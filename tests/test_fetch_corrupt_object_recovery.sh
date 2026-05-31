#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

REMOTE_DIR="$TMP_DIR/remote"
LOCAL_DIR="$TMP_DIR/local"
mkdir -p "$REMOTE_DIR" "$LOCAL_DIR"

(
    cd "$REMOTE_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    mkdir -p src docs
    printf 'hello recover\n' >src/main.uya
    printf 'remote notes\n' >docs/readme.md
    "$TMP_DIR/hgx" add src docs >/dev/null 2>&1
    HGX_AUTHOR_NAME='Remote User' HGX_AUTHOR_EMAIL='remote@example.com' "$TMP_DIR/hgx" commit -m "seed remote" >/dev/null 2>&1
)

(
    cd "$LOCAL_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    "$TMP_DIR/hgx" fetch "file://$REMOTE_DIR" >/dev/null 2>&1
)

HEAD_HEX="$(tr -d '\n' <"$LOCAL_DIR/.hgit/refs/heads/main")"
CORRUPT_OBJECT="$LOCAL_DIR/.hgit/objects/loose/${HEAD_HEX:0:2}/${HEAD_HEX:2}"
printf '\x00' >"$CORRUPT_OBJECT"

doctor_before_stdout="$TMP_DIR/doctor-before.stdout"
doctor_before_stderr="$TMP_DIR/doctor-before.stderr"

set +e
(
    cd "$LOCAL_DIR"
    "$TMP_DIR/hgx" doctor
) >"$doctor_before_stdout" 2>"$doctor_before_stderr"
status=$?
set -e

if [ "$status" -ne 1 ]; then
    echo "unexpected exit code for doctor before recovery: got $status want 1" >&2
    cat "$doctor_before_stdout" >&2 || true
    cat "$doctor_before_stderr" >&2 || true
    exit 1
fi

if [ -s "$doctor_before_stderr" ]; then
    echo "unexpected stderr for doctor before recovery" >&2
    cat "$doctor_before_stderr" >&2
    exit 1
fi

grep -F "doctor: found" "$doctor_before_stdout" >/dev/null
grep -F "corrupt loose object" "$doctor_before_stdout" >/dev/null

fetch_stdout="$TMP_DIR/fetch.stdout"
fetch_stderr="$TMP_DIR/fetch.stderr"

set +e
(
    cd "$LOCAL_DIR"
    "$TMP_DIR/hgx" fetch "file://$REMOTE_DIR"
) >"$fetch_stdout" 2>"$fetch_stderr"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for fetch corruption recovery: got $status want 0" >&2
    cat "$fetch_stdout" >&2 || true
    cat "$fetch_stderr" >&2 || true
    exit 1
fi

if [ -s "$fetch_stdout" ]; then
    echo "unexpected stdout for fetch corruption recovery" >&2
    cat "$fetch_stdout" >&2
    exit 1
fi

if [ -s "$fetch_stderr" ]; then
    echo "unexpected stderr for fetch corruption recovery" >&2
    cat "$fetch_stderr" >&2
    exit 1
fi

status_stdout="$TMP_DIR/status.stdout"
status_stderr="$TMP_DIR/status.stderr"
(
    cd "$LOCAL_DIR"
    "$TMP_DIR/hgx" status
) >"$status_stdout" 2>"$status_stderr"

if [ -s "$status_stderr" ]; then
    echo "unexpected stderr for status after corruption recovery" >&2
    cat "$status_stderr" >&2
    exit 1
fi

grep -F "nothing to commit" "$status_stdout" >/dev/null

log_stdout="$TMP_DIR/log.stdout"
log_stderr="$TMP_DIR/log.stderr"
(
    cd "$LOCAL_DIR"
    "$TMP_DIR/hgx" log
) >"$log_stdout" 2>"$log_stderr"

if [ -s "$log_stderr" ]; then
    echo "unexpected stderr for log after corruption recovery" >&2
    cat "$log_stderr" >&2
    exit 1
fi

grep -F "Remote User <remote@example.com>" "$log_stdout" >/dev/null
grep -F "seed remote" "$log_stdout" >/dev/null
[ "$(cat "$LOCAL_DIR/src/main.uya")" = "hello recover" ]
[ "$(cat "$LOCAL_DIR/docs/readme.md")" = "remote notes" ]
