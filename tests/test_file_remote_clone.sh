#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

REMOTE_DIR="$TMP_DIR/remote"
CLONE_DIR="$TMP_DIR/clone"
mkdir -p "$REMOTE_DIR" "$CLONE_DIR"

(
    cd "$REMOTE_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    mkdir -p src docs
    printf 'fn main() {}\n' >src/main.uya
    printf 'guide\n' >docs/readme.md
    "$TMP_DIR/hgx" add src docs >/dev/null 2>&1
    HGX_AUTHOR_NAME='Remote User' HGX_AUTHOR_EMAIL='remote@example.com' "$TMP_DIR/hgx" commit -m "seed remote" >/dev/null 2>&1
)

stdout_file="$TMP_DIR/fetch.stdout"
stderr_file="$TMP_DIR/fetch.stderr"

set +e
(
    cd "$CLONE_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    "$TMP_DIR/hgx" fetch "file://$REMOTE_DIR"
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for file remote clone: got $status want 0" >&2
    cat "$stderr_file" >&2
    exit 1
fi

if [ -s "$stdout_file" ]; then
    echo "unexpected stdout for file remote clone" >&2
    cat "$stdout_file" >&2
    exit 1
fi

if [ -s "$stderr_file" ]; then
    echo "unexpected stderr for file remote clone" >&2
    cat "$stderr_file" >&2
    exit 1
fi

[ "$(cat "$CLONE_DIR/src/main.uya")" = "fn main() {}" ]
[ "$(cat "$CLONE_DIR/docs/readme.md")" = "guide" ]

HEAD_FILE="$CLONE_DIR/.hgit/refs/heads/main"
if [ ! -f "$HEAD_FILE" ]; then
    echo "missing head ref after file remote clone" >&2
    exit 1
fi

HEAD_HEX="$(tr -d '\n' <"$HEAD_FILE")"
if ! printf '%s' "$HEAD_HEX" | grep -Eq '^[0-9a-f]{64}$'; then
    echo "unexpected cloned head ref contents: $HEAD_HEX" >&2
    exit 1
fi

STATE_FILE="$CLONE_DIR/.hgit/workspace/state.json"
grep -F "\"base_commit\":\"$HEAD_HEX\"" "$STATE_FILE" >/dev/null
if grep -F '"view_id":"0000000000000000000000000000000000000000000000000000000000000000"' "$STATE_FILE" >/dev/null; then
    echo "view_id should be materialized after fetch clone" >&2
    exit 1
fi

ENTRY_COUNT="$(od -An -t u8 -j 40 -N 8 "$CLONE_DIR/.hgit/workspace/stage.hgi" | awk '{print $1}')"
if [ "$ENTRY_COUNT" != "0" ]; then
    echo "stage entry_count should be 0 after file remote clone, got $ENTRY_COUNT" >&2
    exit 1
fi

STATUS_STDOUT="$TMP_DIR/status.stdout"
STATUS_STDERR="$TMP_DIR/status.stderr"
(
    cd "$CLONE_DIR"
    "$TMP_DIR/hgx" status
) >"$STATUS_STDOUT" 2>"$STATUS_STDERR"

if [ -s "$STATUS_STDERR" ]; then
    echo "unexpected stderr for cloned status" >&2
    cat "$STATUS_STDERR" >&2
    exit 1
fi

grep -F "On branch main" "$STATUS_STDOUT" >/dev/null
grep -F "nothing to commit" "$STATUS_STDOUT" >/dev/null

LOG_STDOUT="$TMP_DIR/log.stdout"
LOG_STDERR="$TMP_DIR/log.stderr"
(
    cd "$CLONE_DIR"
    "$TMP_DIR/hgx" log
) >"$LOG_STDOUT" 2>"$LOG_STDERR"

if [ -s "$LOG_STDERR" ]; then
    echo "unexpected stderr for cloned log" >&2
    cat "$LOG_STDERR" >&2
    exit 1
fi

grep -F "Remote User <remote@example.com>" "$LOG_STDOUT" >/dev/null
grep -F "seed remote" "$LOG_STDOUT" >/dev/null
