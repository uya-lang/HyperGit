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
    printf '\x00\x01\x02' >data.bin
    "$TMP_DIR/hgx" add data.bin >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "base" >/dev/null 2>&1
    printf '\x00\x01\x03' >data.bin
)

stdout_file="$TMP_DIR/diff.stdout"
stderr_file="$TMP_DIR/diff.stderr"

set +e
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" diff
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for diff binary: got $status want 0" >&2
    cat "$stderr_file" >&2
    exit 1
fi

if [ -s "$stderr_file" ]; then
    echo "unexpected stderr for diff binary" >&2
    cat "$stderr_file" >&2
    exit 1
fi

grep -F "diff --hgx a/data.bin b/data.bin" "$stdout_file" >/dev/null
grep -F "Binary files differ" "$stdout_file" >/dev/null
grep -F "1 file changed, 0 insertion(+), 0 deletion(-)" "$stdout_file" >/dev/null
