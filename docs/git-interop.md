# HyperGit Git 互操作补充设计

状态：实验性的完整互操作
发布口径：不进入 `v1.0.0` 承诺矩阵
实现入口：`src/hypergit/git/interop.uya`

## 1. 定位

当前仓库里的 Git 互操作不再按 “prototype / proof of concept” 口径描述，而是收敛成一个明确、可测试、可拒绝越界输入的支持子集。

当前互操作层的目标是：

- 让 Git `blob` / `tree` / `commit` 在 loose、packed、delta 压缩和 annotated tag 输入下都能稳定导入到 HyperGit。
- 让 replace ref 在 commit / tree / blob 读取路径上按 Git 语义生效，而不是回退到原对象。
- 让 `160000` submodule gitlink 能以可 roundtrip 的方式导入到 HyperGit manifest，再导出回 Git tree。
- 让由 small blob 与 submodule gitlink 组成的 HyperGit manifest 能稳定导出为 Git tree。
- 对仍然越界的输入给出显式失败，而不是模糊报错或静默降级。

当前实现仍然刻意不追求：

- Git tag object / ref 的持久化导出。当前 API 会接受 tag 作为输入对象选择器并自动 peel 到目标对象，但不会在 HyperGit 侧保留 tag metadata，也不会反向生成 Git tag object。
- chunked blob 到 Git 的自动内容重组导出。
- 与 Git 完全等价的对象 ID、性能或大仓库吞吐。

## 2. 支持矩阵

| 方向 | 输入 | 当前状态 | 限制条件 | 越界后的失败行为 |
| --- | --- | --- | --- | --- |
| Git -> HyperGit | blob OID / tag->blob | 支持 | 只接受 40 字节十六进制 OID；通过 `git rev-parse <oid>^{blob}` peel；对象可来自 loose、pack 或 delta | 非 `blob`/tag->blob 报 `GitInteropUnsupportedGitObject`；缺失对象报 `GitInteropObjectMissing` |
| Git -> HyperGit | tree-ish -> manifest | 支持 | 通过 `git rev-parse <oid>^{tree}` peel；leaf mode 支持 `100644` / `100755` / `120000` / `160000`；路径进入 `manifest_path_normalize` | 非支持 tree entry 报 `GitInteropUnsupportedTreeEntry`；越界对象类型报 `GitInteropUnsupportedGitObject` |
| Git -> HyperGit | commit OID / tag->commit | 支持 | 通过 `git rev-parse <oid>^{commit}` peel；保留 tree、parents、author、committer、message、author timestamp；replace ref 由 Git plumbing 生效 | 非 `commit`/tag->commit 报 `GitInteropUnsupportedGitObject`；缺失对象报 `GitInteropObjectMissing`；结构异常报 `GitInteropTreeParseFailed` |
| HyperGit -> Git | manifest -> tree | 支持 | regular/executable/symlink entry 仍要求 `SmallBlobPayload`；若 `mode == 160000`，则要求 small blob payload 恰好保存 40 字节 submodule commit hex | `ChunkedBlobPayload` 或其他非 small blob 对象报 `GitInteropUnsupportedHyperObject`；非法 submodule target 报 `GitInteropInvalidOid` |

## 3. 对象映射

| 源对象 | 目标对象 | 当前映射 |
| --- | --- | --- |
| Git `blob` | `SmallBlobPayload` | 读取 payload 后重新做 HyperGit canonical codec + domain hash，生成新的 `ObjectId` |
| Git `tree` | `ManifestId` | 通过 `git ls-tree -rz -r` 展平 leaf，排序路径后构建 manifest root |
| Git submodule gitlink | `ManifestEntry{ kind = File, mode = 160000 }` + `SmallBlobPayload` | manifest entry 的 object payload 保存 40 字节 Git commit hex，用于 roundtrip 回 Git tree |
| Git `commit` | `CommitPayload` | 映射 `tree` / `parents` / `author` / `committer` / `message` / author timestamp |
| HyperGit manifest entry | Git tree leaf | `File -> 100644`，`Executable -> 100755`，`Symlink -> 120000`，`mode == 160000 -> gitlink commit` |

补充说明：

- HyperGit 不保留 Git SHA-1 作为权威对象 ID。
- Git commit 的未知 headers 目前不保留，也不重新导出。
- annotated tag 目前只作为对象选择器被 peel 使用，不作为独立 HyperGit object 持久化。
- generation 由 HyperGit 侧按 parent generation 重新计算。

## 4. 当前限制

- tag 输入通过 peel 后消费目标对象；当前不会导出 Git tag object，也不会在 HyperGit 侧保留 tag metadata。
- submodule 只保留 gitlink commit hex，不会自动抓取或同步子模块仓库内容。
- export 只支持 small blob。HyperGit 原生 `ChunkedBlobPayload` 还没有接入 chunk store 重组导出路径。
- 当前实现通过 `git cat-file`、`git rev-parse`、`git ls-tree`、`git update-index`、`git write-tree` 驱动，不是面向超大仓库优化过的批量通路。
- 该模块仍是仓库内实验能力，不暴露为 `v1.0.0` CLI 对外承诺。

## 5. 失败行为

| 错误 | 触发条件 |
| --- | --- |
| `GitInteropInvalidOid` | 输入 OID 不是 40 字节十六进制 |
| `GitInteropObjectMissing` | Git 仓库内不存在该对象 |
| `GitInteropUnsupportedGitObject` | 当前操作拿到的 Git 对象类型不对，例如用 `blob` API 读取 `commit` / `tag` |
| `GitInteropUnsupportedTreeEntry` | tree 中出现非支持 entry，或 submodule gitlink 的 tree metadata 非法 |
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
- packed delta blob 读取与导入。
- annotated tag -> blob 导入。
- tree -> manifest 正常导入。
- submodule tree entry roundtrip。
- commit 历史导入。
- annotated tag -> commit 导入。
- replace ref 驱动的 commit 导入。
- manifest -> Git tree 正常导出。
- chunked blob export 显式拒绝。
- 小仓库端到端 import。

后续如果要扩这个子集，应新增测试后再放宽矩阵，不能只改文档口径。
