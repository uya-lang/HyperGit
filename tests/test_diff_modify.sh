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
    printf 'alpha\nbeta\n' >file.txt
    "$TMP_DIR/hgx" add file.txt >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "first" >/dev/null 2>&1
)

FIRST_HEAD="$(tr -d '\n' <"$REPO_DIR/.hgit/refs/heads/main")"

(
    cd "$REPO_DIR"
    printf 'alpha\ngamma\n' >file.txt
    "$TMP_DIR/hgx" add file.txt >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "second" >/dev/null 2>&1
)

SECOND_HEAD="$(tr -d '\n' <"$REPO_DIR/.hgit/refs/heads/main")"

stdout_file="$TMP_DIR/diff.stdout"
stderr_file="$TMP_DIR/diff.stderr"

set +e
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" diff "$FIRST_HEAD" "$SECOND_HEAD"
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for diff modify: got $status want 0" >&2
    cat "$stderr_file" >&2
    exit 1
fi

if [ -s "$stderr_file" ]; then
    echo "unexpected stderr for diff modify" >&2
    cat "$stderr_file" >&2
    exit 1
fi

grep -F "diff --hgx a/file.txt b/file.txt" "$stdout_file" >/dev/null
grep -F "rename hint: none" "$stdout_file" >/dev/null
grep -F -- "-beta" "$stdout_file" >/dev/null
grep -F "+gamma" "$stdout_file" >/dev/null
grep -F "1 file changed, 1 insertion(+), 1 deletion(-)" "$stdout_file" >/dev/null
