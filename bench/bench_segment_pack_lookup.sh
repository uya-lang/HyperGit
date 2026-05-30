#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OBJECT_COUNT="${1:-2000}"
LOOKUP_COUNT="${2:-2000}"
PAYLOAD_BYTES="${3:-128}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN="$TMP_DIR/bench_segment_pack_lookup"
OBJECTS_ROOT="$TMP_DIR/objects/loose"
PACK_DIR="$TMP_DIR/packs"
PACK_PATH="$PACK_DIR/seg-000001.hgp"
INDEX_PATH="$PACK_DIR/seg-000001.hgi"
mkdir -p "$OBJECTS_ROOT" "$PACK_DIR"

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hypergit/bench_segment_pack_lookup.uya" -o "$BIN" >/dev/null 2>&1

echo "timestamp=$(date -Iseconds)"
echo "command=bash bench/bench_segment_pack_lookup.sh $OBJECT_COUNT $LOOKUP_COUNT $PAYLOAD_BYTES"
echo "uname=$(uname -a)"
echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
echo "cores=$(nproc)"
"$BIN" "$OBJECT_COUNT" "$LOOKUP_COUNT" "$PAYLOAD_BYTES" "$OBJECTS_ROOT" "$PACK_PATH" "$INDEX_PATH"
