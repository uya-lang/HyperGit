#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OBJECT_COUNT="${1:-5000}"
GET_COUNT="${2:-50000}"
PAYLOAD_BYTES="${3:-128}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN="$TMP_DIR/bench_loose_object_get"
OBJECTS_ROOT="$TMP_DIR/objects/loose"
mkdir -p "$OBJECTS_ROOT"

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/bench_loose_object_get.uya" -o "$BIN" >/dev/null 2>&1

echo "timestamp=$(date -Iseconds)"
echo "command=bash bench/bench_loose_object_get.sh $OBJECT_COUNT $GET_COUNT $PAYLOAD_BYTES"
echo "uname=$(uname -a)"
echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
echo "cores=$(nproc)"
"$BIN" "$OBJECT_COUNT" "$GET_COUNT" "$PAYLOAD_BYTES" "$OBJECTS_ROOT"
