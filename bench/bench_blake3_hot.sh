#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMALL_ITERS="${1:-200000}"
LARGE_ITERS="${2:-128}"
PREPARE_ITERS="${3:-3}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN="$TMP_DIR/bench_blake3_hot"

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/bench_blake3_hot.uya" -o "$BIN" >/dev/null 2>&1

echo "timestamp=$(date -Iseconds)"
echo "command=bash bench/bench_blake3_hot.sh $SMALL_ITERS $LARGE_ITERS $PREPARE_ITERS"
echo "uname=$(uname -a)"
echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
echo "cores=$(nproc)"
"$BIN" "$SMALL_ITERS" "$LARGE_ITERS" "$PREPARE_ITERS"
