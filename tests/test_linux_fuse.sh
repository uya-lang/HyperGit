#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UYA_BIN="${UYA:-${HOME}/uya/uya/bin/uya}"

if [ ! -x "$UYA_BIN" ] && [ -x "${HOME}/xyglasses/uya/bin/uya" ]; then
    UYA_BIN="${HOME}/xyglasses/uya/bin/uya"
fi

cd "$ROOT"

if command -v unshare >/dev/null 2>&1 && unshare -Urnm true >/dev/null 2>&1; then
    exec unshare -Urnm -- "$UYA_BIN" test src/hypergit/test_linux_fuse.uya
fi

exec "$UYA_BIN" test src/hypergit/test_linux_fuse.uya
