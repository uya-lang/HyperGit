# HyperGit Git 互操作补充设计

状态：实验性的支持子集
发布口径：不进入 `v1.0.0` 承诺矩阵
实现入口：`src/hypergit/git/interop.uya`

## 1. 定位

当前仓库里的 Git 互操作不再按 “prototype / proof of concept” 口径描述，而是收敛成一个明确、可测试、可拒绝越界输入的支持子集。

这个子集的目标是：

- 让小型 Git 仓库中的 loose `blob` / `tree` / `commit` 能稳定导入到 HyperGit。
- 让由 small blob 组成的小型 HyperGit manifest 能稳定导出为 Git tree。
- 对超出子集的输入给出显式失败，而不是模糊报错或静默降级。

这个子集刻意不追求：

- packed object / delta / tag / replace ref 的完整兼容。
- submodule 导入。
- chunked blob 到 Git 的自动内容重组导出。
- 与 Git 完全等价的对象 ID、性能或大仓库吞吐。

## 2. 支持矩阵

| 方向 | 输入 | 当前状态 | 限制条件 | 越界后的失败行为 |
| --- | --- | --- | --- | --- |
| Git -> HyperGit | loose blob OID | 支持 | 只接受 40 字节十六进制 OID；对象必须是 loose `blob` | packed-only 对象报 `GitInteropUnsupportedPackedObject`；非 `blob` 报 `GitInteropUnsupportedGitObject`；缺失对象报 `GitInteropLooseObjectMissing` |
| Git -> HyperGit | tree -> manifest | 支持 | 只接受展平后的 `blob` leaf；leaf mode 仅支持 `100644` / `100755` / `120000`；路径进入 `manifest_path_normalize` | submodule / 其他非 `blob` leaf / 非支持 mode 报 `GitInteropUnsupportedTreeEntry`；引用 packed-only blob 报 `GitInteropUnsupportedPackedObject` |
| Git -> HyperGit | commit -> commit | 支持 | commit 对象必须是 loose `commit`；保留 tree、parents、author、committer、message、author timestamp；额外 headers 忽略 | packed-only commit/tree/blob 报 `GitInteropUnsupportedPackedObject`；非 `commit` 报 `GitInteropUnsupportedGitObject`；结构异常报 `GitInteropTreeParseFailed` |
| HyperGit -> Git | manifest -> tree | 支持 | manifest entry kind 仅支持 `File` / `Executable` / `Symlink`；entry 对象必须是 `SmallBlobPayload` | `ChunkedBlobPayload` 或其他非 small blob 对象报 `GitInteropUnsupportedHyperObject` |

## 3. 对象映射

| 源对象 | 目标对象 | 当前映射 |
| --- | --- | --- |
| Git loose `blob` | `SmallBlobPayload` | 读取 payload 后重新做 HyperGit canonical codec + domain hash，生成新的 `ObjectId` |
| Git `tree` | `ManifestId` | 通过 `git ls-tree -rz -r` 展平 leaf，排序路径后构建 manifest root |
| Git `commit` | `CommitPayload` | 映射 `tree` / `parents` / `author` / `committer` / `message` / author timestamp |
| HyperGit manifest entry | Git tree leaf | `File -> 100644`，`Executable -> 100755`，`Symlink -> 120000` |

补充说明：

- HyperGit 不保留 Git SHA-1 作为权威对象 ID。
- Git commit 的未知 headers 目前不保留，也不重新导出。
- generation 由 HyperGit 侧按 parent generation 重新计算。

## 4. 当前限制

- 只支持 loose object。实现会先检查 `.git/objects/aa/bbbbb...`，不会自动回退到 pack。
- tree 导入只接受最终 leaf 为 `blob` 的路径；`160000` submodule、tag 指向、replace ref 都不在子集内。
- export 只支持 small blob。HyperGit 原生 `ChunkedBlobPayload` 还没有接入 chunk store 重组导出路径。
- 当前实现通过 `git cat-file`、`git ls-tree`、`git update-index`、`git write-tree` 驱动，不是面向超大仓库优化过的批量通路。
- 该模块仍是仓库内实验能力，不暴露为 `v1.0.0` CLI 对外承诺。

## 5. 失败行为

| 错误 | 触发条件 |
| --- | --- |
| `GitInteropInvalidOid` | 输入 OID 不是 40 字节十六进制 |
| `GitInteropLooseObjectMissing` | Git 仓库内不存在该对象 |
| `GitInteropUnsupportedPackedObject` | 对象存在，但只存在于 pack 中，不满足 loose-only 子集 |
| `GitInteropUnsupportedGitObject` | 当前操作拿到的 Git 对象类型不对，例如用 `blob` API 读取 `commit` / `tag` |
| `GitInteropUnsupportedTreeEntry` | tree 中出现 submodule、非 `blob` leaf 或非支持 mode |
| `GitInteropUnsupportedHyperObject` | export 命中 `ChunkedBlobPayload` 或其他非 small blob 对象 |
| `GitInteropTreeParseFailed` | commit / tree 元数据结构不符合当前解析假设 |
| `GitInteropGitCommandFailed` | 依赖的 `git` 子命令执行失败 |
| `GitInteropReadFailed` | 中间文件读写失败或对象 payload 无法完整读取 |

这些错误的要求是：

- 超出支持子集时优先返回显式 `GitInteropUnsupported*` 错误。
- 不把越界输入伪装成“空结果”或“尽量继续”。
- 不静默把 chunked blob 当成 small blob 导出。

## 6. 测试覆盖

当前支持子集由 `src/hypergit/test_git_interop.uya` 锁定，至少覆盖：

- loose blob 读取与导入。
- packed-only blob 显式拒绝。
- tree -> manifest 正常导入。
- submodule tree entry 显式拒绝。
- commit 历史导入。
- manifest -> Git tree 正常导出。
- chunked blob export 显式拒绝。
- 小仓库端到端 import。

后续如果要扩这个子集，应新增测试后再放宽矩阵，不能只改文档口径。
