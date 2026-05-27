#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hypergit/loose_put_once.uya" -o "$TMP_DIR/loose_put_once" >/dev/null 2>&1

STORE_DIR="$TMP_DIR/objects/loose"
mkdir -p "$STORE_DIR"

"$TMP_DIR/loose_put_once" "$STORE_DIR" &
PID1=$!
"$TMP_DIR/loose_put_once" "$STORE_DIR" &
PID2=$!

wait "$PID1"
wait "$PID2"

FILE_COUNT="$(find "$STORE_DIR" -type f | wc -l | tr -d ' ')"
if [ "$FILE_COUNT" -ne 1 ]; then
    echo "expected exactly one loose object file, got $FILE_COUNT" >&2
    find "$STORE_DIR" -maxdepth 3 -print >&2
    exit 1
fi
