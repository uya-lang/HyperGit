# HyperGit Git 互操作补充设计

状态：prototype 补充设计  
范围：`docs/todo.md` 第 21 阶段

## 1. 目标

本阶段只做 Git 互操作 proof of concept，不追求：

- 覆盖 packed object、delta、tag、submodule、replace ref。
- 保持与 Git 完全等价的性能。
- 处理超大仓库上的全量导入优化。

本阶段要验证三件事：

- HyperGit 能从一个小型 Git 仓库导入 blob/tree/commit。
- HyperGit 能把一个小型 manifest 导回 Git tree。
- native chunked blob 在导出到 Git 时有明确且稳定的降级规则。

## 2. 对象映射

| Git 对象 | HyperGit 原型 | 备注 |
| --- | --- | --- |
| loose blob | `SmallBlobPayload` | 原型阶段只支持可完整读入内存的 blob |
| tree | `ManifestLeafInputList` -> `ManifestId` | tree 递归展平为排序路径列表，再构建 manifest |
| commit | `CommitPayload` | 只映射第一个 tree、parents、author/committer、message、timestamp |

原型阶段不做：

- annotated tag 导入。
- Git mode `160000` submodule 导入。
- packed object 导入。

## 3. 导入原型

### 3.1 loose blob

输入：

- Git 仓库根目录。
- 40 字节十六进制 SHA-1。

原型读取路径：

- `.git/objects/aa/bbbbb...`

读取步骤：

1. 定位 loose object 文件。
2. 解压缩得到 `"<type> <size>\\0<payload>"`。
3. 要求 `type == "blob"`。
4. 取 payload，转成 HyperGit `SmallBlobPayload`。
5. 用 HyperGit 的 canonical codec + domain hash 重新计算 `ObjectId` 并写入 HyperGit store。

### 3.2 tree -> manifest

输入：

- Git tree OID。

原型行为：

1. 递归展开 tree。
2. 只接受 mode：
   - `100644`
   - `100755`
   - `120000`
   - `040000`
3. 对 blob entry：
   - 读取对应 Git blob。
   - 导入为 HyperGit small blob。
4. 对 tree entry：
   - 递归展开并拼接路径。
5. 所有路径进入 `manifest_path_normalize`。
6. `policy_id` 使用统一 placeholder。
7. 最终用 `manifest_root_build_and_store` 构建 `ManifestId`。

### 3.3 commit -> HyperGit commit

输入：

- Git commit OID。

原型映射：

- `tree` -> `manifest_root`
- `parent*` -> `parents`
- `author` -> `author`
- `committer` -> `committer`
- commit message -> `message`
- author timestamp seconds -> `timestamp_ms`

原型约束：

- 不保留 Git SHA-1 作为 HyperGit 权威 ID。
- Git commit 的额外 headers 先忽略。
- generation 按 parent generation 重新计算。

## 4. 导出原型

### 4.1 manifest -> Git tree

输入：

- HyperGit `ManifestId`

原型行为：

1. flatten manifest。
2. 对每个 entry 读取 HyperGit blob 内容。
3. 生成 Git blob。
4. 按路径递归重建 Git tree。
5. 输出 Git tree OID。

原型约束：

- `EntryKind.File` -> mode `100644`
- `EntryKind.Executable` -> mode `100755`
- `EntryKind.Symlink` -> mode `120000`

### 4.2 HyperGit commit -> Git commit

原型阶段只要求：

- tree 正确。
- parent 列表正确。
- author/committer/message 可读。

不要求：

- 和原 Git commit SHA-1 完全一致。
- 保留未知 headers。

## 5. chunked blob Git 降级策略

Git 原生没有 chunked blob 概念，原型阶段采用“内容优先”的降级规则：

1. `ChunkedBlobPayload` 导出到 Git 时，先按 chunk 顺序重建完整字节流。
2. Git 侧一律导出为普通 blob，不保留 chunk 边界。
3. HyperGit 专属元数据不写入 Git tree mode，也不写入 Git blob header。
4. 如需追踪降级来源，原型阶段只在补充文档中声明，不额外写 note/ref。

这样做的取舍：

- 优点：Git 仓库能直接读取，互操作最稳。
- 缺点：丢失 chunk 边界、去重范围、storage tier、encryption profile 等 HyperGit 原生语义。

后续增强方向：

- Git note 记录 HyperGit 源对象 ID。
- sidecar manifest 保存 chunk layout。
- 针对大对象导出 LFS-compatible gateway。

## 6. 测试策略

原型阶段最小测试矩阵：

- 小仓库 Git import：1 个 text blob、1 个 executable、1 层子目录、2 个 commit。
- 导出后 Git 能读取：`git ls-tree`、`git cat-file -p`、`git checkout`。
- chunked blob 降级：验证导出后 blob 内容与重组字节流一致。

## 7. 非目标提醒

如果后续发现实现依赖：

- packed object
- delta base 解析
- reflog
- note
- filter driver

应单独开新 TODO，不在本 prototype 阶段偷偷扩 scope。
