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

项目目前处于架构设计和实现路线图阶段：

- [系统设计文档](docs/design.md)
- [详细 TODO 路线图](docs/todo.md)
- [命名说明](docs/naming.md)

## 实现约束

核心实现语言是 `~/uya/uya` 的 Uya：

```bash
~/uya/uya/bin/uya --help
```

设计约束：

- 核心对象库、索引、manifest、工作区、协议、diff、merge 使用纯 Uya 实现。
- C99 只作为 Uya 编译后端或平台边界，不作为业务实现语言。
- 第一版优先完成 native HyperGit MVP，再考虑 Git 兼容导入/导出。

## 计划中的 CLI

命令行工具名为 `hgx`：

```bash
hgx init
hgx status
hgx add <pathspec>
hgx commit -m "message"
hgx diff
hgx checkout main
hgx hydrate src/**
hgx sparse add src/payment
hgx fetch origin
hgx push origin main
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

## 下一步

按照 [docs/todo.md](docs/todo.md) 从工程骨架开始推进：先让 `hgx --help`、`hgx init`、object codec、loose object store、`stage.hgi` 和首个 commit 链路跑通。
