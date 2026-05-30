#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRY_COUNT="${1:-100000}"
LOOKUP_COUNT="${2:-2000}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN="$TMP_DIR/bench_manifest_lookup"
OBJECTS_ROOT="$TMP_DIR/objects/loose"
mkdir -p "$OBJECTS_ROOT"

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/bench_manifest_lookup.uya" -o "$BIN" >/dev/null 2>&1

echo "timestamp=$(date -Iseconds)"
echo "command=bash bench/bench_manifest_lookup.sh $ENTRY_COUNT $LOOKUP_COUNT"
echo "uname=$(uname -a)"
echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
echo "cores=$(nproc)"
"$BIN" "$ENTRY_COUNT" "$LOOKUP_COUNT" "$OBJECTS_ROOT"
