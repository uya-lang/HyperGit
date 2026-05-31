# HyperGit / 极仓

HyperGit / 极仓是一个用纯 Uya 设计和实现的 Git-like 版本控制系统，目标是让超大规模仓库成为默认场景，而不是靠补丁式优化勉强支撑。

它面向：

- 亿级文件和超大 monorepo。
- TB/PB 级对象存储。
- 百万级提交历史。
- 并行 checkout / diff / merge / fetch。
- 云端索引与本地按需 materialize。
- 大文件、数据集、模型和设计资产的一等版本管理。

## 当前状态

项目目前有一个可运行的 native `hgx` MVP，已覆盖本地仓库初始化、工作区扫描、stage、commit、log、diff、checkout、hydrate/dehydrate、sparse profile，以及 file remote push/fetch 的主路径。

`v1.0.0` 范围冻结如下：

- 进入 `v1.0.0`：`init`、`status`、`add`、`commit`、`log`、`diff`、`checkout`、`hydrate`、`dehydrate`、`sparse`、`doctor`、`fetch`、`push`。
- `v1.0.0` 远端只承诺 `file://` remote；HTTP remote 仍是实验 / smoke 范围。
- 明确延后到 `v1.1+`：`merge` CLI、`branch` CLI、`clone` CLI、HTTP remote 完整协议、Git 互操作正式支持矩阵。
- `policy_id` / `dedupe_scope` / `audit event` 目前仍是实验性占位元数据，不属于 `v1.0.0` 的发布承诺。

当前发布版本：`v0.1.0`（2026-05-31），对应首个 native `hgx` MVP 里程碑。发布说明见 [v0.1.0 里程碑](docs/releases/v0.1.0.md)。

继续阅读：

- [系统设计文档](docs/design.md)
- [详细 TODO 路线图](docs/todo.md)
- [命名说明](docs/naming.md)
- [基准记录](docs/benchmarks.md)
- [v0.1.0 里程碑说明](docs/releases/v0.1.0.md)
- [`v1.0.0` 范围冻结](docs/releases/v1.0.0-scope.md)

## 构建

核心实现语言是 `~/uya/uya` 的 Uya：

```bash
UYA_BIN="${UYA_BIN:-/home/winger/xyglasses/uya/bin/uya}"
"$UYA_BIN" --version
"$UYA_BIN" build src/hgx/main.uya -o bin/hgx
bin/hgx help
```

设计约束：

- 核心对象库、索引、manifest、工作区、协议、diff、merge 使用纯 Uya 实现。
- C99 只作为 Uya 编译后端或平台边界，不作为业务实现语言。
- 第一版优先完成 native HyperGit MVP，再考虑 Git 兼容导入/导出。

## MVP 快速上手

下面的步骤会在 `build/readme-mvp/repo` 里创建一个临时仓库，不会改动项目源码：

```bash
rm -rf build/readme-mvp
mkdir -p build/readme-mvp/repo
cd build/readme-mvp/repo

../../../bin/hgx init
printf 'hello\n' > hello.txt
../../../bin/hgx status
../../../bin/hgx add hello.txt
HGX_AUTHOR_NAME='Demo User' HGX_AUTHOR_EMAIL='demo@example.com' ../../../bin/hgx commit -m "initial commit"
../../../bin/hgx log

printf 'hello again\n' > hello.txt
../../../bin/hgx diff
```

## 设计摘要

HyperGit 把仓库建模为可查询、可分片、可并行执行的版本化内容数据库：

- Commit 指向 manifest root，而不是递归 tree。
- Manifest 使用 Merkle Path Trie / B+Tree 风格分片。
- Blob 分为 small blob 和原生 chunked blob。
- 工作区默认 sparse + lazy materialization。
- 索引是一等公民，但必须可从权威对象重建。
- 远端协议传输视图和查询结果，而不是只传裸对象。
- 引用更新使用 CAS，并绑定 `PublishedView` 保证一致性。
