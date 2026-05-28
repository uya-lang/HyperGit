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
import random

rnd = random.Random(12345)
Path("big.bin").write_bytes(rnd.randbytes(10 * 1024 * 1024))
PY
    "$TMP_DIR/hgx" add big.bin >/dev/null 2>&1
)

INITIAL_CHUNKS="$(find "$REPO_DIR/.hgit/cache/chunks" -type f | wc -l | tr -d ' ')"
if [ "$INITIAL_CHUNKS" -lt 2 ]; then
    echo "expected initial large-file add to produce multiple chunks, got $INITIAL_CHUNKS" >&2
    exit 1
fi

(
    cd "$REPO_DIR"
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "base" >/dev/null 2>&1
    python3 - <<'PY'
from pathlib import Path

path = Path("big.bin")
with path.open("r+b") as f:
    f.seek(5 * 1024 * 1024 + 1234)
    f.write(b"XYZ")
PY
    "$TMP_DIR/hgx" add big.bin >/dev/null 2>&1
)

UPDATED_CHUNKS="$(find "$REPO_DIR/.hgit/cache/chunks" -type f | wc -l | tr -d ' ')"
ADDED_CHUNKS="$((UPDATED_CHUNKS - INITIAL_CHUNKS))"
if [ "$ADDED_CHUNKS" -ne 1 ]; then
    echo "expected a small large-file edit to add exactly 1 chunk, got $ADDED_CHUNKS" >&2
    exit 1
fi
