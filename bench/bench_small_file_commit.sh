#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE_COUNT="${1:-1000}"
PAYLOAD_BYTES="${2:-32}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN="$TMP_DIR/hgx"
REPO="$TMP_DIR/repo"

now_ms() {
  date +%s%3N
}

elapsed_ms() {
  local start="$1"
  local finish="$2"
  printf '%s\n' "$((finish - start))"
}

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$BIN" >/dev/null 2>&1

mkdir -p "$REPO/files"

write_start="$(now_ms)"
python3 - "$REPO/files" "$FILE_COUNT" "$PAYLOAD_BYTES" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
count = int(sys.argv[2])
size = int(sys.argv[3])

for index in range(count):
    data = (f"{index:08d}:" + "x" * size)[:size]
    (root / f"file{index:06d}.txt").write_text(data)
PY
write_finish="$(now_ms)"

(
  cd "$REPO"
  "$BIN" init >"$TMP_DIR/init.log" 2>"$TMP_DIR/init.err"

  add_start="$(now_ms)"
  "$BIN" add files >"$TMP_DIR/add.log" 2>"$TMP_DIR/add.err"
  add_finish="$(now_ms)"

  commit_start="$(now_ms)"
  HGX_AUTHOR_NAME=bench HGX_AUTHOR_EMAIL=bench@example.test \
    "$BIN" commit -m "bench small files" >"$TMP_DIR/commit.log" 2>"$TMP_DIR/commit.err"
  commit_finish="$(now_ms)"

  echo "timestamp=$(date -Iseconds)"
  echo "command=bash bench/bench_small_file_commit.sh $FILE_COUNT $PAYLOAD_BYTES"
  echo "uname=$(uname -a)"
  echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
  echo "cores=$(nproc)"
  echo "files=$FILE_COUNT payload_bytes=$PAYLOAD_BYTES write_ms=$(elapsed_ms "$write_start" "$write_finish") add_ms=$(elapsed_ms "$add_start" "$add_finish") commit_ms=$(elapsed_ms "$commit_start" "$commit_finish")"
)
