# HyperGit 设计草案

假设我要从根本上重新设计一个面向超大规模仓库的 Git-like 系统，目标不是“让 Git 勉强能跑”，而是让它天然支持：

- 亿级文件
- TB/PB 级对象存储
- 百万级提交历史
- 超大 monorepo
- 分布式协作
- 高并发读写
- 并行 checkout / diff / merge / blame / fetch / GC
- 云端索引与本地按需 materialize

我会把它设计成一个内容寻址 + 分层索引 + 懒加载工作区 + 并行执行引擎的系统。

## 1. 现有 Git 的核心问题

Git 的优秀之处是：

> commit / tree / blob 全部内容寻址，天然不可变，适合分布式协作。

但 Git 的历史包袱在超大仓库下非常明显：

1. **tree 是递归结构**  
   大目录 diff、checkout、merge 时需要大量遍历。
2. **工作区是完整物化模型**  
   默认 checkout 出完整文件树，超大 monorepo 会拖垮磁盘和文件系统。
3. **索引 index 是单机文件级结构**  
   `.git/index` 在超大规模下会变成瓶颈。
4. **packfile 更偏批量压缩，不适合细粒度并发访问**  
   对象查找、解压、delta chain 追踪在并发场景下不够理想。
5. **GC / repack 是重量级全局操作**  
   超大仓库下，全局 repack 成本很高。
6. **协议以对象传输为中心，而不是以“用户当前需要的视图”为中心**  
   现代 Git 已经有 `partial clone`、`sparse-checkout`、`commit-graph`、`multi-pack-index`、`Scalar` 等优化，但它们更像增强层，而不是最初的数据模型设计。Git 官方 `sparse-checkout` 允许只检出部分目录；Scalar 通过 `partial clone`、`background maintenance`、`sparse-checkout` 等特性优化大仓库；`multi-pack-index` 用于跨多个 `packfile` 加速对象查找。([Git][1])

## 2. 新系统总体架构：HyperGit

我会设计一个类似下面的架构：

```text
┌──────────────────────────────────────────────┐
│ CLI / IDE / CI / Build System                │
└──────────────────────────────────────────────┘
                    │
┌──────────────────────────────────────────────┐
│ Workspace Engine                             │
│ - sparse materialization                     │
│ - virtual filesystem                         │
│ - local change tracking                      │
└──────────────────────────────────────────────┘
                    │
┌──────────────────────────────────────────────┐
│ Query & Parallel Execution Engine            │
│ - parallel diff                              │
│ - parallel checkout                          │
│ - parallel merge                             │
│ - parallel blame                             │
│ - parallel object prefetch                   │
└──────────────────────────────────────────────┘
                    │
┌──────────────────────────────────────────────┐
│ Metadata Index Layer                         │
│ - commit graph index                         │
│ - path index                                 │
│ - tree segment index                         │
│ - bloom filter index                         │
│ - ownership / module index                   │
└──────────────────────────────────────────────┘
                    │
┌──────────────────────────────────────────────┐
│ Object Storage Layer                         │
│ - content-addressed blobs                    │
│ - chunked files                              │
│ - immutable tree shards                      │
│ - append-only packs                          │
│ - local + remote cache                       │
└──────────────────────────────────────────────┘
                    │
┌──────────────────────────────────────────────┐
│ Remote Object Service / Metadata Service     │
│ - object API                                 │
│ - graph API                                  │
│ - path query API                             │
│ - delta negotiation API                      │
└──────────────────────────────────────────────┘
```

核心思想：

> 不再把仓库看成一个巨大目录树，而是看成一个可查询、可分片、可并行遍历的不可变版本化数据库。

## 3. 数据模型重构

### 3.1 Commit 不只指向 tree，而是指向 Manifest Root

传统 Git：

```text
commit -> root tree -> subtree -> blob
```

新模型：

```text
commit -> manifest root
        -> tree shard index
        -> path segment table
        -> blob/chunk refs
```

Commit 结构：

```text
Commit {
    id: Hash
    parents: [CommitId]
    author
    committer
    message
    timestamp
    manifest_root: ManifestId
    changed_path_summary: BloomFilter
    module_summary: ModuleBitmap
    generation: u64
}
```

新增字段：

- `changed_path_summary`：快速判断某个路径是否可能被该提交影响。
- `module_summary`：快速判断某个模块是否受影响。
- `generation`：加速祖先查询、`merge-base` 查询。
- `manifest_root`：指向分片化文件树。

Git 的 `commit-graph` 本质上已经在做类似“提交历史索引”的事情，新系统会把它变成一等公民，而不是可选优化。

### 3.2 Tree 改成 B+Tree / Merkle Trie

传统 Git tree 是目录递归结构。新模型使用：

```text
Merkle Path Trie / B+Tree
```

路径按段存储：

```text
/src/backend/auth/login.go
=> ["src", "backend", "auth", "login.go"]
```

Manifest 结构：

```text
ManifestNode {
    prefix: PathPrefix
    entries: [Entry]
    children: [ManifestNodeId]
    hash: Hash
}
```

Entry：

```text
Entry {
    name
    type: file | dir | symlink | submodule
    mode
    object_id
    size
    mtime_hint
    content_type
}
```

这样有几个好处：

1. **路径范围查询快**  
   查询 `src/payment/**` 不需要遍历整个仓库。
2. **天然可分片**  
   `src/a-m` 和 `src/n-z` 可以在不同 shard。
3. **diff 可并行**  
   两个 commit 的 manifest root 可以分段比较。
4. **checkout 可并行**  
   不同路径段独立 materialize。
5. **merge 可并行**  
   不同 tree shard 可以独立做三方合并。

### 3.3 大文件是原生 Chunked Blob，而不是外接 LFS

在 HyperGit / 极仓里，大文件不应该像传统 Git 那样作为一个完整 `blob` 直接塞进对象库，也不应该只是外接一个类似 Git LFS 的系统。

核心原则是：

> 大文件 = Blob 元数据 + 内容分块 Chunk + 去重索引 + 按需加载 + 并行传输。

传统 Git 里，一个文件大致是：

```text
file -> blob(hash(content))
```

如果一个 2GB 文件只改了 1MB，Git 仍然会把新版本当成一个新 blob 处理。即使 `pack delta` 能缓解一部分，这个模型对超大文件、二进制文件、局部访问和并发传输都不理想。

HyperGit 中，大文件会变成原生对象链：

```text
LargeFileBlob
    ├── BlobMeta
    ├── ChunkManifest
    ├── Chunk_001
    ├── Chunk_002
    ├── Chunk_003
    └── ...
```

结构类似：

```text
BlobMeta {
    blob_id: Hash
    logical_size: u64
    file_type: binary | text | media | archive | model | dataset
    chunking_strategy: fixed | content_defined
    chunks: [ChunkRef]
    content_fingerprint
    encryption_profile
    dedupe_scope
}
```

每个 chunk：

```text
ChunkRef {
    chunk_id: Hash
    storage_id: Hash
    offset: u64
    logical_size: u32
    stored_size: u32
    ciphertext_checksum
    storage_tier
}
```

底层真实对象仍然是不可变内容寻址对象：

```text
Chunk {
    storage_id: Hash
    encrypted_payload
}
```

这样，大文件的版本对象本身很小，真正的大内容被拆成很多不可变 chunk。直接收益是：

- 大文件小修改不需要重传整个 blob。
- diff 大文件只比较 chunk 或逻辑范围，而不是全量字节。
- 大文件不再外包给 LFS，而是仓库对象模型的一部分。
- 支持并行下载、并行校验、并行解压和范围读取。

#### 3.3.1 内容定义分块优先，固定分块作为回退

对于大文件，我不会只用固定 `4MB` / `8MB` 分块，因为固定分块有一个根本问题：

> 文件头部插入一点内容，后面所有 chunk offset 都变了，去重效果会急剧下降。

因此大文件默认采用 **Content-Defined Chunking, CDC**，也就是根据滚动哈希决定切分点，而不是按固定 offset 切分。

例如：

```text
平均 chunk size: 4MB
最小 chunk size: 512KB
最大 chunk size: 16MB
```

这样如果文件中间插入少量内容，大部分原有 chunk 仍然可以复用。它特别适合：

- 大型二进制文件
- 数据集
- 模型文件
- 视频
- VM 镜像
- 设计资产
- 游戏资源包

固定分块不是被淘汰，而是作为少数格式的回退策略，例如高度随机、不可切分、或内容定义分块收益很低的对象。

#### 3.3.2 小修改只上传变化的 Chunk

假设有一个 `10GB` 文件：

```text
model.bin
```

第一次提交：

```text
model.bin -> 2560 个 chunk，每个约 4MB
```

第二次只改了其中 `20MB` 内容：

```text
新版本 model.bin:
    2555 个 chunk 复用旧版本
    5 个 chunk 新增
```

提交时只需要：

1. 重新计算 chunk manifest。
2. 上传新增 chunk。
3. 新建一个 `BlobMeta`。
4. commit 指向新的 `BlobMeta`。

不会重新上传 `10GB`。

#### 3.3.3 默认懒加载，按需 Hydrate 与 Range Read

默认 checkout 不应该把所有大文件都下载下来。工作区里可以先放一个 lightweight placeholder：

```text
path: assets/model/v3/model.bin
size: 10GB
blob_id: abc123
state: virtual
chunks: not downloaded
```

当用户真的打开文件、构建系统需要文件、或者用户显式执行命令时，才下载内容：

```bash
hgx hydrate assets/model/v3/model.bin
hgx hydrate assets/models/**
hgx dehydrate assets/models/**
```

这点看起来像 Git LFS 的 pointer + pull，但本质区别是：

> HyperGit 的大文件不是外接 LFS，而是原生对象类型。

很多大文件也不需要完整下载。例如视频只预览前几秒、模型只读 header、Parquet 只读 footer、归档文件只读 central directory。

因此对象服务需要支持：

```text
ReadBlobRange(view, blob_id, offset, length)
```

底层根据 offset 映射到 chunk：

```text
offset -> chunk range -> fetch needed chunks only
```

这样 IDE、构建系统、分析工具可以只读必要范围，而不是被迫拉完整对象。

#### 3.3.4 并行上传和下载是默认路径

大文件天然适合并行传输。

上传流程：

```text
1. 扫描文件
2. 并行切 chunk
3. 并行计算 logical_chunk_id / storage_id
4. 并行压缩并加密
5. 查询远端已有 chunk
6. 只上传缺失 chunk
7. 写入 BlobMeta
```

下载流程：

```text
1. 读取 BlobMeta
2. 选择需要的 chunk
3. 按 storage locality 分组
4. 并行下载
5. 并行校验密文完整性
6. 并行解密与解压
7. 顺序组装或按需映射
```

伪代码：

```python
def upload_large_file(path):
    chunks = content_defined_chunk(path)

    missing = remote.find_missing_chunks_in_scope(
        scope_token=current_repo.dedupe_scope_token,
        chunk_storage_ids=[chunk.storage_id for chunk in chunks]
    )

    parallel_upload(missing)

    blob_meta = BlobMeta(
        size=file_size(path),
        chunks=[chunk.ref for chunk in chunks]
    )

    return remote.put_blob_meta(blob_meta)
```

#### 3.3.5 大文件 Diff 要类型感知，Merge 要保守

大文件 diff 不应该默认做全文 diff。系统需要按类型选择策略：

| 文件类型 | Diff 策略 |
| --- | --- |
| 大文本 | 分块行 diff |
| 二进制 | chunk-level diff |
| 图片 | perceptual diff / metadata diff |
| 视频 | metadata + keyframe diff |
| 模型 | tensor metadata diff |
| 数据集 | schema / partition diff |
| 压缩包 | archive index diff |
| 未知二进制 | chunk changed summary |

例如：

```bash
hgx diff model.bin
```

输出不应该是传统文本 diff，而更接近：

```text
model.bin changed
size: 10.2GB -> 10.3GB
chunks: 2560 -> 2581
reused chunks: 2549
new chunks: 32
removed chunks: 11
changed logical ranges:
  1.2GB - 1.3GB
  7.8GB - 7.9GB
```

Merge 则必须更保守：

- **文本大文件**：允许按 chunk + line range 合并；若修改落在不同逻辑范围，可以自动合并。
- **二进制大文件**：默认不做内容级 merge，只做策略判断。
- **可理解格式**：通过插件化 merge driver 处理，例如 `JSON`、`Parquet manifest`、`ONNX`、`Unity asset`、`CAD`、`SQLite`。

默认二进制 merge 规则：

```text
ours changed, theirs unchanged -> take ours
ours unchanged, theirs changed -> take theirs
both changed same blob -> ok
both changed different blob -> conflict
```

核心原则：

> 不懂格式时，不假装智能合并。

#### 3.3.6 去重、冷热分层与安全策略

大文件系统最重要的能力之一是去重，但去重边界必须先于“全局共享”来定义。HyperGit 里，去重不直接建立在“全组织裸 hash 可见”上，而是建立在**授权后的 dedupe scope** 上：

```text
Repo scope    -> 默认，只在单仓库内 dedupe
Tenant scope  -> 同一业务租户内 dedupe
Org scope     -> 明确授权的组织级共享对象池
```

对象标识也分成两层：

```text
logical_chunk_id   = SHA256(plaintext_chunk)
physical_storage_id = HMAC-SHA256(scope_secret, plaintext_chunk)
```

- `logical_chunk_id` 用于内容完整性校验、manifest 引用和跨版本比较。
- `physical_storage_id` 只在服务端存储层和被授权的 dedupe scope 内可见，用于物理去重。
- 客户端不会对“全局对象库”发起裸存在性探测；缺块查询必须携带 scope token，服务端也只能在该授权 scope 内回答是否缺失。

在这个前提下，去重至少分三层：

1. **Chunk 级去重**  
   相同 chunk 只存一次，但物理去重键是 `physical_storage_id`，不是裸内容 hash。
2. **跨文件去重**  
   两个文件共享部分内容时，也能复用 chunk。
3. **跨仓库去重**  
   企业内部多个仓库共用 SDK、数据集、基础模型时，可以在显式授权的 tenant/org scope 内使用共享 chunk store，而不是默认全组织互相探测。

Chunk 还应该支持冷热分层：

```text
Hot: 本地 SSD / 团队缓存
Warm: 区域对象存储
Cold: 归档存储
```

`ChunkRef` 中的 `storage_tier` 用于表达对象当前所在层。典型策略：

- 最近 30 天访问过的 chunk 放热层。
- 主干分支最新版本放热层。
- 老 tag / 旧 release 放冷层。
- CI 常用资源提前预热。

大文件层往往还要承载敏感数据，因此对象层需要支持：

```text
per-path policy
per-blob policy
per-chunk encryption
access audit
quota
retention
```

例如：

```text
/data/customer/**
    require role: data-team
    dedupe-scope: tenant:data-platform
    audit: enabled
    local-cache-ttl: 24h
```

chunk 内容可以独立压缩和加密，但顺序必须固定为“先压缩，再加密，再存储”：

```text
plaintext_chunk
    -> compress
    -> encrypt(chunk_key)
    -> store(ciphertext)
```

校验链也要分层：

```text
logical_chunk_id    -> 约束明文内容身份
ciphertext_checksum -> 约束传输与落盘完整性
```

`BlobMeta` 只记录加密 key reference，而不是直接存 key；真正的数据面校验先验证密文完整性，再解密并验证 `logical_chunk_id`。

#### 3.3.7 与 Git LFS 的区别和默认阈值

Git LFS 的模型大致是：

```text
Git blob = pointer file
LFS server = real large object
```

HyperGit 的模型是：

```text
Commit -> Manifest -> BlobMeta -> Chunks
```

区别：

| 能力 | Git LFS | HyperGit 大文件模型 |
| --- | --- | --- |
| 是否原生对象 | 否 | 是 |
| Chunk 级去重 | 通常不是核心模型 | 是 |
| Range read | 不一定 | 原生支持 |
| 并行下载 | 有限 | 原生支持 |
| 大文件 diff | 弱 | 类型感知 |
| 大文件 merge | 弱 | 插件化 |
| 存储分层 | 外部实现 | 原生 |
| 权限审计 | 依赖 LFS 服务 | 原生 |
| 与 manifest 集成 | 弱 | 强 |
| 部分 checkout | 依赖额外机制 | 默认模型 |

推荐默认策略：

```text
小于 8MB：普通 blob
8MB - 128MB：chunked blob，可直接 hydrate
大于 128MB：large blob，默认 lazy
大于 1GB：large blob + explicit hydrate
```

示例：

```text
README.md              -> normal blob
src/app/main.go        -> normal blob
assets/logo.psd        -> chunked blob
dataset/train.parquet  -> large chunked blob
model/checkpoint.bin   -> large chunked blob, lazy by default
```

也可以通过配置覆盖：

```toml
[large_file]
threshold = "8MB"
chunk_avg_size = "4MB"

[[large_file.rule]]
pattern = "*.parquet"
strategy = "chunked"
diff = "parquet-aware"

[[large_file.rule]]
pattern = "*.onnx"
strategy = "chunked"
diff = "model-metadata"

[[large_file.rule]]
pattern = "*.zip"
strategy = "whole-object"
diff = "archive-index"
```

一句话总结：

> HyperGit 不把大文件当成 Git blob，也不把它外包给 LFS，而是把它建模成原生的 chunked blob：支持内容定义分块、跨版本去重、按需加载、范围读取、并行传输、冷热存储、类型感知 diff 和插件化 merge。

### 3.4 发布视图与一致性模型

如果索引成为核心读路径，就必须先定义一致性边界。系统需要明确区分四类数据：

- **权威对象**：`Commit`、`Manifest`、`Blob Metadata`、`Chunk`，是最终事实来源。
- **最小同步发布索引**：`commit graph delta`、`manifest shard locator`、`changed path bloom`、changed-path 的 L0 posting list；它们必须和 ref 发布保持同一快照。
- **延迟构建的服务加速索引**：完整 `tree segment map`、大范围 path fanout cache、模块聚合 posting，可在 ref 发布后补齐，但查询必须能回退到权威对象路径。
- **异步分析索引**：`DependencyIndex`、深度 `LineageIndex`、热度统计、预取提示，可以落后于最新提交，但必须显式带版本。

查询不直接对“最新对象集合”执行，而是对一个已发布视图执行：

```text
PublishedView {
    view_id: Hash
    head_commit: CommitId
    manifest_root: ManifestId
    serving_index_snapshot: IndexSnapshotId
    optional_index_watermarks: {
        lineage: u64
        dependency: u64
    }
    created_at
}
```

约束如下：

1. `push` 先上传权威对象，再构建**最小同步发布索引**并生成 `PublishedView`，最后原子发布 ref；只有这一小组索引会阻塞 ref 可见性。
2. 多步操作必须绑定同一个 `view_id`；一次 `checkout`、`diff`、`merge`、`blame`、IDE 浏览会话不能在中途漂到另一个索引快照上。
3. 延迟构建的服务加速索引和异步分析索引都允许滞后，但查询结果必须返回自己的 watermark；若所需索引未追平，则退化到较慢但正确的权威对象路径。
4. 同步发布阶段必须有明确预算，例如“单次 push 只同步触达 changed shards”；超过预算的二级索引自动转入后台任务，不能无限期阻塞提交发布。
5. 任意索引都必须可从权威对象重建；索引损坏只能影响性能，不能改变仓库事实。

## 4. 存储层设计

### 4.1 对象分层

对象分四类：

```text
Commit Object
Manifest Object
Blob Metadata Object
Chunk Object
```

每类对象有不同存储策略：

| 类型 | 特点 | 存储策略 |
| --- | --- | --- |
| Commit | 小、频繁查询 | 热索引 + KV |
| Manifest | 中等、结构化 | 分片 + Merkle |
| Blob Metadata | 中等 | KV + cache |
| Chunk | 大、不可变 | 对象存储 / pack / CDN |

### 4.2 Packfile 改为 Segment Pack

传统 `packfile` 是大包。新设计：

```text
PackSegment {
    segment_id
    object_type
    locality_key
    objects[]
    index
    bloom
}
```

按 locality 分组：

- 按路径模块：`src/payment`
- 按时间窗口：`2026-W20`
- 按对象类型：`commit` / `manifest` / `blob` / `chunk`
- 按热度：`hot` / `warm` / `cold`

这样可以做到：

- 查询某个模块只打开相关 pack segment。
- 后台 compaction 可以局部执行。
- GC 不需要全仓库 stop-the-world。
- 多线程可以独立读取不同 segment。

### 4.3 多级缓存

```text
L1: 进程内对象 cache
L2: 本地磁盘 object cache
L3: 局域网 / 团队共享 cache
L4: 远程对象服务
L5: 冷对象归档存储
```

开发者 `clone` 时不再下载完整仓库，而是：

```text
clone = 下载 commit graph + manifest root + 当前 sparse profile
```

这与 Git `partial clone` 的方向一致：`partial clone` 的目标就是不在初始 `clone` 时下载所有对象，而是在需要时再取对象；Scalar 也通过 `partial clone` 和 background prefetch 降低大仓库操作成本。([GitHub][2])

### 4.4 对象生命周期、Lease 与回收边界

只看 refs 做可达性分析是不够的，因为工作区、后台任务和进行中的查询都会临时依赖尚未物化的对象。

因此系统需要显式 lease：

```text
ObjectLease {
    lease_id
    holder_type: workspace | fetch | merge | blame | prefetch | gc_reader
    root_view: ViewId
    pinned_commits: [CommitId]
    pinned_manifest_shards: [ManifestNodeId]
    pinned_segments: [SegmentId]
    expires_at
    renew_token
}
```

规则：

1. `clone` / `checkout` 会为当前 `base_commit` 和对应 `PublishedView` 建立长租约，哪怕文件尚未 materialize。
2. `fetch`、`merge`、`blame`、后台 prefetch 只拿短租约，但在任务执行期间自动续租。
3. `dehydrate` 可以删除本地副本，但不能立即释放逻辑 pin；只有当工作区基线前移或工作区关闭后，租约才能真正释放。
4. Compaction 采用 copy-forward：先写新 segment，再发布新索引映射；旧 segment 只有在其小于全局 lease watermark 后才能回收。
5. 冷归档和删除都基于“refs 可达性 + 活跃 lease + 正在运行的后台任务”三者的并集，而不是只看 head refs。

## 5. 工作区设计：虚拟化，而不是完整 checkout

### 5.1 Workspace Manifest

本地工作区不再默认拥有所有文件，而是有一个 workspace manifest：

```text
Workspace {
    base_commit
    sparse_profile
    materialized_paths
    dirty_paths
    virtual_paths
}
```

用户看到的是完整目录树，但真正落盘的只有：

- 用户打开过的文件
- build 需要的文件
- sparse profile 指定的文件
- 最近修改过的文件

这类似 `sparse-checkout` 的思想，但设计成默认模型。Git `sparse-checkout` 的官方描述是：只让工作树包含被选择的路径子集，通常可按目录 cone 模式选择。([Git][1])

### 5.2 VFS / Lazy Materialization

访问文件时：

```text
open("src/payment/foo.go")
    -> workspace engine 检查本地是否有
    -> 没有则查询 manifest
    -> 下载 blob chunks
    -> materialize 到本地
    -> 返回文件句柄
```

对 IDE 和构建系统暴露：

```text
完整路径空间 + 按需文件内容
```

对磁盘暴露：

```text
部分真实文件 + 虚拟占位
```

仅拦截 `open()` 还不够，workspace engine 还必须原生回答目录与元数据查询：

- `stat` / `lstat`：直接由 manifest 返回，不强制下载文件内容。
- `readdir` / 递归 walk：直接遍历 manifest shard；必要时只 hydrate 目录元数据，不 hydrate 文件 payload。
- `glob` / include 扫描：优先在 manifest 上执行，避免构建系统先全盘遍历再触发海量 materialize。
- synthetic inode：对虚拟路径生成稳定 inode 映射，避免 IDE、watcher、增量编译器把同一路径误判成新文件。

### 5.3 目录枚举、Glob 与 Watcher 语义

如果目标是“用户看到完整目录树”，那就必须把下面这些语义定义完整：

1. **目录枚举是虚拟化的一等能力**  
   不允许因为工具做了 `readdir()` 就被迫批量下载文件内容；目录项和基础元数据应该来自 manifest。
2. **watch 不能只依赖底层文件系统事件**  
   对尚未 materialize 的路径，workspace engine 要能发出 synthetic create/modify/delete 事件；本地 watcher 丢事件时要能回放日志并做 reconcile。
3. **大规模扫描要区分“元数据 hydrate”和“内容 hydrate”**  
   构建系统可以先拿完整目录和属性视图，再按需 materialize 真正要读取的文件。
4. **跨平台文件系统差异必须前置建模**  
   例如大小写敏感/不敏感、inode 语义、符号链接能力、执行位语义，不能等到 merge 或 checkout 时才暴露。

### 5.4 本地变更单独存储

不要直接依赖全量 working tree 扫描。

维护一个本地变更数据库：

```text
LocalChangeDB {
    path
    base_object
    working_hash
    status
    last_seen_inode
    last_seen_mtime
    watcher_seq
    reconcile_epoch
}
```

配合文件系统 watcher：

- 新增文件直接记录
- 修改文件增量 hash
- 删除文件记录 tombstone
- watcher 是 fast path，不是唯一事实来源
- status 不需要扫全仓库，但要支持后台分片 reconcile 来纠正漏事件、系统崩溃和跨平台 watcher 差异

## 6. 并行处理核心设计

### 6.1 并行 diff

传统：

```text
递归比较 tree
```

新模型：

```text
diff(commitA, commitB, pathspec):
    rootA = manifest(A)
    rootB = manifest(B)
    tasks = split_by_manifest_shard(rootA, rootB, pathspec)
    parallel_map(diff_shard, tasks)
    merge_results()
```

伪代码：

```rust
fn diff_commits(a: CommitId, b: CommitId, pathspec: PathSpec) -> DiffResult {
    let shards = planner.plan_manifest_diff(a.manifest_root, b.manifest_root, pathspec);

    parallel(shards, |shard| {
        diff_manifest_shard(shard.left, shard.right)
    }).reduce(DiffResult::merge)
}
```

优化点：

- manifest node hash 相同，整段跳过。
- bloom filter 显示路径不可能变化，跳过。
- path index 直接定位相关 shard。
- 大文件 diff 按 chunk 并行。

### 6.2 并行 checkout

```text
checkout(commit, sparse_profile):
    target_manifest = get_manifest(commit)
    plan = compare(workspace_manifest, target_manifest)
    tasks = partition_by_directory_or_pack_locality(plan)
    parallel_execute(tasks)
```

每个任务：

```text
Task {
    paths: [Path]
    required_objects: [ObjectId]
    pack_segments: [SegmentId]
}
```

执行：

1. 批量下载对象。
2. 并行解压。
3. 并行写文件。
4. 原子更新 workspace manifest。

避免每个文件单独 round-trip。

### 6.3 并行 merge

三方合并：

```text
base, ours, theirs
```

先按 manifest shard 分区：

```text
merge(base, ours, theirs):
    namespace_conflicts = preflight_namespace_scan(base, ours, theirs)
    shards = align(base.manifest, ours.manifest, theirs.manifest)
    parallel_map(merge_shard, shards)
    combine_manifest()
    reconcile_global_renames_and_modes()
```

不同路径之间只有在通过全局 namespace preflight 后，才可以安全并行。

冲突分四类：

1. **同路径内容冲突**
2. **rename / delete 冲突**
3. **命名空间冲突**：`file <-> dir`、目录级 rename、大小写折叠冲突、symlink / submodule 边界冲突、mode 冲突
4. **跨路径语义冲突**

因此 merge planner 至少要分三阶段：

1. **全局预处理**：扫描改动路径集，建立 rename graph，检测 namespace 冲突。
2. **shard 内并行合并**：对已证明相互独立的 shard 做内容级三方合并。
3. **全局收敛**：统一处理目录 rename、mode 变化、平台相关约束，再生成最终 manifest。

前 3 类冲突由版本系统保证语义一致；第 4 类再交给语言服务 / build graph / test selection。

### 6.4 并行 blame

Blame 最大的问题是历史路径追踪昂贵。

新模型维护：

```text
LineageIndex {
    path
    commit_range
    content_fingerprint
    previous_path
    chunk_line_map
}
```

执行：

```text
blame(file):
    chunks = split_file_into_line_chunks(file)
    parallel_map(blame_chunk, chunks)
```

每个 chunk 优先通过 `LineageIndex` 做内容 fingerprint 回溯；若对应索引尚未追平当前 `view_id`，则回退到较慢的 manifest diff / path history 组合路径，而不是返回不一致结果。

### 6.5 并行 fetch / push

Fetch 不再是“给我这些 commit 及其可达对象”，而是：

```text
client:
    have commit graph frontier
    want refs
    want path profile
    want blob policy
```

协议：

```text
FetchRequest {
    have_commits
    want_refs
    base_view
    sparse_profile
    blob_filter
    max_pack_segment_size
    client_cache_summary
}
```

服务端返回：

```text
FetchResponse {
    published_view
    commit_graph_delta
    manifest_delta
    object_segments
    prefetch_hints
}
```

这样服务端可以只返回：

- 新 commit
- 相关 manifest shard
- 用户 sparse profile 需要的 blob/chunk
- 未来可能需要的预取提示

## 7. 索引系统是一等公民

### 7.1 Commit Graph Index

```text
CommitGraphIndex {
    commit_id
    generation
    parents
    changed_paths_bloom
    module_bitmap
    timestamp
}
```

用途：

- `merge-base`
- `log -- path`
- `branch contains`
- blame
- `bisect`
- CI affected target selection

Git 的 Scalar 已经通过开启高级配置、后台维护等方式让大仓库更可用；在新设计里，这些索引和维护任务应该是核心机制，而不是额外工具。([Git][3])

### 7.2 Path History Index

`log -- path` 和 `blame` 想要在超大规模下可用，必须承认它们对索引的要求并不相同。因此 path history 不能只有一层：

- **L0 强一致路径索引**：提交时同步写入，只记录“哪些 path 在哪些 commit 里被显式修改/删除”，以及廉价的 rename hint。
- **L1 异步 lineage 索引**：后台构建内容 fingerprint、chunk-line map、重命名图和跨路径 lineage，用于快速 blame 和高质量 rename 追踪。

```text
PathHistoryIndex {
    path_hash
    commits_that_changed_path
    delete_events
    rename_hints
    lineage_shards
}
```

维护策略：

1. 写入路径只要求 L0 就绪，这样不会把 `push` 成本放大到不可接受。
2. L1 由后台 worker 按 changed shard 增量构建，并带独立 watermark。
3. `log -- path` 默认可只依赖 L0；`blame`、深度 rename 跟踪优先用 L1，若 L1 落后则显式回退到慢路径。
4. 显式 rename 操作、目录级移动、批量格式化等高噪声场景要记录额外 hint，否则纯查询时推断会非常昂贵。

让下面操作变成索引查询：

```bash
hgx log -- src/payment/foo.go
hgx blame src/payment/foo.go
hgx diff main...feature -- src/payment
```

### 7.3 Build / Ownership Index

超大仓库最重要的问题不是“所有文件是什么”，而是：

> 我的改动影响什么？

维护：

```text
DependencyIndex {
    source_path
    build_targets
    reverse_dependencies
    owners
    test_targets
}
```

这让系统能支持：

```bash
hgx affected tests
hgx affected owners
hgx affected builds
```

## 8. 并发写入与引用模型

Git refs 本质是指针：

```text
refs/heads/main -> commit
```

新系统中 ref update 必须支持高并发，但 native serving 层不能只存“`ref -> commit`”，还要存“这个 ref 当前暴露的是哪个已发布视图”。

设计：

```text
RefStore {
    ref_name
    target_commit
    published_view
    version
    lease_token
}
```

更新使用 CAS：

```text
update_ref(ref, old_commit, new_commit):
    compare_and_swap(
        ref.target_commit,
        ref.published_view,
        old_commit,
        new_commit,
        new_view
    )
```

Push 流程：

1. 客户端上传新对象。
2. 服务端校验对象完整性。
3. 服务端只构建最小同步发布索引，并生成 `PublishedView`。
4. 服务端校验权限、策略、CI gate。
5. CAS 更新 `ref -> (target_commit, published_view)`。
6. 延迟服务索引和分析索引在后台继续追平，并把 watermark 绑定到同一个 `view_id`。
7. 若第 5 步失败，则返回最新 ref，让客户端 rebase/merge；后台索引任务也必须按 `view_id` 幂等收敛，避免对失败发布做无用放大。

## 9. GC / Compaction 设计

传统全局 GC 在超大仓库里非常危险。新设计使用分代 compaction：

```text
Generation 0: recent loose segments
Generation 1: daily compacted segments
Generation 2: weekly compacted segments
Generation 3: cold archival segments
```

GC 原则：

- append-only 写入
- 后台局部 compaction
- 对象引用计数或可达性 bitmap
- 以 active lease watermark 作为真正回收下界
- pack segment 级别回收
- 冷对象迁移到低成本存储
- 永不阻塞前台读写

## 10. 网络协议重新设计

不要只传 Git object，要传“查询结果”。

协议能力：

```text
Capability {
    partial_materialization
    manifest_query
    path_history_query
    chunked_blob
    parallel_pack_segments
    server_side_diff
    server_side_merge_base
    prefetch_hints
}
```

典型请求：

```text
GetManifest(view, pathspec)
GetBlob(view, blob_id, range/chunks)
GetDiff(viewA, viewB, pathspec)
GetCommitGraph(frontier, view)
GetPathHistory(path, since, view)
GetPackSegments(object_ids, view)
```

这会把远端从“文件服务器”升级为“版本数据库服务”。

## 11. 命令层体验

用户命令保持类似 Git。本文统一假设 CLI 名称为 `hgx`：

```bash
hgx clone repo
hgx checkout main
hgx status
hgx diff
hgx commit
hgx push
```

但默认行为不同：

```bash
hgx clone repo
```

只下载：

- refs
- commit graph head slice
- root manifest
- 默认 sparse profile

新增命令：

```bash
hgx sparse add src/payment
hgx sparse remove legacy/
hgx prefetch //team/payment
hgx hydrate src/payment/**
hgx dehydrate third_party/**
hgx affected tests
hgx doctor performance
```

## 12. 关键算法示例

### 12.1 Manifest Diff

```python
def diff_manifest(a, b):
    if a.hash == b.hash:
        return []

    if a.is_leaf() and b.is_leaf():
        return diff_entries(a.entries, b.entries)

    tasks = align_children(a.children, b.children)

    return parallel_reduce(
        tasks,
        lambda pair: diff_manifest(pair.left, pair.right),
        merge_diff_results
    )
```

复杂度从：

```text
O(total files)
```

变成接近：

```text
O(changed shards + touched path range)
```

### 12.2 Sparse Checkout Planner

```python
def checkout_plan(current, target, sparse_profile):
    target_paths = target.query(sparse_profile)
    current_paths = current.materialized_paths

    to_add = target_paths - current_paths
    to_remove = current_paths - target_paths
    to_update = changed_between(current, target, target_paths)

    return partition_by_pack_locality(to_add + to_update + to_remove)
```

### 12.3 Parallel Object Fetch

```python
def fetch_objects(object_ids):
    groups = group_by_pack_segment(object_ids)

    return parallel_map(groups, lambda group: {
        segment = download_segment(group.segment_id)
        return extract_objects(segment, group.object_ids)
    })
```

## 13. 与现有 Git 的兼容策略

完全推翻 Git 生态不现实，所以我会设计三层兼容：

### 第一层：Git Compatible Mode

这是一个兼容网关，不是把 native 对象模型原样暴露给 Git 客户端。它支持：

```bash
git clone
git fetch
git push
```

约束与语义如下：

- `git clone` / `git fetch` 读取的是某个 `PublishedView` 的确定性 Git 导出结果，导出对象 id 在该兼容视图内稳定，但不要求与 native object id 相同。
- `git push` 只允许进入开启兼容模式的 refs；服务端先把 Git tree/blob/commit 导入 native manifest/object 模型，再走同一套 ref CAS 发布流程。
- native chunked blob 在兼容导出时按策略降级：小对象导出为普通 Git blob，大对象导出为普通 blob 或 Git LFS pointer，取决于仓库策略。
- virtual workspace、server-side diff、范围读取、路径级查询等 native 能力不会透传给 Git 客户端；兼容层的目标是互操作，不是保留全部语义。

### 第二层：Enhanced Git Mode

基于现有 Git 功能：

- `partial clone`
- `sparse-checkout`
- `commit-graph`
- `multi-pack-index`
- `background maintenance`
- `FSMonitor`
- `bitmap index`

这和 Scalar 的方向一致：Scalar 是通过配置高级 Git 特性、后台维护、减少网络传输来优化大仓库使用体验。([Git][3])

### 第三层：Native HyperGit Mode

启用新协议：

- manifest query
- chunked blob
- path history index
- server-side diff
- virtual workspace
- parallel checkout / merge / blame

## 14. 我会特别避免的设计

不建议只做这些：

1. **只把仓库拆成多个 repo**  
   会破坏原子提交、跨模块重构和统一版本视图。
2. **只上 Git LFS**  
   LFS 解决大文件，不解决亿级小文件、历史查询、checkout、diff、merge。
3. **只做 shallow clone**  
   shallow clone 影响历史操作，不适合长期开发工作区。
4. **只做 CI 缓存**  
   只能优化构建，不解决开发者本地体验。
5. **只靠更强机器**  
   这是把架构问题变成硬件问题。

## 15. 最终架构原则

我会把系统原则定为：

```text
1. 所有大对象不可变
2. 所有树结构可分片
3. 所有路径查询走索引
4. 所有文件内容按需加载
5. 所有耗时操作可切分为任务图
6. 所有后台维护增量化
7. 所有网络传输基于用户实际工作集
8. 所有 ref 更新使用 CAS
9. 所有本地状态显式记录，不靠全量扫描
10. 所有大型操作默认并行
```

一句话总结：

> 新系统不是“更快的 Git”，而是把 Git 的内容寻址思想保留下来，把目录树、对象存储、工作区、协议、索引和执行引擎全部改造成面向超大规模仓库的并行版本数据库。

[1]: https://git-scm.com/docs/git-sparse-checkout?utm_source=chatgpt.com "Git - git-sparse-checkout Documentation"
[2]: https://github.com/microsoft/scalar?utm_source=chatgpt.com "microsoft/scalar: Scalar: A set of tools and ..."
[3]: https://git-scm.com/docs/scalar?utm_source=chatgpt.com "Git - scalar Documentation"
