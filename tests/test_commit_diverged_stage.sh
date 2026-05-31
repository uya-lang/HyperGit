#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

BASE_REPO="$TMP_DIR/base"
PRIMARY_REPO="$TMP_DIR/primary"
ADVANCER_REPO="$TMP_DIR/advancer"
mkdir -p "$BASE_REPO"

(
    cd "$BASE_REPO"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    mkdir -p src docs
    printf 'main-one' >src/main.uya
    printf 'readme-one' >docs/readme.md
    "$TMP_DIR/hgx" add src docs >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "first" >/dev/null 2>&1
)

cp -R "$BASE_REPO" "$PRIMARY_REPO"
cp -R "$BASE_REPO" "$ADVANCER_REPO"

(
    cd "$PRIMARY_REPO"
    printf 'main-two' >src/main.uya
    "$TMP_DIR/hgx" add src/main.uya >/dev/null 2>&1
)

(
    cd "$ADVANCER_REPO"
    printf 'readme-two' >docs/readme.md
    "$TMP_DIR/hgx" add docs/readme.md >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "second" >/dev/null 2>&1
)

cp -R "$ADVANCER_REPO/.hgit/objects/loose/." "$PRIMARY_REPO/.hgit/objects/loose/"
cp "$ADVANCER_REPO/.hgit/refs/heads/main" "$PRIMARY_REPO/.hgit/refs/heads/main"
cp "$ADVANCER_REPO/docs/readme.md" "$PRIMARY_REPO/docs/readme.md"

stdout_file="$TMP_DIR/diverged-commit.stdout"
stderr_file="$TMP_DIR/diverged-commit.stderr"

set +e
(
    cd "$PRIMARY_REPO"
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "third"
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for diverged stage commit: got $status want 0" >&2
    cat "$stderr_file" >&2
    exit 1
fi

if [ -s "$stdout_file" ]; then
    echo "unexpected stdout for diverged stage commit" >&2
    cat "$stdout_file" >&2
    exit 1
fi

if [ -s "$stderr_file" ]; then
    echo "unexpected stderr for diverged stage commit" >&2
    cat "$stderr_file" >&2
    exit 1
fi

status_stdout="$TMP_DIR/status.stdout"
status_stderr="$TMP_DIR/status.stderr"

set +e
(
    cd "$PRIMARY_REPO"
    "$TMP_DIR/hgx" status
) >"$status_stdout" 2>"$status_stderr"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for status after diverged stage commit: got $status want 0" >&2
    cat "$status_stderr" >&2
    exit 1
fi

cat >"$TMP_DIR/expected.stdout" <<'EOF'
On branch main

nothing to commit
EOF

diff -u "$TMP_DIR/expected.stdout" "$status_stdout"

if [ -s "$status_stderr" ]; then
    echo "unexpected stderr for status after diverged stage commit" >&2
    cat "$status_stderr" >&2
    exit 1
fi
