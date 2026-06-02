## Summary
`/home/winger/uya/uya/bin/uya test src/hypergit/test_object_model.uya` segfaults during code generation, which prevents `make test` from completing even after the Linux FUSE fix passes in isolation.

## Status
Not reproduced as of 2026-06-02 after rebuilding `/home/winger/uya/uya/bin/uya` from the current Uya toolchain. The repro command completed successfully: all 5 HyperGit object model tests passed with 25 assertions.

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
This repro was independent of the Linux FUSE bridge changes. It is no longer blocking the broader test gate in the current local toolchain.
