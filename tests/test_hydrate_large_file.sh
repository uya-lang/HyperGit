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
with Path("big.bin").open("wb") as f:
    for i in range(10):
        f.write(bytes([65 + i]) * chunk_size)
PY
    cp big.bin "$TMP_DIR/original.bin"
    "$TMP_DIR/hgx" add big.bin >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "big" >/dev/null 2>&1
)

CHUNK_COUNT="$(find "$REPO_DIR/.hgit/cache/chunks" -type f | wc -l | tr -d ' ')"
if [ "$CHUNK_COUNT" -lt 1 ]; then
    echo "expected chunked blob storage for large hydrate test" >&2
    exit 1
fi

(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" dehydrate big.bin >/dev/null 2>&1
)

[ ! -e "$REPO_DIR/big.bin" ]

(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" hydrate big.bin >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"
)

grep -F "hydrate 1/1 big.bin" "$TMP_DIR/stdout" >/dev/null
[ -z "$(cat "$TMP_DIR/stderr")" ]
cmp -s "$TMP_DIR/original.bin" "$REPO_DIR/big.bin"
