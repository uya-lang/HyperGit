#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

REMOTE_DIR="$TMP_DIR/remote"
LOCAL_DIR="$TMP_DIR/local"
PEER_DIR="$TMP_DIR/peer"
mkdir -p "$REMOTE_DIR" "$LOCAL_DIR" "$PEER_DIR"

(
    cd "$REMOTE_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
)

(
    cd "$LOCAL_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    mkdir -p src docs
    printf 'push happy path\n' >src/main.uya
    printf 'remote guide\n' >docs/readme.md
    "$TMP_DIR/hgx" add src docs >/dev/null 2>&1
    HGX_AUTHOR_NAME='Local User' HGX_AUTHOR_EMAIL='local@example.com' "$TMP_DIR/hgx" commit -m "seed local" >/dev/null 2>&1
)

push_stdout="$TMP_DIR/push.stdout"
push_stderr="$TMP_DIR/push.stderr"

set +e
(
    cd "$LOCAL_DIR"
    "$TMP_DIR/hgx" push "file://$REMOTE_DIR"
) >"$push_stdout" 2>"$push_stderr"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for file remote push happy path: got $status want 0" >&2
    cat "$push_stderr" >&2
    exit 1
fi

if [ -s "$push_stdout" ]; then
    echo "unexpected stdout for file remote push happy path" >&2
    cat "$push_stdout" >&2
    exit 1
fi

if [ -s "$push_stderr" ]; then
    echo "unexpected stderr for file remote push happy path" >&2
    cat "$push_stderr" >&2
    exit 1
fi

fetch_stdout="$TMP_DIR/fetch.stdout"
fetch_stderr="$TMP_DIR/fetch.stderr"

set +e
(
    cd "$PEER_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    "$TMP_DIR/hgx" fetch "file://$REMOTE_DIR"
) >"$fetch_stdout" 2>"$fetch_stderr"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for file remote fetch happy path: got $status want 0" >&2
    cat "$fetch_stderr" >&2
    exit 1
fi

if [ -s "$fetch_stdout" ]; then
    echo "unexpected stdout for file remote fetch happy path" >&2
    cat "$fetch_stdout" >&2
    exit 1
fi

if [ -s "$fetch_stderr" ]; then
    echo "unexpected stderr for file remote fetch happy path" >&2
    cat "$fetch_stderr" >&2
    exit 1
fi

[ "$(cat "$PEER_DIR/src/main.uya")" = "push happy path" ]
[ "$(cat "$PEER_DIR/docs/readme.md")" = "remote guide" ]

STATUS_STDOUT="$TMP_DIR/status.stdout"
STATUS_STDERR="$TMP_DIR/status.stderr"
(
    cd "$PEER_DIR"
    "$TMP_DIR/hgx" status
) >"$STATUS_STDOUT" 2>"$STATUS_STDERR"

if [ -s "$STATUS_STDERR" ]; then
    echo "unexpected stderr for fetched peer status" >&2
    cat "$STATUS_STDERR" >&2
    exit 1
fi

grep -F "nothing to commit" "$STATUS_STDOUT" >/dev/null

LOG_STDOUT="$TMP_DIR/log.stdout"
LOG_STDERR="$TMP_DIR/log.stderr"
(
    cd "$PEER_DIR"
    "$TMP_DIR/hgx" log
) >"$LOG_STDOUT" 2>"$LOG_STDERR"

if [ -s "$LOG_STDERR" ]; then
    echo "unexpected stderr for fetched peer log" >&2
    cat "$LOG_STDERR" >&2
    exit 1
fi

grep -F "Local User <local@example.com>" "$LOG_STDOUT" >/dev/null
grep -F "seed local" "$LOG_STDOUT" >/dev/null
