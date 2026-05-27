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
    mkdir -p src
    printf 'hello' >src/main.uya
    "$TMP_DIR/hgx" add src >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "initial" >/dev/null 2>&1
)

stdout_file="$TMP_DIR/log.stdout"
stderr_file="$TMP_DIR/log.stderr"

set +e
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" log
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for first log: got $status want 0" >&2
    cat "$stderr_file" >&2
    exit 1
fi

if [ -s "$stderr_file" ]; then
    echo "unexpected stderr for first log" >&2
    cat "$stderr_file" >&2
    exit 1
fi

HEAD_HEX="$(tr -d '\n' <"$REPO_DIR/.hgit/refs/heads/main")"
FIRST_LINE="$(sed -n '1p' "$stdout_file")"
if [ "$FIRST_LINE" != "commit $HEAD_HEX" ]; then
    echo "unexpected first log line: $FIRST_LINE" >&2
    exit 1
fi

grep -F "Author: Test User <test@example.com>" "$stdout_file" >/dev/null
grep -F "    initial" "$stdout_file" >/dev/null
