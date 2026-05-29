#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT/build/bench/manifests/$STAMP"
BIN="$ROOT/build/bench_manifest_synthetic"

mkdir -p "$OUT_DIR/100k" "$OUT_DIR/1m"

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/bench_manifest_synthetic.uya" -o "$BIN" >/dev/null 2>&1

"$BIN" 100000 >"$OUT_DIR/100k/stdout.txt" 2>"$OUT_DIR/100k/result.txt"
"$BIN" 1000000 >"$OUT_DIR/1m/stdout.txt" 2>"$OUT_DIR/1m/result.txt"

cat >"$OUT_DIR/commands.txt" <<EOF
$BIN 100000
$BIN 1000000
EOF

printf '%s\n' "$OUT_DIR"
