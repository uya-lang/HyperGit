# HyperGit / 极仓 TODO

本文是 HyperGit 纯 Uya 实现路线图。所有核心代码默认使用 `~/uya/uya` 编译和测试；除系统 FFI、C99 后端和必要平台边界外，不引入非 Uya 核心实现。

## 0. 文档与约束

- [x] 确认项目名称为 `HyperGit / 极仓`。
- [x] 确认 CLI 名称为 `hgx`。
- [x] 确认核心实现语言为纯 Uya。
- [x] 编写系统设计文档：`docs/design.md`。
- [x] 编写分阶段 TODO 文档：`docs/todo.md`。
- [x] 更新项目入口文档：`readme.md`。
- [x] 在 `docs/design.md` 冻结 object codec v1 前补充二进制字段编码表。
- [x] 在 `docs/design.md` 补充 path normalization 跨平台规则表。
- [x] 在 `docs/design.md` 补充 manifest shard split / merge 的精确阈值。
- [x] 在 `docs/design.md` 补充错误码命名规范。
- [x] 在 `docs/design.md` 明确对象 `ObjectId` / `ManifestId` 不进入自身 canonical payload。
- [x] 在 `docs/design.md` 补充 staging/index 设计，明确 `commit` 只消费 stage snapshot。
- [x] 对齐 `bin/` 与 `build/` 产物目录约束。

## 1. 工程骨架

- [x] 创建 `src/hgx/main.uya`。
- [x] 创建 `src/hgx/commands/` 命令目录。
- [x] 创建 `src/hypergit/core/` 核心类型目录。
- [x] 创建 `src/hypergit/object/` 对象模型目录。
- [x] 创建 `src/hypergit/store/` 存储目录。
- [x] 创建 `src/hypergit/manifest/` manifest 目录。
- [x] 创建 `src/hypergit/index/` 索引目录。
- [x] 创建 `src/hypergit/workspace/` 工作区目录。
- [x] 创建 `src/hypergit/exec/` 并行执行目录。
- [x] 创建 `src/hypergit/protocol/` 协议目录。
- [x] 创建 `src/hypergit/large/` 大文件目录。
- [x] 创建 `src/hypergit/merge/` merge 目录。
- [x] 创建 `tests/` Uya 测试目录。
- [x] 创建 `bench/` 基准目录。
- [x] 创建 `bin/` 和 `build/` 输出目录并加入忽略规则。
- [x] 创建最小构建脚本或 Makefile。
- [x] 确保 `~/uya/uya/bin/uya check src/hgx/main.uya` 可运行。
- [x] 确保 `~/uya/uya/bin/uya build src/hgx/main.uya -o bin/hgx` 可运行。

## 2. CLI MVP

- [x] 实现 `hgx --help`。
- [x] 实现 `hgx --version`。
- [x] 实现命令分派器。
- [x] 实现未知命令错误。
- [x] 实现统一退出码。
- [x] 实现 `hgx doctor` 占位命令。
- [x] 实现 `hgx init` 占位命令。
- [x] 为 CLI 参数解析写单元测试。
- [x] 为错误输出写 golden 测试。

## 3. Core Types

- [x] 实现 `Hash32`。
- [x] 实现 `ObjectId`。
- [x] 实现 `CommitId`。
- [x] 实现 `ManifestId`。
- [x] 实现 `BlobId`。
- [x] 实现 `PublishedViewId`。
- [x] 实现 `PolicyId`。
- [x] 实现 ID 字节比较。
- [x] 实现 ID 十六进制编码。
- [x] 实现 ID 十六进制解析。
- [x] 实现 domain-separated hash helper。
- [x] 接入 `std.crypto.blake3` 或 `std.crypto.sha256`。
- [x] 为 ID roundtrip 写测试。
- [x] 为 hash domain 隔离写测试。

## 4. Canonical Codec v1

- [x] 定义 codec magic。
- [x] 定义 object envelope。
- [x] 实现 fixed integer encode/decode。
- [x] 实现 varuint encode/decode。
- [x] 实现 byte slice encode/decode。
- [x] 实现 enum encode/decode。
- [x] 实现 list encode/decode。
- [x] 实现 canonical map ordering helper。
- [x] 实现 payload hash 校验。
- [x] 实现版本不兼容错误。
- [x] 实现截断输入错误。
- [x] 实现 non-canonical 输入错误。
- [x] 为每个 primitive 写 roundtrip 测试。
- [x] 为损坏 magic/version/hash 写错误测试。
- [x] 为随机截断 payload 写健壮性测试。

## 5. Object Model

- [x] 实现 `ObjectKind`。
- [x] 实现 `StoredObject<T>` wrapper。
- [x] 实现 `CommitPayload` 结构。
- [x] 实现 `Identity` 结构。
- [x] 实现 `ManifestNodePayload` 结构。
- [x] 实现 `ManifestEntry` 结构。
- [x] 实现 `ManifestChild` 结构。
- [x] 实现 `SmallBlobPayload` 结构。
- [x] 实现 `ChunkedBlobPayload` 结构。
- [x] 实现 `ChunkRef` 结构。
- [x] 实现 `PublishedView` 结构。
- [x] 实现每类对象 codec。
- [x] 实现每类对象 hash。
- [x] 实现每类对象 validate。
- [x] 测试 commit 编码稳定性。
- [x] 测试 manifest entry 排序约束。
- [x] 测试非法 object kind 被拒绝。

## 6. 本地仓库布局

- [x] 定义 `.hgit/` 目录结构常量。
- [x] 实现 repo root 探测。
- [x] 实现 `.hgit/config.json` 读写。
- [x] 实现 `refs/heads` 目录创建。
- [x] 实现 `objects/loose` 目录创建。
- [x] 实现 `objects/packs` 目录创建。
- [x] 实现 `indexes` 目录创建。
- [x] 实现 `workspace` 目录创建。
- [x] 实现重复 `hgx init` 的幂等行为。
- [x] 实现非空目录初始化和权限错误处理。
- [x] 测试空目录初始化。
- [x] 测试嵌套目录 repo root 探测。

## 7. Loose Object Store

- [x] 定义 `ObjectStore` interface。
- [x] 实现 loose object path 映射。
- [x] 实现对象临时文件写入。
- [x] 实现原子 rename 发布。
- [x] 实现 `has`。
- [x] 实现 `get`。
- [x] 实现 `put`。
- [x] 实现读取时 hash 校验。
- [x] 实现重复 put 去重。
- [x] 实现损坏对象错误。
- [x] 测试 put/get roundtrip。
- [x] 测试并发重复 put。
- [x] 测试对象文件被截断。

## 8. Manifest

- [x] 实现 path normalization。
- [x] 实现 path segment iterator。
- [x] 实现 path byte order comparator。
- [x] 实现 manifest leaf builder。
- [x] 实现 manifest internal node builder。
- [x] 实现 shard split。
- [x] 实现 shard lookup by path。
- [x] 实现 pathspec matcher。
- [x] 实现 manifest range query。
- [x] 实现 manifest hash skip。
- [x] 实现 manifest diff。
- [x] 测试百万路径 synthetic builder。
- [x] 测试同 hash shard diff 跳过。
- [x] 测试 pathspec 查询边界。
- [x] 测试 file/dir 冲突检测。

## 9. Status / Add / Commit

- [x] 实现 `hgx status` 空仓库输出。
- [x] 实现 `StageState`。
- [x] 实现 `StageEntry`。
- [x] 实现 `workspace/stage.hgi`。
- [x] 实现工作区文件枚举。
- [x] 实现 small blob hash。
- [x] 实现 `hgx add <pathspec>`。
- [x] 实现 staging metadata。
- [x] `hgx add` 按 pathspec 定向扫描，避免单文件 add 触发全仓库枚举。
- [x] `hgx add` 复用 `LocalChangeDB` / `(inode, mtime_ns, logical_size)` 快速路径，未改文件不重复全量 hash。
- [x] 为 `workspace/stage.hgi` 增加原子发布语义（repo-local lock 或 CAS）。
- [x] 测试两个 `hgx add` 并发更新 stage 不丢 staging 结果。
- [x] 测试 `hgx add <pathspec>` 不遍历无关目录（包括无关大目录和无关权限受限目录）。
- [x] 实现 staged / unstaged 状态分离输出。
- [x] 实现 manifest root 构建。
- [x] 实现 commit object 构建。
- [x] 实现 `refs/heads/main` 更新。
- [x] 实现 `hgx commit -m`。
- [x] 实现 `hgx log`。
- [x] 测试首个 commit。
- [x] 测试第二个 commit parent 正确。
- [x] 测试 partial stage 只提交被 staged 的路径。
- [x] 测试 add 删除文件。
- [x] 测试 status 不误报未改文件。

## 10. Commit Graph Index

- [x] 实现 commit graph entry。
- [x] 实现 generation 计算。
- [x] 实现 parent lookup。
- [x] 实现 ref head frontier。
- [x] 实现 changed path bloom 初版。
- [x] 实现 commit graph 持久化。
- [x] 实现 commit graph 增量加载。
- [x] 实现 merge-base 查询。
- [x] 测试线性历史。
- [x] 测试分叉历史。
- [x] 测试多 parent merge commit。

## 11. Diff

- [x] 实现 `hgx diff` 基本命令。
- [x] 实现 commit-to-commit manifest diff。
- [x] 实现 workspace-to-commit diff。
- [x] 实现 small text diff。
- [x] 实现 binary changed summary。
- [x] 实现 pathspec diff。
- [x] 实现 rename hint 占位。
- [x] 实现 diff 统计输出。
- [x] 测试新增文件 diff。
- [x] 测试删除文件 diff。
- [x] 测试修改文件 diff。
- [x] 测试目录 pathspec diff。

## 12. Workspace Engine

- [x] 定义 `WorkspaceState`。
- [x] 定义 `LocalChange`。
- [x] 实现 `workspace/state.json`。
- [x] 实现 `workspace/local-change.hgi` 初版。
- [x] 实现 materialized path 记录。
- [x] 实现 dirty path 记录。
- [x] 实现 watcher journal 占位。
- [x] 实现 reconcile 扫描。
- [x] 实现 `hgx checkout <ref>`。
- [x] 实现 checkout planner。
- [x] 实现 atomic workspace state 更新。
- [x] 测试 checkout 后文件内容正确。
- [x] 测试 dirty 文件不被覆盖。
- [x] 测试中断后 state 可恢复。

## 13. Sparse / Hydrate

- [x] 定义 sparse profile 格式。
- [x] 实现 `hgx sparse add`。
- [x] 实现 `hgx sparse remove`。
- [x] 实现 sparse profile 持久化。
- [x] 实现 virtual path 状态。
- [x] 实现 `hgx hydrate <pathspec>`。
- [x] 实现 `hgx dehydrate <pathspec>`。
- [x] 实现缺失对象错误提示。
- [x] 实现 hydrate 进度输出。
- [x] 测试 sparse add 后 checkout 范围变化。
- [x] 测试 dehydrate 不删除 dirty file。
- [x] 测试 hydrate 恢复文件内容。

## 14. Segment Pack

- [x] 设计 `.hgp` pack header。
- [x] 设计 `.hgi` pack index。
- [x] 实现 segment writer。
- [x] 实现 segment reader。
- [x] 实现 object record checksum。
- [x] 实现 footer checksum。
- [x] 实现 object id -> offset 查询。
- [x] 实现 pack bloom 占位。
- [x] 实现 loose -> pack compaction。
- [x] 实现 composite store 读路径。
- [x] 测试 pack 写读 roundtrip。
- [x] 测试 pack index 损坏。
- [x] 测试 loose 和 pack 同时存在时优先级。

## 15. Large File

- [x] 实现固定分块 chunker。
- [x] 实现 CDC chunker 原型。
- [x] 实现 chunk hash。
- [x] 实现 chunk store。
- [x] 实现 chunked blob meta。
- [x] 实现 large file threshold 配置。
- [x] 实现 large file add。
- [x] 实现 range read。
- [x] 实现 large file hydrate。
- [x] 实现 large file diff summary。
- [x] 测试 10MB 文件 chunk roundtrip。
- [x] 测试小修改只新增少量 chunk。
- [x] 测试 range read 跨 chunk 边界。

## 16. Merge

- [x] 实现 merge planner 数据结构。
- [x] 实现 base/ours/theirs manifest 对齐。
- [x] 实现 namespace preflight。
- [x] 实现 file/file text merge。
- [x] 实现 delete/modify 冲突。
- [x] 实现 file/dir 冲突。
- [x] 实现 binary merge 保守策略。
- [x] 实现 conflict marker 输出。
- [x] 实现 merge result manifest。
- [x] 测试无冲突合并。
- [x] 测试同文件冲突。
- [x] 测试目录 rename 冲突占位。

## 17. Parallel Execution

- [x] 实现 `TaskKind`。
- [x] 实现任务队列。
- [x] 实现 worker pool。
- [x] 实现 atomic 进度计数。
- [x] 实现任务错误聚合。
- [x] 实现 graceful shutdown。
- [x] 接入 parallel manifest diff。
- [x] 接入 parallel checkout。
- [x] 接入 parallel pack read。
- [x] 接入 parallel large file hash（覆盖 `hgx add` / worktree hash 路径）。
- [x] 约束 parallel `hgx add` 只并行对象计算，最终 stage publish 保持单 writer。
- [x] 测试单 worker 和多 worker 结果一致。
- [x] 测试任务失败能正确取消后续任务。

## 18. Remote / Protocol

- [x] 定义 protocol frame header。
- [x] 实现 frame encode/decode。
- [x] 实现 request id。
- [x] 实现 checksum。
- [x] 实现 file remote。
- [x] 实现 `FetchView`。
- [x] 实现 `PushObjects`。
- [x] 实现 remote ref CAS。
- [x] 实现 published view。
- [x] 实现 `hgx fetch`。
- [x] 实现 `hgx push`。
- [x] 测试 file remote clone。
- [x] 测试 push CAS 失败。
- [x] 测试 fetch sparse profile。

## 19. HTTP Remote

- [x] 评估 Uya `std.http` 当前 API。
- [x] 实现 HTTP route skeleton。
- [x] 实现 capabilities endpoint。
- [x] 实现 object batch endpoint。
- [x] 实现 manifest query endpoint。
- [x] 实现 fetch endpoint。
- [x] 实现 push endpoint。
- [x] 实现 request size limit。
- [x] 实现基础鉴权 hook。
- [x] 实现服务端 smoke test。

## 20. Security / Policy

- [x] 实现 path traversal 防护。
- [x] 实现绝对路径拒绝。
- [x] 实现非法 symlink escape 检查。
- [x] 实现 object hash 强校验。
- [x] 实现 pack checksum 强校验。
- [x] 实现 policy id 占位。
- [x] 实现 dedupe scope 占位。
- [x] 实现 audit event 占位。
- [x] 测试恶意路径。
- [x] 测试损坏对象无法 checkout。

## 21. Git 互操作

- [x] 编写 Git import/export 设计补充文档。
- [x] 实现读取 loose Git blob 原型。
- [x] 实现 Git tree -> manifest 转换原型。
- [x] 实现 Git commit -> HyperGit commit 映射原型。
- [x] 实现 HyperGit manifest -> Git tree 导出原型。
- [x] 明确 native chunked blob 的 Git 降级策略。
- [x] 测试小仓库 Git import。
- [x] 测试导出后 Git 能读取。

## 22. Benchmarks

- [x] 生成 10 万路径 synthetic manifest。
- [x] 生成 100 万路径 synthetic manifest。
- [x] 基准 manifest lookup。
- [x] 基准 manifest diff。
- [x] 基准 loose object get。
- [x] 基准 segment pack lookup。
- [x] 基准 small file commit。
- [x] 基准单文件 `hgx add <pathspec>`（大 worktree，小 pathspec）。
- [x] 基准目录 `hgx add <pathspec>`（大 worktree，小目录）。
- [x] 基准重复 `hgx add` 命中 metadata fast path。
- [x] 基准 large file chunk。
- [x] 基准 hydrate。
- [x] 记录每次基准命令和机器信息。

## 23. Release Readiness

- [x] `hgx init/status/add/commit/log/diff` 可端到端运行。
- [x] 所有 object codec 测试通过。
- [x] 所有 store 测试通过。
- [x] 所有 manifest 测试通过。
- [x] 所有 workspace 测试通过。
- [x] 损坏对象测试通过。
- [x] C99 后端 build smoke 通过。
- [x] README 能按步骤复现 MVP。
- [x] `docs/design.md` 与实际模块命名一致。
- [x] `docs/todo.md` 已更新真实完成状态。
- [x] 发布首个里程碑版本 `v0.1.0` 并记录 release notes。

## 24. `v1.0.0` 发布清单

以下清单用于把 `v0.1.0` 的“可运行 MVP”推进到“可对外承诺的 `v1.0.0`”。
要求：不再用 prototype / placeholder / smoke test 作为 1.0 主路径完成标准。

### P0 / `v1.0.0` 发布阻塞项

- [x] 补齐 `hgx commit` 对 staged deletion 的完整提交路径，移除 `commit with staged deletions or unsupported entries is not implemented yet` 分支。
- [x] 补齐 `stage base commit != HEAD` 时的安全提交流程，移除 `commit from an existing history is not implemented yet` 分支。
- [x] 将 `hgx doctor` 从占位命令提升为真实诊断命令，至少覆盖对象损坏、索引落后、workspace state 不一致、stale lock。
- [x] 冻结 `v1.0.0` CLI 支持面，明确 `merge` / `branch` / `clone` / HTTP remote / Git 互操作哪些进入 1.0，哪些明确延后。
- [x] 为 1.0 选定至少一条发布级远端主路径：要么把 HTTP remote 补到 CLI 端到端可用，要么明确 1.0 只支持 file remote 并完成文档、帮助和测试收口。
- [x] 为删除提交、diverged stage、fetch/push happy path、远端冲突、损坏恢复补齐端到端测试。
- [x] 建立自动化 CI，默认执行 `make test`、native build、C99 smoke，并固定失败门槛。
- [x] 更新 `readme.md`、`docs/design.md`、release notes 和命令帮助，使 1.0 承诺范围与真实实现一致。

### P1 / 强烈建议在 `v1.0.0` 前完成

- [x] 如果 `merge` 进入 1.0 范围，补齐用户可见命令、冲突处理流程和 shell 测试，而不只停留在底层模块。
- [x] 如果 `branch` / `clone` 进入 1.0 范围，补齐 CLI、仓库引用操作、远端初始化流程和文档。
- [x] 将 policy / dedupe scope / audit event 从占位实现升级为最小可用实现，或明确标记为实验特性并从 1.0 承诺中移出。
- [x] 将 HTTP remote 从当前 smoke 级验证提升为更完整的协议验证，覆盖鉴权失败、对象批量传输、fetch、push、尺寸限制和服务端错误路径。
- [x] 将 Git 互操作从 prototype 收敛为“支持子集”并写清兼容矩阵、限制条件和失败行为。
- [x] 基于 `docs/benchmarks.md` 当前结果继续优化明显热点，至少解释并处理“parallel diff 慢于 serial”和“segment pack lookup 偏慢”的现状。

### 可明确延后到 `v1.1+`

- [x] Git packed object / delta / tag / submodule / replace ref 完整互操作。
- [x] 更复杂的 audit / policy / dedupe / storage tier 体系。
- [x] 定义可持久化的 path policy / dedupe scope / audit / cache TTL 配置格式，并实现 repo-local 读写与 matcher。
- [x] 将 policy / dedupe / audit 规则接入 add / commit / manifest / chunked blob 构建路径，替换当前 experimental default 常量直写。
- [x] 为 chunk / object 存储实现 tier-aware 放置与查询策略，并补齐 `StorageTier` 的真实选择、回退和测试。
- [x] 为 checkout / fetch / push / commit 生成可落盘 audit log，并补齐 doctor / CLI 可见性与回归测试。
- [x] 定义 repo-local audit log 文件格式、轮转边界和事件字段，并实现原子追加写入。
- [x] 将 audit log 接入 checkout / fetch / push / commit 成功路径，记录 policy_id / dedupe_scope / audit_enabled 等最终生效元数据。
- [x] 扩展 `hgx doctor` 对 audit log 的可见性与诊断，并补齐命令级回归测试。
- [x] FUSE / 平台 VFS / 内核级虚拟工作区。
- [x] 定义 VFS provider / placeholder entry / materialization request 数据结构与规划器，并补齐单元测试。
- [x] 将 sparse / hydrate / dehydrate / workspace local view 接入 VFS 规划层，并补齐回归测试。
- [x] 实现 Linux FUSE adapter、mount 生命周期和错误恢复。
- [x] 为 macOS / Windows 平台抽象 VFS 边界与降级策略。
- [x] 更激进的服务端索引、云端查询和分布式执行能力。

## 25. 大仓库命令性能（2x git 目标）

目标：在 `bench/bench_million_files_repo.sh`（百万文件）下，核心命令对齐或超过 `git` 的 2 倍速度。

- [x] 建立百万文件端到端基准脚本，覆盖 init/status/add/commit/log/diff，记录每步 hgx/git 耗时与加速比。
- [x] 修复 `hgx add` 在大量小文件首次 add 时的并行回归：定位为 Uya 分配器多线程争用（20 worker 比串行慢约 9x），将存储受限的小 blob 批量默认转为串行（`ADD_PARALLEL_TINY_SMALL_BLOB_AVG_BYTES` 64→65536），add_initial 从 0.095x 提升到约 1.4–1.5x。
- [ ] **（另立项）`hgx add` 首次大批量达到 2x git**：当前受限于 Uya 分配器无法多线程扩展。需二选一：(a) 无 malloc 的并行 prepare —— worker 用栈缓冲读+编码，写入预分配批缓冲的各自槽位，再串行写盘；或 (b) add 直接顺序写 pack 而非百万 loose 对象。
- [ ] status / diff 工作区扫描超过 git 2x：当前受 lstat 逐文件成本限制与 git 持平，需引入 watcher / stat-cache 增量层。
