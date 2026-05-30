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

(
  cd "$REPO"
  "$BIN" init >"$TMP_DIR/init.log" 2>"$TMP_DIR/init.err"
  "$BIN" add files >"$TMP_DIR/add.log" 2>"$TMP_DIR/add.err"
  HGX_AUTHOR_NAME=bench HGX_AUTHOR_EMAIL=bench@example.test \
    "$BIN" commit -m "bench hydrate seed" >"$TMP_DIR/commit.log" 2>"$TMP_DIR/commit.err"

  dehydrate_start="$(now_ms)"
  "$BIN" dehydrate files >"$TMP_DIR/dehydrate.log" 2>"$TMP_DIR/dehydrate.err"
  dehydrate_finish="$(now_ms)"

  if [ -e "files/file000000.txt" ]; then
    echo "dehydrate_failed=file_still_materialized" >&2
    exit 1
  fi

  hydrate_start="$(now_ms)"
  "$BIN" hydrate files >"$TMP_DIR/hydrate.log" 2>"$TMP_DIR/hydrate.err"
  hydrate_finish="$(now_ms)"

  if [ ! -f "files/file000000.txt" ] || [ ! -f "$(printf 'files/file%06d.txt' "$((FILE_COUNT - 1))")" ]; then
    echo "hydrate_failed=file_missing" >&2
    exit 1
  fi

  echo "timestamp=$(date -Iseconds)"
  echo "command=bash bench/bench_hydrate.sh $FILE_COUNT $PAYLOAD_BYTES"
  echo "uname=$(uname -a)"
  echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
  echo "cores=$(nproc)"
  echo "files=$FILE_COUNT payload_bytes=$PAYLOAD_BYTES dehydrate_ms=$(elapsed_ms "$dehydrate_start" "$dehydrate_finish") hydrate_ms=$(elapsed_ms "$hydrate_start" "$hydrate_finish")"
)
