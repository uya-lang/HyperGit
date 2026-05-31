# HyperGit / 极仓系统设计

状态：设计版 v0.1 / 已发布里程碑 `v0.1.0`（2026-05-31）
目标实现语言：纯 Uya  
本机工具链：默认使用 `/home/winger/xyglasses/uya/bin/uya`，也可通过 `UYA_BIN` 覆盖；当前 `uya --version` 显示版本 `v0.9.7`
命令行入口：`hgx`

## 1. 项目定位

HyperGit / 极仓是一个面向超大规模仓库的 Git-like 版本控制系统。它保留 Git 最重要的精神：内容寻址、不可变对象、分布式协作和本地优先；但数据模型、索引、工作区和协议从一开始就按亿级文件、TB/PB 级对象、百万级提交历史和高并发读写来设计。

一句话目标：

> 把仓库从“巨大目录树”重构为“可查询、可分片、可并行执行的版本化内容数据库”。

核心用户场景：

- 超大 monorepo 的日常开发。
- CI / 构建系统只拉取受影响工作集。
- IDE 浏览和搜索巨大仓库时按需 materialize。
- 大文件、数据集、模型、设计资产作为一等对象管理。
- 服务端提供 manifest query、path history query、server-side diff 和按需对象传输。

非目标：

- 不做 Git 的小修小补包装层。
- 不以“完整 checkout 全仓库”为默认模型。
- 不把大文件完全外包给 Git LFS 式旁路系统。
- 不依赖外部 GC 语言运行时、JVM、Node、Python 服务作为核心实现。

## 2. 纯 Uya 实现约束

HyperGit 的核心实现必须使用 Uya 语言完成。C99 后端只是 Uya 编译产物，不是业务实现语言。

允许的边界：

- Uya 标准库：`std.crypto`、`std.collections`、`std.io`、`std.json`、`std.protobuf`、`std.http`、`std.async`、`std.thread`、`std.mem`。
- OS / libc FFI：文件、目录、mmap、socket、poll/epoll、时间、进程退出码等系统边界。
- C99 后端：用于可移植编译、调试生成代码和性能剖析。

不允许的核心依赖：

- 不用 Rust/C++/Go/Python 实现对象库、索引、协议、diff、merge 或工作区核心。
- 不把 SQLite/RocksDB/LevelDB 作为第一版必要存储核心；可以在未来做可选后端。
- 不用外部 Git 命令作为 native 功能的真实执行路径；Git 兼容层只能是导入/导出或网关。

Uya 语言特性在本项目中的使用原则：

- `!T` 显式错误联合：所有 IO、解析、校验、网络、存储操作返回显式错误。
- `defer` / `errdefer`：文件句柄、segment writer、arena、lease token 必须显式释放。
- `atomic T`：worker 计数、队列状态、引用发布版本、后台任务状态使用原子字段。
- `interface`：对象存储、索引、传输、工作区后端通过接口解耦。
- 泛型 `<T>`：arena vector、hash map、result collector、bounded queue 使用通用容器。
- 无 GC：热路径以 arena、固定缓冲区、对象池和显式 drop 为基础。

## 3. 总体架构

```text
┌──────────────────────────────────────────────────────────┐
│ CLI / IDE Adapter / CI Adapter                           │
│ hgx clone/status/diff/commit/push/hydrate/affected        │
└─────────────────────────────┬────────────────────────────┘
                              │
┌─────────────────────────────▼────────────────────────────┐
│ Workspace Engine                                          │
│ sparse profile / local change db / lazy materialization   │
└─────────────────────────────┬────────────────────────────┘
                              │
┌─────────────────────────────▼────────────────────────────┐
│ Query + Parallel Execution Engine                         │
│ diff / checkout / merge / blame / fetch / prefetch         │
└─────────────────────────────┬────────────────────────────┘
                              │
┌─────────────────────────────▼────────────────────────────┐
│ Index Layer                                               │
│ commit graph / manifest shard / path history / bloom       │
└─────────────────────────────┬────────────────────────────┘
                              │
┌─────────────────────────────▼────────────────────────────┐
│ Object Storage                                            │
│ content objects / chunked blobs / segment packs / cache    │
└─────────────────────────────┬────────────────────────────┘
                              │
┌─────────────────────────────▼────────────────────────────┐
│ Remote Service                                            │
│ object API / graph API / manifest API / pack protocol      │
└──────────────────────────────────────────────────────────┘
```

架构原则：

- 对象不可变，引用可变。
- 对象内容寻址，引用更新 CAS。
- manifest 可分片，路径查询不全树扫描。
- 工作区默认懒加载，文件内容按需 hydrate。
- 索引是一等数据结构，但任何索引都可从权威对象重建。
- 大操作拆成任务图，目标是默认并行执行；在 worker pool 和取消/聚合语义未落地前，允许先以串行路径保证正确性。
- 本地与远端共享同一对象模型，协议传输“视图和查询结果”，不只是裸对象。

## 4. 当前源码布局

当前实现采用 `src/hypergit` 作为核心库模块树，`src/hgx` 作为 CLI 模块根。`src/hgx` 中的 `core`、`crypto`、`index`、`large`、`manifest`、`object`、`workspace` 是指向 `src/hypergit` 对应目录的符号链接；CLI 命令通过这些镜像模块名编译，避免维护两套核心实现。

```text
src/
  hgx/
    main.uya                 # CLI 入口和命令分派
    cli/
      cli.uya
    commands/
      init.uya
      status.uya
      add.uya
      commit.uya
      diff.uya
      checkout.uya
      dehydrate.uya
      doctor.uya
      errors.uya
      hydrate.uya
      log.uya
      sparse.uya
      version.uya
      fetch.uya
      push.uya
      help.uya
    store/
      file_remote.uya
      head_ref.uya
      repo_layout.uya
    core -> ../hypergit/core
    crypto -> ../hypergit/crypto
    index -> ../hypergit/index
    large -> ../hypergit/large
    manifest -> ../hypergit/manifest
    object -> ../hypergit/object
    workspace -> ../hypergit/workspace
  hypergit/
    core/
      ids.uya                # Hash / ObjectId / CommitId / ManifestId
      codec.uya              # canonical binary codec
      policy.uya             # policy id placeholder
    crypto/
      blake3.uya
    object/
      types.uya              # Commit / Manifest / Blob / Chunk
      hash.uya               # domain separated hash
      validate.uya           # 对象结构校验
      codec.uya
      commit_build.uya
      small_blob.uya
    store/
      object_store.uya       # ObjectStore interface
      loose_store.uya        # 开发期 loose object
      composite_store.uya
      segment_pack.uya       # segment pack 读写
    manifest/
      trie.uya
      shard.uya
      root.uya
      path.uya
      load.uya
      query.uya
      diff.uya
      flat_diff.uya
    index/
      commit_graph.uya
    workspace/
      checkout_plan.uya
      file_hash.uya
      local_change_file.uya
      local_view.uya
      reconcile.uya
      scan.uya
      sparse_profile.uya
      stage.uya
      stage_file.uya
      stage_view.uya
      state.uya
      state_file.uya
    exec/
      control.uya
      queue.uya
      task.uya
      worker_pool.uya
    protocol/
      frame.uya
      fetch.uya
      http_remote.uya
      published_view.uya
      push.uya
      ref_cas.uya
      request_id.uya
    large/
      chunker.uya
      chunk_hash.uya
      chunk_manifest.uya
      chunk_store.uya
      config.uya
      prepare.uya
      range_read.uya
    merge/
      planner.uya
      result_manifest.uya
      text_merge.uya
    git/
      interop.uya
    test_*.uya               # 核心库 Uya 测试
  tests/
    test_*.sh                # CLI / 端到端 shell 测试
bench/
  bench_*.sh                 # 外层基准脚本
```

包命名以稳定语义为准，避免把实现细节暴露到公共模块名里。例如 `store.segment_pack` 可以替换实现，但 `core.ids.ObjectId`、`manifest.query`、`workspace.stage`、`workspace.sparse_profile` 应保持稳定。

## 5. 本地仓库布局

HyperGit 本地元数据目录使用 `.hgit/`，避免与 `.git/` 混淆：

```text
.hgit/
  config.json
  refs/
    heads/main
    remotes/origin/main
  objects/
    loose/
      ab/cdef...
    packs/
      seg-000001.hgp
      seg-000001.hgi
  indexes/
    commit-graph.hgi
    manifest-locator.hgi
    path-history-l0.hgi
  workspace/
    state.json
    sparse.json
    stage.hgi
    local-change.hgi
    leases.json
  cache/
    chunks/
    manifests/
```

本地文件分三类：

- 权威对象：`objects/` 下的不可变对象和 pack segment。
- 可重建索引：`indexes/` 下的 commit graph、manifest locator、path history。
- 工作区状态：`workspace/` 下的 sparse profile、stage、materialized path、dirty path、lease。

## 6. 核心标识和对象模型

对象 ID 使用 domain-separated hash。第一版推荐使用 32 字节 BLAKE3 或 SHA-256；Uya 标准库已提供 `std.crypto.blake3` 和 `std.crypto.sha256`，具体实现可先抽象为 `HashAlgorithm`。

下面的 Uya 片段默认可引入：

```uya
use std.collections.vec.Vec;
```

```uya
export struct Hash32 {
    bytes: [byte: 32]
}

export struct ObjectId {
    hash: Hash32
}

export struct CommitId {
    id: ObjectId
}

export struct ManifestId {
    id: ObjectId
}

export struct BlobId {
    id: ObjectId
}

export struct PublishedViewId {
    hash: Hash32
}
```

以下 Uya 片段以“对象 payload”视角表达数据模型，接近实现结构，但不是完整可编译模块。内容寻址对象的 `ObjectId`、manifest Merkle hash 和其他自派生标识不写入它自己的 canonical payload，而是放在对象文件名、索引、ref、内存 wrapper 或查询上下文里，避免 hash 自引用。

存储边界可以抽象为：

```uya
export struct StoredObject<T> {
    object_id: ObjectId,
    payload: T
}
```

对象外壳统一包含版本、类型、长度和校验：

```uya
export enum ObjectKind {
    Commit,
    ManifestNode,
    BlobMeta,
    Chunk,
    RefSnapshot,
    IndexBlock
}

export struct ObjectEnvelope {
    magic: u32,
    version: u16,
    kind: ObjectKind,
    flags: u16,
    payload_len: u64,
    payload_hash: Hash32
}
```

Hash 输入必须包含 domain，避免不同对象类型在相同 payload 下混淆：

```text
hash("hypergit.commit.v1" || canonical_commit_payload)
hash("hypergit.manifest.v1" || canonical_manifest_payload)
hash("hypergit.chunk.v1" || plaintext_or_ciphertext_policy_payload)
```

## 7. Commit 与 Published View

Commit 不直接指向递归 tree，而是指向 manifest root。

```uya
export struct CommitPayload {
    parents: Vec<CommitId>,
    author: Identity,
    committer: Identity,
    message: Vec<byte>,
    timestamp_ms: i64,
    manifest_root: ManifestId,
    changed_path_bloom: BloomFilter,
    module_bitmap: ModuleBitmap,
    generation: u64
}
```

`generation` 用于祖先查询和 merge-base；`changed_path_bloom` 用于快速判断某个 pathspec 是否可能受提交影响；`module_bitmap` 用于 CI affected target。

远端和本地引用不只发布 commit，还发布一致性视图：

```uya
export struct PublishedView {
    head_commit: CommitId,
    manifest_root: ManifestId,
    serving_index_snapshot: ObjectId,
    lineage_watermark: u64,
    dependency_watermark: u64,
    created_at_ms: i64
}
```

引用更新模型：

```text
refs/heads/main -> (target_commit, published_view_id, version)
```

更新必须走 CAS：

```text
old ref version + expected commit + new commit + new published_view_id -> compare-and-swap
```

这样一次 checkout、diff、blame、IDE 浏览会话可以绑定同一个 `PublishedViewId`，不会在中途读到两个索引快照。

## 8. Manifest：分片化 Merkle Path Trie

传统 Git tree 是递归目录对象。HyperGit 使用按路径排序的 Merkle Path Trie / B+Tree 风格 manifest。路径按 segment 处理，例如：

```text
src/backend/auth/login.uya -> ["src", "backend", "auth", "login.uya"]
```

### 8.1 Path normalization 跨平台规则

所有写入 manifest、stage、pathspec matcher 和索引的路径，都先归一化为“仓库相对 UTF-8 byte path”。规范化结果永远使用 `/` 作为 separator，不依赖宿主平台的本地路径表示。

| 场景 | Canonical 规则 | Windows / macOS / Linux 备注 |
| --- | --- | --- |
| 分隔符 | 输入中的 `\`、`/` 和重复分隔符都先按 segment separator 处理，输出统一为 `/` | Windows 工作区路径先转成 `/`；POSIX 平台保持 `/` |
| 相对路径约束 | 只接受仓库相对路径；`/foo`、`C:\foo`、`\\server\share`、`~/foo` 一律拒绝 | 三平台统一报绝对路径错误，不做“帮你截成相对路径”的隐式修复 |
| `.` segment | 头部 `./` 和中间 `.` segment 在归一化时移除 | `./src/./main.uya` 归一化为 `src/main.uya` |
| `..` segment | 任意位置出现 `..` 都直接拒绝，不做折叠 | 防止 path traversal，供 `add`、`checkout`、`hydrate` 和远端输入共用 |
| 空 segment / 尾部分隔符 | 空 segment 折叠；尾部分隔符移除；仓库根保持空路径而不是 `.` | `foo//bar/` 归一化为 `foo/bar` |
| 编码 | 路径必须是有效 UTF-8；归一化后保留原始 code point 序列，不做 NFC/NFD 重写 | macOS 额外做 NFD/NFC 冲突检测，但不会静默改写对象路径 |
| 大小写 | canonical bytes 保留原大小写，不做 case folding | 在大小写不敏感工作区上，`status` / `merge` / `checkout` 必须显式报 `PathCaseConflict` |
| 非法字符 | 拒绝 NUL、ASCII 控制字符和 Windows 无法 materialize 的 `:\"*?<>|` | 避免对象能入库但无法在受支持平台落盘 |
| 保留名 | 拒绝 `.`、`..`、Windows device names（`CON`、`PRN`、`AUX`、`NUL`、`COM1`-`COM9`、`LPT1`-`LPT9`）以及尾随空格 / 点 | 保证仓库在 Windows / macOS / Linux 间可 roundtrip |

Manifest node：

```uya
export struct ManifestNodePayload {
    prefix: PathPrefix,
    level: u16,
    entry_count: u32,
    child_count: u32,
    entries: Vec<ManifestEntry>,
    children: Vec<ManifestChild>
}

export struct ManifestEntry {
    name: Vec<byte>,
    kind: EntryKind,
    mode: u32,
    object_id: ObjectId,
    logical_size: u64,
    content_type: ContentType,
    policy_id: PolicyId
}

export struct ManifestChild {
    min_name: Vec<byte>,
    max_name: Vec<byte>,
    child_id: ManifestId,
    child_hash: Hash32
}
```

Manifest 约束：

- entries 按 canonical path byte order 排序。
- 一个 node 的目标大小控制在 32KB 到 256KB，便于缓存和并行 diff。
- child range 不重叠，查询 pathspec 时可直接跳过无关分片。
- `ManifestId = hash("hypergit.manifest.v1" || canonical_manifest_payload)`，Merkle 身份由 payload 派生，而不是写回 payload。

### 8.2 Manifest shard split / merge 阈值

第一版先使用固定阈值，把“单 shard 可缓存、可顺序读、可并行 diff”优先级放在最前面：

| 指标 | soft target | hard split | merge underflow | merge upper bound |
| --- | --- | --- | --- | --- |
| encoded payload size | 128 KiB | `> 256 KiB` | `< 32 KiB` | sibling 合并后 `<= 192 KiB` |
| leaf `entry_count` | 1024 | `> 2048` | `< 128` | 合并后 `<= 1536` |
| internal `child_count` | 64 | `> 256` | `< 16` | 合并后 `<= 192` |

执行规则：

1. leaf 或 internal node 命中任一 `hard split` 条件后，就在当前 level 上按 canonical path byte order 选择最接近 `128 KiB` / `1024 entries` 的边界拆分。
2. split 后每个 sibling 的目标范围是 `64 KiB - 160 KiB`；若数据分布极端不均，允许留下一个较小尾 shard，但绝不允许另一个 sibling 超过 `256 KiB`。
3. 节点写回后若落入任一 `merge underflow` 条件，先尝试与左 sibling 合并，再尝试右 sibling；只有当合并结果不超过 `merge upper bound` 时才真正合并。
4. root node 允许暂时小于 underflow 阈值；当 root 只剩一个 child 且自身没有 direct entry 时，直接向下折叠一级，而不是保留空壳 root。
5. 读路径（query / diff / checkout planner）只消费现有 shard 结构；split / merge 只发生在写路径，避免查询期间偷偷改树。

路径查询复杂度应接近：

```text
O(log(shards) + matched_entries)
```

而不是：

```text
O(total_files)
```

## 9. Blob 与大文件模型

小文件使用普通 blob：

```uya
export struct SmallBlobPayload {
    logical_size: u64,
    content_hash: Hash32,
    payload: Vec<byte>
}
```

大文件是原生 chunked blob，不是外接 LFS pointer：

```uya
export struct ChunkedBlobPayload {
    logical_size: u64,
    file_type: FileType,
    chunking_strategy: ChunkingStrategy,
    chunk_count: u32,
    chunks: Vec<ChunkRef>,
    content_fingerprint: Hash32,
    encryption_profile: PolicyId,
    dedupe_scope: DedupeScope
}

export struct ChunkRef {
    logical_chunk_id: Hash32,
    storage_id: Hash32,
    offset: u64,
    logical_size: u32,
    stored_size: u32,
    checksum: Hash32,
    storage_tier: StorageTier
}
```

默认阈值建议：

| 文件大小 | 对象策略 | 默认工作区行为 |
| --- | --- | --- |
| `< 8MB` | small blob | 可直接 materialize |
| `8MB - 128MB` | chunked blob | 按 sparse profile hydrate |
| `> 128MB` | large chunked blob | 默认 virtual |
| `> 1GB` | large chunked blob | 需要显式 hydrate |

Chunk 策略：

- 默认 Content-Defined Chunking，平均 4MB，最小 512KB，最大 16MB。
- 高随机内容或已压缩文件可回退固定分块。
- 上传只传缺失 chunk。
- 下载支持 range read 和并行 hydrate。
- 二进制 merge 默认保守，不懂格式时不假装智能合并。

## 10. Canonical Codec

对象持久化使用项目自定义 canonical binary codec。第一版不要直接用 JSON/YAML 存权威对象；JSON 只用于 config、debug dump 和测试 golden 文件。

Codec 规则：

- 整数使用明确端序，推荐 little-endian。
- 变长列表使用 `varuint length + repeated item`。
- enum 使用固定宽度 `u16` 或 `u32`。
- 字符串和路径存 UTF-8 byte slice，不做平台本地编码。
- 所有 map 在编码前按 key 的 byte order 排序。
- 不把对象自己的 `ObjectId`、`ManifestId`、`PublishedViewId` 或其他自派生 hash 编进自己的 canonical payload。
- 不编码不确定字段，例如本地 mtime、指针地址、arena offset。
- payload hash 基于 canonical payload，而不是内存布局。

### 10.1 object codec v1 二进制字段编码表

v1 codec 一律按“字段顺序即字节顺序”序列化，不依赖 Uya struct 内存布局，也不写任何隐式 padding。

| 逻辑类型 / 字段 | 编码 | 字节布局 | Canonical 约束 |
| --- | --- | --- | --- |
| `u8` | fixed integer | 1 byte | 不允许额外填充 |
| `u16` | fixed integer | 2 bytes, little-endian | 仅按声明宽度编码 |
| `u32` | fixed integer | 4 bytes, little-endian | magic、flags、mode 等固定宽度字段使用 |
| `u64` | fixed integer | 8 bytes, little-endian | length、generation、logical size 使用 |
| `i64` | fixed integer | 8 bytes, little-endian two's complement | 时间戳和带符号偏移使用 |
| `bool` | fixed integer | 1 byte | 只允许 `0x00` / `0x01`；其他值视为 `CodecNonCanonical` |
| `varuint` | unsigned LEB128 | 1-10 bytes | 必须最短编码；`0` 只能编码成单字节 `0x00` |
| `Hash32` | raw bytes | 32 bytes | 不加长度前缀，不做额外包装 |
| `ObjectId` / `CommitId` / `ManifestId` / `BlobId` | raw wrapped hash | 32 bytes | 只编码内部 `Hash32` 字节，不编码 wrapper 名称 |
| `enum` | fixed integer | 默认 `u16`；超出 `65535` 成员时升级为 `u32` | 数值必须映射到已声明成员；未知值报 `CodecNonCanonical` |
| `byte slice` | `varuint len + raw bytes` | `len` 前缀后紧跟数据 | 不写 NUL terminator，不做隐式压缩 |
| `UTF-8 string` / path | `varuint len + raw bytes` | 与 `byte slice` 相同 | 对用户可见文本和路径要求有效 UTF-8 |
| `list<T>` | `varuint count + repeated item` | 逐项顺序编码 | item 顺序属于语义的一部分，编码前不得重排 |
| `map<K, V>` | `varuint count + repeated key/value` | 逐对顺序编码 | key 必须先按 key byte order 排序；重复 key 直接报错 |

`ObjectEnvelope` 的序列化顺序固定如下：

| 顺序 | 字段 | 编码 | 说明 |
| --- | --- | --- | --- |
| 1 | `magic` | `u32` little-endian | magic 常量值在 codec 实现冻结阶段统一确定 |
| 2 | `version` | `u16` little-endian | v1 固定写入 `1` |
| 3 | `kind` | `u16` enum | `ObjectKind` 的判别值空间预留给对象模型 |
| 4 | `flags` | `u16` little-endian | v1 未定义位必须写 `0` |
| 5 | `payload_len` | `u64` little-endian | 只统计 canonical payload 字节数，不包含 envelope |
| 6 | `payload_hash` | `Hash32` raw bytes | hash 输入只覆盖 canonical payload，不覆盖 envelope |

错误处理：

```uya
error CodecUnexpectedEof;
error CodecInvalidMagic;
error CodecUnsupportedVersion;
error CodecHashMismatch;
error CodecNonCanonical;
```

### 10.2 错误码命名规范

HyperGit 统一把“模块内 Uya 错误符号”和“对外稳定错误码”分成两层命名：

| 层级 | 格式 | 示例 | 用途 |
| --- | --- | --- | --- |
| Uya 错误符号 | `error <Domain><Reason>;` | `error CodecInvalidMagic;` | 模块内返回、测试断言、模式匹配 |
| 稳定错误码 | `HGX_<DOMAIN>_<REASON>` | `HGX_CODEC_INVALID_MAGIC` | CLI、JSON、protocol frame、日志聚合 |

命名规则：

1. `Domain` 必须来自稳定模块边界，例如 `Cli`、`Repo`、`Config`、`Codec`、`Object`、`Manifest`、`Store`、`Pack`、`Stage`、`Workspace`、`Remote`、`Merge`、`Policy`、`Http`。
2. `Reason` 使用稳定语义词，不把临时实现细节塞进错误名；优先复用 `NotFound`、`AlreadyExists`、`Invalid*`、`Unsupported*`、`HashMismatch`、`UnexpectedEof`、`PermissionDenied`、`CaseConflict`、`DirtyConflict`、`WouldOverwrite`、`Corrupt*` 等后缀。
3. 一个错误只表达一个可恢复判断点；避免 `And` / `Or` / `Misc` / `UnknownFailure` 这类模糊拼接名。
4. 若多个模块共享同一失败语义，Uya 名称仍保留模块前缀，但稳定错误码的 `REASON` 应尽量一致，例如 `CodecUnexpectedEof` -> `HGX_CODEC_UNEXPECTED_EOF`，`RemoteUnexpectedEof` -> `HGX_REMOTE_UNEXPECTED_EOF`。
5. 面向用户的命令输出可以附带解释文本，但机器可消费接口必须保留稳定错误码，不直接暴露本地化句子当“错误码”。

推荐示例：

| 场景 | Uya 错误符号 | 稳定错误码 |
| --- | --- | --- |
| 仓库不存在 | `error RepoNotFound;` | `HGX_REPO_NOT_FOUND` |
| codec magic 错误 | `error CodecInvalidMagic;` | `HGX_CODEC_INVALID_MAGIC` |
| manifest 中出现大小写冲突 | `error ManifestCaseConflict;` | `HGX_MANIFEST_CASE_CONFLICT` |
| checkout 会覆盖 dirty 文件 | `error WorkspaceWouldOverwriteDirty;` | `HGX_WORKSPACE_WOULD_OVERWRITE_DIRTY` |

Codec 的第一批测试必须覆盖：

- 同一对象重复编码字节完全一致。
- 字段顺序、map 顺序、路径排序稳定。
- 损坏 magic/version/hash 时返回明确错误。
- 随机截断 payload 不越界，不 panic，不读未初始化内存。

## 11. Object Store

对象存储接口：

```uya
export interface ObjectStore {
    fn has(self: &Self, id: ObjectId) !bool;
    fn get(self: &Self, id: ObjectId, arena: &Arena) !ObjectBytes;
    fn put(self: &Self, kind: ObjectKind, payload: &[const byte]) !ObjectId;
    fn open_reader(self: &Self, id: ObjectId) !ObjectReader;
}
```

第一版实现顺序：

1. `LooseObjectStore`：每个对象一个文件，便于调试。
2. `SegmentPackWriter`：append-only segment pack。
3. `SegmentPackIndex`：object id -> segment offset。
4. `CompositeObjectStore`：loose + pack + cache 组合读。

Segment pack 结构：

```text
.hgp
  PackHeader
  ObjectRecord...
  PackFooter

.hgi
  PackIndexHeader
  ObjectIndexEntry...
  PrefixBloomBlock (optional v1 placeholder)
  PackIndexFooter
```

### 11.1 `.hgp` pack header

`.hgp` 是 append-only data segment；实现只允许尾部追加，不允许原地改写 record。第一版 header 固定 64 bytes，全部 little-endian：

| 偏移 | 字段 | 类型 | 说明 |
| --- | --- | --- | --- |
| `0x00` | `magic` | `u32` | 固定为 `HGP1`，用于快速拒绝错误文件类型 |
| `0x04` | `version` | `u16` | v1 固定为 `1` |
| `0x06` | `header_bytes` | `u16` | v1 固定为 `64`，后续版本可扩展 header 但必须递增 |
| `0x08` | `segment_seq` | `u64` | 单仓库单调递增的 segment 序号，对应 `seg-000001.hgp` 命名 |
| `0x10` | `object_count` | `u64` | 当前 segment 内 record 数量 |
| `0x18` | `data_bytes` | `u64` | 所有 `ObjectRecord` payload 总字节数，不含 header/footer |
| `0x20` | `index_ref_offset` | `u64` | 指向 `.hgp` 内 footer 区，保存 sidecar `.hgi` 摘要和 build watermark |
| `0x28` | `created_at_ms` | `i64` | segment 首次发布时间 |
| `0x30` | `base_generation` | `u64` | compaction 来源代次；前台直写为 `0` |
| `0x38` | `flags` | `u32` | 预留位，v1 必须写 `0` |
| `0x3c` | `header_crc32` | `u32` | 仅覆盖前 60 bytes，用于快速发现 header 损坏 |

`ObjectRecord` 的第一版布局：

| 顺序 | 字段 | 类型 | 说明 |
| --- | --- | --- | --- |
| 1 | `record_bytes` | `u32` | 包括 record header + object bytes + trailer 的总长度 |
| 2 | `kind` | `u16` | `ObjectKind` |
| 3 | `flags` | `u16` | 压缩/外联/保留位；v1 先全部写 `0` |
| 4 | `object_id` | `Hash32` | 直接保存对象 ID，便于顺序扫描时校验 |
| 5 | `payload_crc32` | `u32` | 仅覆盖对象 bytes，不覆盖 record header |
| 6 | `object_bytes` | `byte slice` | 与 loose object 完全一致的权威字节 |
| 7 | `trailer_crc32` | `u32` | 覆盖整个 record，便于局部损坏定位 |

约束：

- record 必须按写入顺序 append，不做洞填充；删除只能通过 compaction 回收。
- `object_bytes` 的 canonical 内容必须与 loose store 完全一致，不能因 pack 引入重编码。
- footer 必须至少包含：`segment_seq`、对应 `.hgi` 文件的 `Hash32`、footer 自身 checksum。
- 校验顺序固定为：`magic/version` -> `header_crc32` -> `record trailer_crc32` -> `payload_crc32`。

### 11.2 `.hgi` pack index

`.hgi` 是 sidecar index，允许重建。v1 采用按 `object_id` 升序排列的定长主表，方便二分查找和后续 mmap。

`PackIndexHeader` 固定 48 bytes：

| 偏移 | 字段 | 类型 | 说明 |
| --- | --- | --- | --- |
| `0x00` | `magic` | `u32` | 固定为 `HGI1` |
| `0x04` | `version` | `u16` | v1 固定为 `1` |
| `0x06` | `header_bytes` | `u16` | v1 固定为 `48` |
| `0x08` | `segment_seq` | `u64` | 必须与配套 `.hgp` 一致 |
| `0x10` | `entry_count` | `u64` | 主表 entry 数量 |
| `0x18` | `entries_offset` | `u64` | 主表起始偏移，v1 固定为 `48` |
| `0x20` | `bloom_offset` | `u64` | prefix bloom block 起始偏移；v1 无 bloom 时等于 footer offset |
| `0x28` | `header_crc32` | `u32` | 覆盖前 40 bytes |
| `0x2c` | `reserved` | `u32` | v1 必须写 `0` |

`ObjectIndexEntry` 固定 64 bytes：

| 偏移 | 字段 | 类型 | 说明 |
| --- | --- | --- | --- |
| `0x00` | `object_id` | `Hash32` | 主键，整表按它严格升序 |
| `0x20` | `record_offset` | `u64` | 指向 `.hgp` 内对应 `ObjectRecord` 起始位置 |
| `0x28` | `record_bytes` | `u32` | record 总长度 |
| `0x2c` | `kind` | `u16` | `ObjectKind`，用于快速跳过非目标类型 |
| `0x2e` | `flags` | `u16` | 与 pack record flags 对齐 |
| `0x30` | `logical_size` | `u64` | 对 blob/chunk 可直接提供统计信息；commit/manifest 记编码字节数 |
| `0x38` | `prefix_hint` | `u32` | 预留给路径/模块 locality hint，v1 可写 `0` |
| `0x3c` | `entry_crc32` | `u32` | 覆盖前 60 bytes |

`PackIndexFooter` 至少包含：

- `pack_hash: Hash32`：对应 `.hgp` 全文件 hash。
- `entries_hash: Hash32`：主表 hash，用于重建后快速比对。
- `footer_crc32: u32`：覆盖整个 footer。

约束：

- `.hgi` 损坏只允许降级到慢路径，不得把对象内容读错。
- `record_offset + record_bytes` 必须落在 `.hgp` 数据区边界内；越界直接视为索引损坏。
- 同一 `object_id` 在一个 `.hgi` 中只能出现一次；compaction 去重由 writer 保证。
- v1 的 bloom block 可以为空，但 `bloom_offset` 仍需指向 footer，以便后续版本原地扩展。

分组维度：

- 对象类型：commit / manifest / blobmeta / chunk。
- locality：路径前缀、时间窗口、模块、热度。
- generation：recent、daily、weekly、cold。

GC / compaction 原则：

- 前台写 append-only。
- 后台 copy-forward 生成新 segment。
- 旧 segment 只有在 active lease watermark 之后才能删除。
- 索引损坏只影响性能；对象校验失败必须返回硬错误。

## 12. Index Layer

索引是性能路径，但不是事实来源。

Commit graph index：

```uya
export struct CommitGraphEntry {
    commit_id: CommitId,
    generation: u64,
    parents: Vec<CommitId>,
    timestamp_ms: i64,
    changed_path_bloom: BloomFilter,
    module_bitmap: ModuleBitmap
}
```

用途：

- `merge-base`
- `log -- path`
- `branch contains`
- `bisect`
- `affected tests`

Path history 分两层：

- L0 强一致索引：提交发布时同步写入 changed path、delete event、rename hint。
- L1 异步 lineage 索引：后台构建 content fingerprint、chunk-line map、深度 rename graph。

Manifest locator：

- `path prefix -> manifest shard id`
- `manifest id -> pack segment`
- `published_view_id -> root manifest + shard map snapshot`

Bloom filter：

- commit changed-path bloom。
- segment object bloom。
- manifest shard path bloom。

任意查询都必须能在索引缺失或落后时回退到权威对象路径，并在结果中暴露 watermark。

## 13. Workspace Engine

工作区不是完整目录树，而是一个有 sparse profile 的虚拟视图。

```uya
export struct WorkspaceState {
    repo_root: Vec<byte>,
    base_commit: CommitId,
    view_id: PublishedViewId,
    sparse_profile_id: Hash32,
    materialized_count: u64,
    dirty_count: u64,
    watcher_seq: u64
}
```

### 13.1 Stage / Index 模型

`hgx add` 和 `hgx commit` 不能直接建立在 `LocalChangeDB` 上。`LocalChangeDB` 只负责发现工作区变化；真正的提交输入必须是显式 stage snapshot。

第一版 stage 持久化文件：

```text
.hgit/workspace/stage.hgi
```

建议的数据模型：

```uya
export enum StageEntryKind {
    Add,
    Modify,
    Delete,
    ModeOnly
}

export struct StageEntry {
    path: Vec<byte>,
    kind: StageEntryKind,
    base_object: ObjectId,
    has_staged_object: bool,
    staged_object: ObjectId,
    file_mode: u32
}

export struct StageState {
    base_commit: CommitId,
    entry_count: u64,
    last_update_ms: i64
}
```

约束：

- `hgx add <pathspec>` 从 working tree 或 manifest snapshot 生成 `StageEntry`，写入 `stage.hgi`。
- `hgx commit` 只消费 stage snapshot，不重新全量扫描 working tree。
- `hgx status` 同时展示 base -> stage 的 staged 变化，以及 stage -> worktree 的 unstaged 变化。
- 删除、mode change、稀疏路径部分提交都通过 stage 表达，不能依赖“当前目录上恰好扫到了什么”。
- 对尚未 hydrate 的未修改文件，stage 可以直接复用 manifest 中已有 `ObjectId`，不需要强制 materialize。

当前落地状态：

- 当前实现里的 `hgx add` 仍是单进程串行路径：先扫描工作区，再按匹配路径顺序生成对象，最后合并写回 `stage.hgi`。
- loose object 和 chunk store 的对象发布已经按内容寻址去重，但 `stage.hgi` 还没有 repo-local lock、CAS 或版本校验语义。
- 在补上 stage 原子发布之前，同一仓库并发执行多个 `hgx add` 不是已定义安全语义；未来即使接入 parallel hash/chunk，最终 stage publish 仍应保持单 writer。

当前 `hgx add` 的主要耗时来源：

- 即使 pathspec 很小，当前实现仍先全仓库枚举，再在内存里按 pathspec 过滤。
- 对已记录到 `LocalChangeDB` 且 `(inode, mtime_ns, logical_size)` 未变化的路径，`hgx add` 现在会直接复用已有 working hash / object id，避免重复全量 hash；watcher journal 和更激进的并行对象计算仍待补完。
- large file add 仍按单线程顺序执行 chunk 切分、hash 和 chunk store publish。

`hgx add` 的优化顺序建议：

1. 先做 pathspec 定向扫描，让 `hgx add src/main.uya` 只触达目标文件或目标子树，而不是全仓库 walk。
2. 接入 metadata fast path：对于未变化的 materialized file，直接复用已有 working hash / object id，避免重复全量 hash。
3. 最后接入 parallel object compute：把多文件 hash、大文件 chunk/hash/store 并行化，但 stage publish 仍保持单 writer。

### 13.2 本地变更数据库

本地变更数据库：

```uya
export struct LocalChange {
    path: Vec<byte>,
    base_object: ObjectId,
    working_hash: Hash32,
    status: ChangeStatus,
    last_seen_inode: u64,
    last_seen_mtime_ns: i64,
    last_seen_logical_size: u64,
    watcher_seq: u64,
    reconcile_epoch: u64
}
```

状态来源优先级：

1. stage snapshot。
2. 显式记录的 local change。
3. 文件系统 watcher 事件。
4. 分片 reconcile 扫描。
5. manifest 权威视图。

命令语义：

- `hgx status` 不全仓库扫描，默认读 stage、local change db 和 watcher journal。
- `hgx add pathspec` 更新 stage，而不是直接写 commit 草稿。
- `hgx commit -m` 以 stage 为唯一提交输入；空 stage 时拒绝生成新 commit。
- `hgx hydrate pathspec` 下载并落盘内容。
- `hgx dehydrate pathspec` 删除本地内容但保留 manifest 元数据。
- `hgx sparse add/remove` 更新工作区可见/默认物化范围。

第一版可以先不实现内核级 VFS，采用“真实文件 + placeholder + manifest-aware command”的用户态模型；后续再扩展 FUSE/平台 VFS。

## 14. 并行执行模型

HyperGit 的重操作都通过 planner 生成任务图，再交给 worker pool 执行。

当前代码状态：

- `TaskKind`、任务队列、worker pool，以及用于并行任务编排的基础控制状态已经存在：包括 atomic progress 计数、任务错误聚合和 shutdown 请求信号。
- `manifest diff`、`checkout`、pack read、large file hash 以及 `hgx add` 的对象计算层还没有真正接入这套并行执行框架。
- 因此现在的 `hgx add`、`manifest diff`、`checkout` 等命令仍可以保持串行实现；这里描述的是目标执行模型，不表示这些路径都已经并行化。

```uya
export enum TaskKind {
    ReadObject,
    WriteObject,
    DiffShard,
    MaterializePath,
    FetchSegment,
    HashFileRange,
    MergeShard
}

export struct Task {
    id: u64,
    kind: TaskKind,
    priority: u16,
    input_offset: u64,
    input_len: u64
}
```

执行原则：

- 每个 worker 持有自己的 arena，减少跨线程分配。
- 共享统计使用 `atomic u64`。
- object cache 只存不可变对象。
- 任务结果通过 bounded queue 汇总。
- 失败任务携带明确错误；planner 决定是否重试、降级或整体失败。

需要并行化的路径：

- manifest diff：按 shard 并行。
- checkout/materialize：按路径和 pack locality 并行。
- fetch/push：按 segment 并行。
- 大文件 hash/chunk/upload：按 range 或 chunk 并行。
- merge：全局 namespace preflight 后按独立 shard 并行。

对于 `hgx add`，更合适的分层是：

- 对象计算层可以并行：大文件 chunk 切分、range hash、chunk store publish、工作区 hash 计算。
- stage 更新层保持串行：把并行任务产出的 `StageEntry` 聚合后，经过锁或 CAS 校验，再一次性发布新的 `stage.hgi`。

## 15. Diff 与 Merge

Manifest diff：

```text
if left_manifest_id == right_manifest_id:
    skip whole shard
else:
    align child ranges
    spawn diff task per changed range
```

文本 diff 第一版可以实现 Myers 或 patience diff 的简化版本，优先保证正确性和可测试性。大文件 diff 使用类型感知摘要：

- 大文本：chunk + line range diff。
- 二进制：chunk-level changed summary。
- 图片/视频/模型/数据集：先输出 metadata diff，后续插件化。

Merge 分三阶段：

1. 全局 preflight：rename graph、file/dir 冲突、大小写折叠冲突、symlink/submodule 边界。
2. shard 内并行三方合并。
3. 全局收敛：目录 rename、mode、平台约束、最终 manifest。

默认二进制 merge 规则：

```text
ours changed, theirs unchanged -> take ours
ours unchanged, theirs changed -> take theirs
both unchanged -> keep base
both changed to same blob -> ok
both changed to different blob -> conflict
```

## 16. 远端协议

协议目标不是“传所有可达对象”，而是“传这个工作视图需要的对象和索引增量”。

能力协商：

```text
partial_materialization
manifest_query
path_history_query
chunked_blob
parallel_pack_segments
server_side_diff
server_side_merge_base
prefetch_hints
```

核心请求：

```text
GetCommitGraph(frontier, want_refs)
GetManifest(published_view_id, pathspec)
GetBlobRange(published_view_id, blob_id, offset, length)
GetPackSegments(published_view_id, object_ids)
GetPathHistory(published_view_id, path, since)
FetchView(have_frontier, want_ref, sparse_profile, blob_filter)
PushObjects(objects, expected_ref, new_commit)
```

第一版传输建议：

- 本地测试先使用 file remote：`file:///path/to/repo`。
- 第二阶段使用 Uya `std.http` 实现 HTTP/1.1 服务端。
- payload 使用 canonical binary frame，debug 模式可导出 JSON。
- 每个 frame 包含 magic、version、request id、kind、payload length、checksum。

## 17. 安全、策略与权限

对象完整性：

- 所有对象读取后校验 hash。
- pack segment 有整体 checksum。
- chunk 同时有 logical chunk id 和 stored checksum。

去重边界：

```text
Repo scope   -> 默认，只在单仓库去重
Tenant scope -> 同租户授权去重
Org scope    -> 明确授权的组织级共享对象池
```

权限策略以 path policy 表达：

```text
/data/customer/**
    require role: data-team
    dedupe-scope: tenant:data-platform
    audit: enabled
    local-cache-ttl: 24h
```

本地安全：

- 不信任 `.hgit` 中可被手工篡改的索引。
- 读取 object 必须重新校验 hash。
- checkout 必须拒绝 path traversal、绝对路径、非法 symlink escape。
- Windows/macOS/Linux 的大小写、执行位、symlink 差异要在 manifest entry 中建模。

## 18. CLI 设计

第一版命令：

```bash
hgx init
hgx status
hgx add <pathspec>
hgx commit -m <message>
hgx log
hgx diff [pathspec]
hgx checkout <commit-or-ref>
hgx hydrate <pathspec>
hgx dehydrate <pathspec>
hgx sparse add <pathspec>
hgx sparse remove <pathspec>
hgx fetch <remote>
hgx push <remote> <ref>
hgx doctor
```

`v1.0.0` 支持面冻结：

- 进入 `v1.0.0`：`init`、`status`、`add`、`commit`、`log`、`diff`、`checkout`、`hydrate`、`dehydrate`、`sparse add/remove`、`doctor`、`fetch`、`push`。
- 远端主路径：只承诺 `file://` remote 的 `fetch` / `push`。
- 明确延后：`merge` CLI、`branch` CLI、`clone` CLI、HTTP remote 正式支持、Git 互操作正式兼容矩阵。
- 实验特性：`policy_id` / `dedupe_scope` / `audit event` 目前只保留占位元数据，不作为 `v1.0.0` 发布级能力承诺。

体验原则：

- 常用命令与 Git 心智接近。
- 输出明确区分 virtual、materialized、dirty、missing、conflict。
- 慢操作显示对象数、segment 数、下载字节、并行度。
- `doctor` 能检查对象损坏、索引落后、lease 泄漏、工作区状态不一致。

## 19. 测试与验证策略

测试分层：

- 单元测试：codec、hash、path normalize、manifest query、bloom filter。
- 存储测试：loose store、segment pack、pack index、corruption detection。
- 工作区测试：status、add、commit、hydrate/dehydrate、sparse profile。
- 算法测试：manifest diff、merge conflict、large file chunking。
- 协议测试：frame encode/decode、file remote fetch/push、HTTP remote smoke。
- 属性测试：随机 manifest roundtrip、随机对象 codec roundtrip、随机 pathspec query。
- 性能基准：百万路径 manifest query、segment lookup、parallel materialize、`hgx add` 单文件 pathspec 延迟、重复 add metadata fast path 命中率。

Uya 命令建议：

```bash
UYA_BIN="${UYA_BIN:-/home/winger/xyglasses/uya/bin/uya}"
"$UYA_BIN" check src/hgx/main.uya
"$UYA_BIN" test src/hypergit/test_object_codec.uya
"$UYA_BIN" build src/hgx/main.uya -o bin/hgx
"$UYA_BIN" build src/hgx/main.uya -o build/hgx.c --c99
```

CI 第一阶段至少跑：

- 所有核心 `src/hypergit/test_*.uya` / `src/hgx/test_*.uya`。
- 所有 CLI shell 测试 `tests/test_*.sh`。
- C99 生成 smoke。
- 空仓库到首个 commit 的端到端脚本。
- 损坏对象检测脚本。

## 20. 里程碑

已发布里程碑：

- `v0.1.0`（2026-05-31）：首个 native `hgx` MVP 发布，覆盖 M0-M9 设计目标，并完成 `docs/todo.md` 的 Release Readiness 检查项。

M0 文档和工程骨架：

- 明确纯 Uya 实现边界。
- 建立源码目录、测试目录、构建脚本。
- 完成 `hgx --help`。

M1 最小本地仓库：

- `hgx init`
- canonical codec
- object id / hash
- loose object store
- refs

M2 最小提交链：

- path normalize
- small blob
- manifest node
- commit object
- `hgx add/status/commit/log`

M3 查询和 diff：

- manifest query
- manifest diff
- commit graph index
- `hgx diff`

M4 工作区物化：

- sparse profile
- hydrate/dehydrate
- local change db
- checkout planner

M5 Segment pack：

- pack writer/reader
- pack index
- local compaction
- corruption tests

M6 大文件：

- chunker
- chunked blob meta
- range read
- large file diff summary

M7 远端：

- file remote
- fetch/push
- published view
- CAS refs

M8 并行化：

- worker pool
- parallel manifest diff
- parallel checkout
- parallel fetch

M9 Git 互操作：

- Git import/export proof of concept。
- Native object 和 Git object 的映射文档。

## 21. 关键风险

- Uya 标准库中某些 IO / async / thread 能力仍可能需要项目内补足；第一版应控制并发模型复杂度。
- canonical codec 一旦发布就影响对象 ID，需要早期冻结 v1 规则。
- manifest shard 大小和 path ordering 会影响所有查询性能，需要基准驱动调整。
- 工作区 watcher 不能作为唯一事实来源，必须设计 reconcile。
- 大文件 CDC 算法需要大量测试，避免边界错误导致去重率和性能双输。
- Git 兼容层容易吞掉资源，应先做 native MVP，再做兼容网关。

## 22. 最终设计原则

1. 权威对象不可变。
2. 可变引用必须 CAS。
3. 路径空间必须可索引、可分片。
4. 工作区默认按需物化。
5. 大文件是原生 chunked blob。
6. 索引可重建，不能改变事实。
7. 每个长操作绑定 `PublishedView`。
8. 每个后台任务有 lease 和 watermark。
9. 每个 IO 失败返回显式 Uya 错误。
10. 每个核心模块都必须能用纯 Uya 测试验证。
