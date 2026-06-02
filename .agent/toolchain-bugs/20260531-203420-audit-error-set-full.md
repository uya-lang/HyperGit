## Summary
在当前 audit log 接线改动下，`uya build src/hgx/main.uya` 会在类型检查阶段稳定报 `错误集已满`，并连带把 `hydrate/status` 中的 `@error_id` 参数推断打坏，无法继续验证主程序构建。

## Status
Not reproduced as of 2026-06-02 after rebuilding `/home/winger/uya/uya/bin/uya` from the current Uya toolchain. The repro command completed type checking, code generation, split-C compilation, and linked `/tmp/hgx-audit-error-set-full` successfully.

## Affected Tasks
- 更复杂的 audit / policy / dedupe / storage tier 体系。
- 为 checkout / fetch / push / commit 生成可落盘 audit log，并补齐 doctor / CLI 可见性与回归测试。
- 将 audit log 接入 checkout / fetch / push / commit 成功路径，记录 policy_id / dedupe_scope / audit_enabled 等最终生效元数据。

## Toolchain Command
`$HOME/uya/uya/bin/uya build src/hgx/main.uya -o /tmp/hgx-audit-error-set-full`

## Actual Error
类型检查阶段输出多处 `错误集已满`，首批报错集中在：

- `src/hgx/commands/hydrate.uya:(165:28): 错误: 错误集已满`
- `src/hgx/commands/hydrate.uya:(373:40): 错误: @error_id 的参数必须是 error 类型`
- `src/hgx/commands/status.uya:(178:16): 错误: 错误集已满`

## Expected Behavior
主程序应完成类型检查，至少把真实的业务代码错误定位到新增的 audit 接线路径，而不是在无关命令上触发全局错误集溢出。

## Repro File
`.agent/toolchain-bugs/repros/20260531-203420-audit-error-set-full.sh`

## Repro Code
```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

"$HOME/uya/uya/bin/uya" build src/hgx/main.uya -o /tmp/hgx-audit-error-set-full
```

## Notes
- 该 repro 依赖当前工作区中的 audit log 接线改动。
- 当前本地工具链已不再触发 `错误集已满`；若后续再次出现，应重新确认是否由新的 audit/error-set 增量触发。
