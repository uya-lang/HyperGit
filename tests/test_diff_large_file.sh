#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

REPO_DIR="$TMP_DIR/repo"
mkdir -p "$REPO_DIR"

(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    python3 - <<'PY'
from pathlib import Path

chunk_size = 1024 * 1024
path = Path("big.bin")
with path.open("wb") as f:
    for i in range(10):
        f.write(bytes([65 + i]) * chunk_size)

with path.open("r+b") as f:
    f.seek(5 * chunk_size + 1234)
    f.write(b"ABC")
PY
    "$TMP_DIR/hgx" add big.bin >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "base" >/dev/null 2>&1
    python3 - <<'PY'
from pathlib import Path

chunk_size = 1024 * 1024
path = Path("big.bin")
with path.open("r+b") as f:
    f.seek(5 * chunk_size + 1234)
    f.write(b"XYZ")
PY
)

stdout_file="$TMP_DIR/diff.stdout"
stderr_file="$TMP_DIR/diff.stderr"

set +e
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" diff
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for diff large file: got $status want 0" >&2
    cat "$stderr_file" >&2
    exit 1
fi

if [ -s "$stderr_file" ]; then
    echo "unexpected stderr for diff large file" >&2
    cat "$stderr_file" >&2
    exit 1
fi

grep -F "diff --hgx a/big.bin b/big.bin" "$stdout_file" >/dev/null
grep -F "Chunk summary:" "$stdout_file" >/dev/null
grep -F "Chunk counts:" "$stdout_file" >/dev/null
grep -F "Logical size:" "$stdout_file" >/dev/null
grep -F "1 file changed, 0 insertion(+), 0 deletion(-)" "$stdout_file" >/dev/null

if grep -F "Binary files differ" "$stdout_file" >/dev/null; then
    echo "expected chunk summary instead of generic binary diff output" >&2
    cat "$stdout_file" >&2
    exit 1
fi
