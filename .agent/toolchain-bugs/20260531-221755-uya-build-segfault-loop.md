## Summary
`uya build src/hgx/main.uya -o <tmp>/hgx >/dev/null 2>&1` 在 shell 回归里会偶发崩溃，表现为 `Segmentation fault`，导致 `tests/test_doctor_diagnostics.sh`、`tests/test_checkout_content.sh`、`tests/test_file_remote_fetch_push_happy_path.sh` 等命令级回归无法稳定执行。

## Affected Tasks
- 为 checkout / fetch / push / commit 生成可落盘 audit log，并补齐 doctor / CLI 可见性与回归测试。
- 扩展 `hgx doctor` 对 audit log 的可见性与诊断，并补齐命令级回归测试。

## Toolchain Command
`bash .agent/toolchain-bugs/repros/20260531-221755-uya-build-segfault-loop.sh`

## Actual Error
在循环执行 `uya build ... >/dev/null 2>&1` 时，某次迭代会以 `139` 退出，也就是 `Segmentation fault`。在 shell 测试里表现为例如：

- `tests/test_doctor_diagnostics.sh: line 8: ... Segmentation fault "$HOME/uya/uya/bin/uya" build ...`

## Expected Behavior
同一 build 命令应稳定成功或稳定返回可诊断的编译错误，而不是在无源码变动时随机崩溃。

## Repro File
`.agent/toolchain-bugs/repros/20260531-221755-uya-build-segfault-loop.sh`

## Repro Code
```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

for i in $(seq 1 20); do
    tmpdir="$(mktemp -d)"
    if ! "$HOME/uya/uya/bin/uya" build src/hgx/main.uya -o "$tmpdir/hgx" >/dev/null 2>&1; then
        status=$?
        echo "iteration=$i status=$status"
        rm -rf "$tmpdir"
        exit "$status"
    fi
    rm -rf "$tmpdir"
done

echo "no failure observed"
```

## Notes
- 这是间歇性崩溃，不是每次都能在第一次迭代触发。
- 当前 audit / doctor 子任务已经有业务层回归测试，但 shell 测试入口被这个编译器稳定性问题污染，无法作为可靠完成证据。
