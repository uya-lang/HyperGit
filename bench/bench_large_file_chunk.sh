#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAYLOAD_BYTES="${1:-33554432}"
ITERATIONS="${2:-2}"
WORKERS="${3:-2}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN="$TMP_DIR/bench_large_file_chunk"

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/bench_large_file_chunk.uya" -o "$BIN" >/dev/null 2>&1

echo "timestamp=$(date -Iseconds)"
echo "command=bash bench/bench_large_file_chunk.sh $PAYLOAD_BYTES $ITERATIONS $WORKERS"
echo "uname=$(uname -a)"
echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
echo "cores=$(nproc)"
"$BIN" "$PAYLOAD_BYTES" "$ITERATIONS" "$WORKERS"
