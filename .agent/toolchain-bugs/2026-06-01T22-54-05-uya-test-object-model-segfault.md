## Summary
`/home/winger/uya/uya/bin/uya test src/hypergit/test_object_model.uya` segfaults during code generation, which prevents `make test` from completing even after the Linux FUSE fix passes in isolation.

## Affected Tasks
- `实现 Linux FUSE adapter、mount 生命周期和错误恢复。`

## Toolchain Command
`/home/winger/uya/uya/bin/uya test src/hypergit/test_object_model.uya`

## Actual Error
The process exits with code 139 and the shell reports `Segmentation fault` after `=== 代码生成阶段 ===` for `src/hypergit/test_object_model.uya`.

## Expected Behavior
The test should compile and run successfully, or fail with a normal diagnostic instead of crashing the Uya toolchain.

## Repro File
`.agent/toolchain-bugs/repros/2026-06-01T22-54-05-uya-test-object-model-segfault.sh`

## Repro Code
```bash
#!/usr/bin/env bash
set -euo pipefail
cd /media/winger/_dde_home/winger/uya/HyperGit
/home/winger/uya/uya/bin/uya test src/hypergit/test_object_model.uya
```

## Notes
This repro is independent of the Linux FUSE bridge changes. The isolated Linux FUSE wrapper test passes under `unshare -Urnm`, but the broader `make test` gate is currently blocked by this separate Uya crash.
