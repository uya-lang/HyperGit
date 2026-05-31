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
    mkdir -p src docs
    printf 'main-one' >src/main.uya
    printf 'readme-one' >docs/readme.md
    "$TMP_DIR/hgx" add src docs >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "first" >/dev/null 2>&1
    rm src/main.uya
    "$TMP_DIR/hgx" add src >/dev/null 2>&1
)

stdout_file="$TMP_DIR/commit-delete.stdout"
stderr_file="$TMP_DIR/commit-delete.stderr"

set +e
(
    cd "$REPO_DIR"
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "delete main"
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for staged delete commit: got $status want 0" >&2
    cat "$stderr_file" >&2
    exit 1
fi

if [ -s "$stdout_file" ]; then
    echo "unexpected stdout for staged delete commit" >&2
    cat "$stdout_file" >&2
    exit 1
fi

if [ -s "$stderr_file" ]; then
    echo "unexpected stderr for staged delete commit" >&2
    cat "$stderr_file" >&2
    exit 1
fi

if [ -e "$REPO_DIR/src/main.uya" ]; then
    echo "deleted path should stay absent after commit" >&2
    exit 1
fi

if [ ! -f "$REPO_DIR/docs/readme.md" ]; then
    echo "unrelated path should remain present after delete commit" >&2
    exit 1
fi

status_stdout="$TMP_DIR/status.stdout"
status_stderr="$TMP_DIR/status.stderr"

set +e
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" status
) >"$status_stdout" 2>"$status_stderr"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for status after delete commit: got $status want 0" >&2
    cat "$status_stderr" >&2
    exit 1
fi

cat >"$TMP_DIR/expected.stdout" <<'EOF'
On branch main

nothing to commit
EOF

diff -u "$TMP_DIR/expected.stdout" "$status_stdout"

if [ -s "$status_stderr" ]; then
    echo "unexpected stderr for status after delete commit" >&2
    cat "$status_stderr" >&2
    exit 1
fi
