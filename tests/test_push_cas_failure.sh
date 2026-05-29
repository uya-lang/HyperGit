#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

REMOTE_DIR="$TMP_DIR/remote"
LOCAL_DIR="$TMP_DIR/local"
VERIFY_DIR="$TMP_DIR/verify"
mkdir -p "$REMOTE_DIR" "$LOCAL_DIR" "$VERIFY_DIR"

(
    cd "$REMOTE_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    printf 'base\n' >shared.txt
    "$TMP_DIR/hgx" add shared.txt >/dev/null 2>&1
    HGX_AUTHOR_NAME='Remote User' HGX_AUTHOR_EMAIL='remote@example.com' "$TMP_DIR/hgx" commit -m "base remote" >/dev/null 2>&1
)

(
    cd "$LOCAL_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    "$TMP_DIR/hgx" fetch "file://$REMOTE_DIR" >/dev/null 2>&1
)

(
    cd "$REMOTE_DIR"
    printf 'remote advance\n' >>shared.txt
    "$TMP_DIR/hgx" add shared.txt >/dev/null 2>&1
    HGX_AUTHOR_NAME='Remote User' HGX_AUTHOR_EMAIL='remote@example.com' "$TMP_DIR/hgx" commit -m "remote advance" >/dev/null 2>&1
)

(
    cd "$LOCAL_DIR"
    printf 'local advance\n' >>shared.txt
    "$TMP_DIR/hgx" add shared.txt >/dev/null 2>&1
    HGX_AUTHOR_NAME='Local User' HGX_AUTHOR_EMAIL='local@example.com' "$TMP_DIR/hgx" commit -m "local advance" >/dev/null 2>&1
)

stdout_file="$TMP_DIR/push.stdout"
stderr_file="$TMP_DIR/push.stderr"

set +e
(
    cd "$LOCAL_DIR"
    "$TMP_DIR/hgx" push "file://$REMOTE_DIR"
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 1 ]; then
    echo "unexpected exit code for push CAS failure: got $status want 1" >&2
    cat "$stderr_file" >&2
    exit 1
fi

if [ -s "$stdout_file" ]; then
    echo "unexpected stdout for push CAS failure" >&2
    cat "$stdout_file" >&2
    exit 1
fi

printf '%s' "error: push rejected by remote ref CAS
" >"$TMP_DIR/expected.err"
diff -u "$TMP_DIR/expected.err" "$stderr_file"

(
    cd "$VERIFY_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    "$TMP_DIR/hgx" fetch "file://$REMOTE_DIR" >/dev/null 2>&1
)

if ! grep -F "remote advance" "$VERIFY_DIR/shared.txt" >/dev/null; then
    echo "remote content should keep remote advance after CAS failure" >&2
    exit 1
fi

if grep -F "local advance" "$VERIFY_DIR/shared.txt" >/dev/null; then
    echo "remote content should not contain local advance after CAS failure" >&2
    exit 1
fi

LOG_STDOUT="$TMP_DIR/verify.log"
LOG_STDERR="$TMP_DIR/verify.log.err"
(
    cd "$VERIFY_DIR"
    "$TMP_DIR/hgx" log
) >"$LOG_STDOUT" 2>"$LOG_STDERR"

if [ -s "$LOG_STDERR" ]; then
    echo "unexpected stderr while verifying remote log" >&2
    cat "$LOG_STDERR" >&2
    exit 1
fi

grep -F "remote advance" "$LOG_STDOUT" >/dev/null
if grep -F "local advance" "$LOG_STDOUT" >/dev/null; then
    echo "remote log should not include local advance after CAS failure" >&2
    exit 1
fi
