## Summary
`uya test src/hypergit/test_workspace_vfs.uya` 在类型检查和代码生成之后异常退出，返回码显示为 `-1`，没有继续到对象编译/链接或测试执行阶段，导致 FUSE/VFS 规划层的新单元测试无法作为完成证据。

## Status
Resolved as of 2026-06-02 by the Uya C99 async-frame descriptor emission fix. The repro command now compiles, links, and runs successfully: all 4 HyperGit Workspace VFS tests passed with 28 assertions.

## Affected Tasks
- FUSE / 平台 VFS / 内核级虚拟工作区。
- 定义 VFS provider / placeholder entry / materialization request 数据结构与规划器，并补齐单元测试。

## Toolchain Command
`bash .agent/toolchain-bugs/repros/20260531-224524-uya-test-workspace-vfs.sh`

## Actual Error
命令输出停在：

- `=== 代码生成阶段 ===`
- `模块名: src/hypergit/test_workspace_vfs.uya`

然后工具直接异常结束，调用方观测到退出码 `-1`，没有生成可执行测试结果。

## Expected Behavior
`uya test` 应继续完成对象编译、链接并执行测试，像现有 `src/hypergit/test_local_view.uya` 一样给出通过/失败结果。

## Repro File
`.agent/toolchain-bugs/repros/20260531-224524-uya-test-workspace-vfs.sh`

## Repro Code
```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

"$HOME/uya/uya/bin/uya" test src/hypergit/test_workspace_vfs.uya
```

## Notes
- 同一仓库里 `uya test src/hypergit/test_local_view.uya` 可以正常完成并运行测试。
- 根因对应 Uya C99 后端在无 async frame metadata 但运行时引用 descriptor 表时漏发 `_uya_async_frame_descriptors`。
