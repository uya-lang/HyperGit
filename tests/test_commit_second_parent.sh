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
    printf 'one' >src/main.uya
    "$TMP_DIR/hgx" add src >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "first" >/dev/null 2>&1
)

FIRST_HEAD="$(tr -d '\n' <"$REPO_DIR/.hgit/refs/heads/main")"

(
    cd "$REPO_DIR"
    printf 'two' >src/main.uya
    "$TMP_DIR/hgx" add src >/dev/null 2>&1
)

stdout_file="$TMP_DIR/second.stdout"
stderr_file="$TMP_DIR/second.stderr"

set +e
(
    cd "$REPO_DIR"
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "second"
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for second commit: got $status want 0" >&2
    cat "$stderr_file" >&2
    exit 1
fi

if [ -s "$stdout_file" ]; then
    echo "unexpected stdout for second commit" >&2
    cat "$stdout_file" >&2
    exit 1
fi

if [ -s "$stderr_file" ]; then
    echo "unexpected stderr for second commit" >&2
    cat "$stderr_file" >&2
    exit 1
fi

SECOND_HEAD="$(tr -d '\n' <"$REPO_DIR/.hgit/refs/heads/main")"
if [ "$SECOND_HEAD" = "$FIRST_HEAD" ]; then
    echo "second commit should update head" >&2
    exit 1
fi

log_stdout="$TMP_DIR/log.stdout"
log_stderr="$TMP_DIR/log.stderr"

set +e
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" log
) >"$log_stdout" 2>"$log_stderr"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for log after second commit: got $status want 0" >&2
    cat "$log_stderr" >&2
    exit 1
fi

if [ -s "$log_stderr" ]; then
    echo "unexpected stderr for log after second commit" >&2
    cat "$log_stderr" >&2
    exit 1
fi

grep -F "commit $SECOND_HEAD" "$log_stdout" >/dev/null
grep -F "commit $FIRST_HEAD" "$log_stdout" >/dev/null
