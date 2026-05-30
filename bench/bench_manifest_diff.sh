#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRY_COUNT="${1:-100000}"
CHANGE_STRIDE="${2:-100}"
WORKERS="${3:-4}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN="$TMP_DIR/bench_manifest_diff"

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/bench_manifest_diff.uya" -o "$BIN" >/dev/null 2>&1

echo "timestamp=$(date -Iseconds)"
echo "command=bash bench/bench_manifest_diff.sh $ENTRY_COUNT $CHANGE_STRIDE $WORKERS"
echo "uname=$(uname -a)"
echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
echo "cores=$(nproc)"
"$BIN" "$ENTRY_COUNT" "$CHANGE_STRIDE" "$WORKERS"
