# HyperGit / 极仓 TODO

本文是 HyperGit 纯 Uya 实现路线图。所有核心代码默认使用 `~/uya/uya` 编译和测试；除系统 FFI、C99 后端和必要平台边界外，不引入非 Uya 核心实现。

## 0. 文档与约束

- [x] 确认项目名称为 `HyperGit / 极仓`。
- [x] 确认 CLI 名称为 `hgx`。
- [x] 确认核心实现语言为纯 Uya。
- [x] 编写系统设计文档：`docs/design.md`。
- [x] 编写分阶段 TODO 文档：`docs/todo.md`。
- [x] 更新项目入口文档：`readme.md`。
- [ ] 在 `docs/design.md` 冻结 object codec v1 前补充二进制字段编码表。
- [ ] 在 `docs/design.md` 补充 path normalization 跨平台规则表。
- [ ] 在 `docs/design.md` 补充 manifest shard split / merge 的精确阈值。
- [ ] 在 `docs/design.md` 补充错误码命名规范。
- [x] 在 `docs/design.md` 明确对象 `ObjectId` / `ManifestId` 不进入自身 canonical payload。
- [x] 在 `docs/design.md` 补充 staging/index 设计，明确 `commit` 只消费 stage snapshot。
- [x] 对齐 `bin/` 与 `build/` 产物目录约束。

## 1. 工程骨架

- [ ] 创建 `src/hgx/main.uya`。
- [ ] 创建 `src/hgx/commands/` 命令目录。
- [ ] 创建 `src/hypergit/core/` 核心类型目录。
- [ ] 创建 `src/hypergit/object/` 对象模型目录。
- [ ] 创建 `src/hypergit/store/` 存储目录。
- [ ] 创建 `src/hypergit/manifest/` manifest 目录。
- [ ] 创建 `src/hypergit/index/` 索引目录。
- [ ] 创建 `src/hypergit/workspace/` 工作区目录。
- [ ] 创建 `src/hypergit/exec/` 并行执行目录。
- [ ] 创建 `src/hypergit/protocol/` 协议目录。
- [ ] 创建 `src/hypergit/large/` 大文件目录。
- [ ] 创建 `src/hypergit/merge/` merge 目录。
- [ ] 创建 `tests/` Uya 测试目录。
- [ ] 创建 `bench/` 基准目录。
- [ ] 创建 `bin/` 和 `build/` 输出目录并加入忽略规则。
- [ ] 创建最小构建脚本或 Makefile。
- [ ] 确保 `~/uya/uya/bin/uya check src/hgx/main.uya` 可运行。
- [ ] 确保 `~/uya/uya/bin/uya build src/hgx/main.uya -o bin/hgx` 可运行。

## 2. CLI MVP

- [ ] 实现 `hgx --help`。
- [ ] 实现 `hgx --version`。
- [ ] 实现命令分派器。
- [ ] 实现未知命令错误。
- [ ] 实现统一退出码。
- [ ] 实现 `hgx doctor` 占位命令。
- [ ] 实现 `hgx init` 占位命令。
- [ ] 为 CLI 参数解析写单元测试。
- [ ] 为错误输出写 golden 测试。

## 3. Core Types

- [ ] 实现 `Hash32`。
- [ ] 实现 `ObjectId`。
- [ ] 实现 `CommitId`。
- [ ] 实现 `ManifestId`。
- [ ] 实现 `BlobId`。
- [ ] 实现 `PublishedViewId`。
- [ ] 实现 `PolicyId`。
- [ ] 实现 ID 字节比较。
- [ ] 实现 ID 十六进制编码。
- [ ] 实现 ID 十六进制解析。
- [ ] 实现 domain-separated hash helper。
- [ ] 接入 `std.crypto.blake3` 或 `std.crypto.sha256`。
- [ ] 为 ID roundtrip 写测试。
- [ ] 为 hash domain 隔离写测试。

## 4. Canonical Codec v1

- [ ] 定义 codec magic。
- [ ] 定义 object envelope。
- [ ] 实现 fixed integer encode/decode。
- [ ] 实现 varuint encode/decode。
- [ ] 实现 byte slice encode/decode。
- [ ] 实现 enum encode/decode。
- [ ] 实现 list encode/decode。
- [ ] 实现 canonical map ordering helper。
- [ ] 实现 payload hash 校验。
- [ ] 实现版本不兼容错误。
- [ ] 实现截断输入错误。
- [ ] 实现 non-canonical 输入错误。
- [ ] 为每个 primitive 写 roundtrip 测试。
- [ ] 为损坏 magic/version/hash 写错误测试。
- [ ] 为随机截断 payload 写健壮性测试。

## 5. Object Model

- [ ] 实现 `ObjectKind`。
- [ ] 实现 `StoredObject<T>` wrapper。
- [ ] 实现 `CommitPayload` 结构。
- [ ] 实现 `Identity` 结构。
- [ ] 实现 `ManifestNodePayload` 结构。
- [ ] 实现 `ManifestEntry` 结构。
- [ ] 实现 `ManifestChild` 结构。
- [ ] 实现 `SmallBlobPayload` 结构。
- [ ] 实现 `ChunkedBlobPayload` 结构。
- [ ] 实现 `ChunkRef` 结构。
- [ ] 实现 `PublishedView` 结构。
- [ ] 实现每类对象 codec。
- [ ] 实现每类对象 hash。
- [ ] 实现每类对象 validate。
- [ ] 测试 commit 编码稳定性。
- [ ] 测试 manifest entry 排序约束。
- [ ] 测试非法 object kind 被拒绝。

## 6. 本地仓库布局

- [ ] 定义 `.hgit/` 目录结构常量。
- [ ] 实现 repo root 探测。
- [ ] 实现 `.hgit/config.json` 读写。
- [ ] 实现 `refs/heads` 目录创建。
- [ ] 实现 `objects/loose` 目录创建。
- [ ] 实现 `objects/packs` 目录创建。
- [ ] 实现 `indexes` 目录创建。
- [ ] 实现 `workspace` 目录创建。
- [ ] 实现重复 `hgx init` 的幂等行为。
- [ ] 实现非空错误和权限错误处理。
- [ ] 测试空目录初始化。
- [ ] 测试嵌套目录 repo root 探测。

## 7. Loose Object Store

- [ ] 定义 `ObjectStore` interface。
- [ ] 实现 loose object path 映射。
- [ ] 实现对象临时文件写入。
- [ ] 实现原子 rename 发布。
- [ ] 实现 `has`。
- [ ] 实现 `get`。
- [ ] 实现 `put`。
- [ ] 实现读取时 hash 校验。
- [ ] 实现重复 put 去重。
- [ ] 实现损坏对象错误。
- [ ] 测试 put/get roundtrip。
- [ ] 测试并发重复 put。
- [ ] 测试对象文件被截断。

## 8. Manifest

- [ ] 实现 path normalization。
- [ ] 实现 path segment iterator。
- [ ] 实现 path byte order comparator。
- [ ] 实现 manifest leaf builder。
- [ ] 实现 manifest internal node builder。
- [ ] 实现 shard split。
- [ ] 实现 shard lookup by path。
- [ ] 实现 pathspec matcher。
- [ ] 实现 manifest range query。
- [ ] 实现 manifest hash skip。
- [ ] 实现 manifest diff。
- [ ] 测试百万路径 synthetic builder。
- [ ] 测试同 hash shard diff 跳过。
- [ ] 测试 pathspec 查询边界。
- [ ] 测试 file/dir 冲突检测。

## 9. Status / Add / Commit

- [ ] 实现 `hgx status` 空仓库输出。
- [ ] 实现 `StageState`。
- [ ] 实现 `StageEntry`。
- [ ] 实现 `workspace/stage.hgi`。
- [ ] 实现工作区文件枚举。
- [ ] 实现 small blob hash。
- [ ] 实现 `hgx add <pathspec>`。
- [ ] 实现 staging metadata。
- [ ] 实现 staged / unstaged 状态分离输出。
- [ ] 实现 manifest root 构建。
- [ ] 实现 commit object 构建。
- [ ] 实现 `refs/heads/main` 更新。
- [ ] 实现 `hgx commit -m`。
- [ ] 实现 `hgx log`。
- [ ] 测试首个 commit。
- [ ] 测试第二个 commit parent 正确。
- [ ] 测试 partial stage 只提交被 staged 的路径。
- [ ] 测试 add 删除文件。
- [ ] 测试 status 不误报未改文件。

## 10. Commit Graph Index

- [ ] 实现 commit graph entry。
- [ ] 实现 generation 计算。
- [ ] 实现 parent lookup。
- [ ] 实现 ref head frontier。
- [ ] 实现 changed path bloom 初版。
- [ ] 实现 commit graph 持久化。
- [ ] 实现 commit graph 增量加载。
- [ ] 实现 merge-base 查询。
- [ ] 测试线性历史。
- [ ] 测试分叉历史。
- [ ] 测试多 parent merge commit。

## 11. Diff

- [ ] 实现 `hgx diff` 基本命令。
- [ ] 实现 commit-to-commit manifest diff。
- [ ] 实现 workspace-to-commit diff。
- [ ] 实现 small text diff。
- [ ] 实现 binary changed summary。
- [ ] 实现 pathspec diff。
- [ ] 实现 rename hint 占位。
- [ ] 实现 diff 统计输出。
- [ ] 测试新增文件 diff。
- [ ] 测试删除文件 diff。
- [ ] 测试修改文件 diff。
- [ ] 测试目录 pathspec diff。

## 12. Workspace Engine

- [ ] 定义 `WorkspaceState`。
- [ ] 定义 `LocalChange`。
- [ ] 实现 `workspace/state.json`。
- [ ] 实现 `workspace/local-change.hgi` 初版。
- [ ] 实现 materialized path 记录。
- [ ] 实现 dirty path 记录。
- [ ] 实现 watcher journal 占位。
- [ ] 实现 reconcile 扫描。
- [ ] 实现 `hgx checkout <ref>`。
- [ ] 实现 checkout planner。
- [ ] 实现 atomic workspace state 更新。
- [ ] 测试 checkout 后文件内容正确。
- [ ] 测试 dirty 文件不被覆盖。
- [ ] 测试中断后 state 可恢复。

## 13. Sparse / Hydrate

- [ ] 定义 sparse profile 格式。
- [ ] 实现 `hgx sparse add`。
- [ ] 实现 `hgx sparse remove`。
- [ ] 实现 sparse profile 持久化。
- [ ] 实现 virtual path 状态。
- [ ] 实现 `hgx hydrate <pathspec>`。
- [ ] 实现 `hgx dehydrate <pathspec>`。
- [ ] 实现缺失对象错误提示。
- [ ] 实现 hydrate 进度输出。
- [ ] 测试 sparse add 后 checkout 范围变化。
- [ ] 测试 dehydrate 不删除 dirty file。
- [ ] 测试 hydrate 恢复文件内容。

## 14. Segment Pack

- [ ] 设计 `.hgp` pack header。
- [ ] 设计 `.hgi` pack index。
- [ ] 实现 segment writer。
- [ ] 实现 segment reader。
- [ ] 实现 object record checksum。
- [ ] 实现 footer checksum。
- [ ] 实现 object id -> offset 查询。
- [ ] 实现 pack bloom 占位。
- [ ] 实现 loose -> pack compaction。
- [ ] 实现 composite store 读路径。
- [ ] 测试 pack 写读 roundtrip。
- [ ] 测试 pack index 损坏。
- [ ] 测试 loose 和 pack 同时存在时优先级。

## 15. Large File

- [ ] 实现固定分块 chunker。
- [ ] 实现 CDC chunker 原型。
- [ ] 实现 chunk hash。
- [ ] 实现 chunk store。
- [ ] 实现 chunked blob meta。
- [ ] 实现 large file threshold 配置。
- [ ] 实现 large file add。
- [ ] 实现 range read。
- [ ] 实现 large file hydrate。
- [ ] 实现 large file diff summary。
- [ ] 测试 10MB 文件 chunk roundtrip。
- [ ] 测试小修改只新增少量 chunk。
- [ ] 测试 range read 跨 chunk 边界。

## 16. Merge

- [ ] 实现 merge planner 数据结构。
- [ ] 实现 base/ours/theirs manifest 对齐。
- [ ] 实现 namespace preflight。
- [ ] 实现 file/file text merge。
- [ ] 实现 delete/modify 冲突。
- [ ] 实现 file/dir 冲突。
- [ ] 实现 binary merge 保守策略。
- [ ] 实现 conflict marker 输出。
- [ ] 实现 merge result manifest。
- [ ] 测试无冲突合并。
- [ ] 测试同文件冲突。
- [ ] 测试目录 rename 冲突占位。

## 17. Parallel Execution

- [ ] 实现 `TaskKind`。
- [ ] 实现任务队列。
- [ ] 实现 worker pool。
- [ ] 实现 atomic 进度计数。
- [ ] 实现任务错误聚合。
- [ ] 实现 graceful shutdown。
- [ ] 接入 parallel manifest diff。
- [ ] 接入 parallel checkout。
- [ ] 接入 parallel pack read。
- [ ] 接入 parallel large file hash。
- [ ] 测试单 worker 和多 worker 结果一致。
- [ ] 测试任务失败能正确取消后续任务。

## 18. Remote / Protocol

- [ ] 定义 protocol frame header。
- [ ] 实现 frame encode/decode。
- [ ] 实现 request id。
- [ ] 实现 checksum。
- [ ] 实现 file remote。
- [ ] 实现 `FetchView`。
- [ ] 实现 `PushObjects`。
- [ ] 实现 remote ref CAS。
- [ ] 实现 published view。
- [ ] 实现 `hgx fetch`。
- [ ] 实现 `hgx push`。
- [ ] 测试 file remote clone。
- [ ] 测试 push CAS 失败。
- [ ] 测试 fetch sparse profile。

## 19. HTTP Remote

- [ ] 评估 Uya `std.http` 当前 API。
- [ ] 实现 HTTP route skeleton。
- [ ] 实现 capabilities endpoint。
- [ ] 实现 object batch endpoint。
- [ ] 实现 manifest query endpoint。
- [ ] 实现 fetch endpoint。
- [ ] 实现 push endpoint。
- [ ] 实现 request size limit。
- [ ] 实现基础鉴权 hook。
- [ ] 实现服务端 smoke test。

## 20. Security / Policy

- [ ] 实现 path traversal 防护。
- [ ] 实现绝对路径拒绝。
- [ ] 实现非法 symlink escape 检查。
- [ ] 实现 object hash 强校验。
- [ ] 实现 pack checksum 强校验。
- [ ] 实现 policy id 占位。
- [ ] 实现 dedupe scope 占位。
- [ ] 实现 audit event 占位。
- [ ] 测试恶意路径。
- [ ] 测试损坏对象无法 checkout。

## 21. Git 互操作

- [ ] 编写 Git import/export 设计补充文档。
- [ ] 实现读取 loose Git blob 原型。
- [ ] 实现 Git tree -> manifest 转换原型。
- [ ] 实现 Git commit -> HyperGit commit 映射原型。
- [ ] 实现 HyperGit manifest -> Git tree 导出原型。
- [ ] 明确 native chunked blob 的 Git 降级策略。
- [ ] 测试小仓库 Git import。
- [ ] 测试导出后 Git 能读取。

## 22. Benchmarks

- [ ] 生成 10 万路径 synthetic manifest。
- [ ] 生成 100 万路径 synthetic manifest。
- [ ] 基准 manifest lookup。
- [ ] 基准 manifest diff。
- [ ] 基准 loose object get。
- [ ] 基准 segment pack lookup。
- [ ] 基准 small file commit。
- [ ] 基准 large file chunk。
- [ ] 基准 hydrate。
- [ ] 记录每次基准命令和机器信息。

## 23. Release Readiness

- [ ] `hgx init/status/add/commit/log/diff` 可端到端运行。
- [ ] 所有 object codec 测试通过。
- [ ] 所有 store 测试通过。
- [ ] 所有 manifest 测试通过。
- [ ] 所有 workspace 测试通过。
- [ ] 损坏对象测试通过。
- [ ] C99 后端 build smoke 通过。
- [ ] README 能按步骤复现 MVP。
- [ ] `docs/design.md` 与实际模块命名一致。
- [ ] `docs/todo.md` 已更新真实完成状态。
