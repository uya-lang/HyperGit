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
    printf 'one\n' >main.txt
    "$TMP_DIR/hgx" add main.txt >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "first" >/dev/null 2>&1
)

FIRST_HEAD="$(tr -d '\n' <"$REPO_DIR/.hgit/refs/heads/main")"

(
    cd "$REPO_DIR"
    printf 'two\n' >main.txt
    "$TMP_DIR/hgx" add main.txt >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "second" >/dev/null 2>&1
    printf 'dirty\n' >main.txt
)

stdout_file="$TMP_DIR/checkout.stdout"
stderr_file="$TMP_DIR/checkout.stderr"

set +e
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" checkout "$FIRST_HEAD"
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -eq 0 ]; then
    echo "checkout should fail on dirty workspace" >&2
    exit 1
fi

grep -F "error: checkout blocked by dirty workspace" "$stderr_file" >/dev/null
if [ "$(cat "$REPO_DIR/main.txt")" != "dirty" ]; then
    echo "dirty file should not be overwritten" >&2
    exit 1
fi
