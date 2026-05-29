#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

REPO_DIR="$TMP_DIR/repo"
mkdir -p "$REPO_DIR"

(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    mkdir -p include
    printf 'x' >'include/name.'
)

stdout_file="$TMP_DIR/add.stdout"
stderr_file="$TMP_DIR/add.stderr"

set +e
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" add .
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -eq 0 ]; then
    echo "add . should fail on Windows-incompatible manifest names" >&2
    exit 1
fi

if [ -s "$stdout_file" ]; then
    echo "unexpected stdout for Windows-incompatible add" >&2
    cat "$stdout_file" >&2
    exit 1
fi

cat >"$TMP_DIR/expected.stderr" <<'EOF'
error: path uses Windows-incompatible names and cannot be staged
EOF

diff -u "$TMP_DIR/expected.stderr" "$stderr_file"
