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
    "$TMP_DIR/hgx" add src/main.uya >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "first" >/dev/null 2>&1
    rm src/main.uya
)

stdout_file="$TMP_DIR/add-delete-file.stdout"
stderr_file="$TMP_DIR/add-delete-file.stderr"

set +e
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" add src/main.uya
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for file pathspec delete add: got $status want 0" >&2
    cat "$stderr_file" >&2
    exit 1
fi

printf 'src/main.uya\n' >"$TMP_DIR/expected.stdout"
diff -u "$TMP_DIR/expected.stdout" "$stdout_file"

if [ -s "$stderr_file" ]; then
    echo "unexpected stderr for file pathspec delete add" >&2
    cat "$stderr_file" >&2
    exit 1
fi

STAGE_FILE="$REPO_DIR/.hgit/workspace/stage.hgi"
ENTRY_COUNT="$(od -An -t u8 -j 40 -N 8 "$STAGE_FILE" | awk '{print $1}')"
if [ "$ENTRY_COUNT" != "1" ]; then
    echo "unexpected stage entry_count after file pathspec delete: got $ENTRY_COUNT want 1" >&2
    exit 1
fi

FIRST_KIND_HEX="$(od -An -v -t x1 -j 69 -N 2 "$STAGE_FILE" | tr -d ' \n')"
if [ "$FIRST_KIND_HEX" != "0200" ]; then
    echo "unexpected delete stage entry kind bytes for file pathspec: $FIRST_KIND_HEX" >&2
    exit 1
fi

FIRST_HAS_STAGED="$(od -An -t u1 -j 103 -N 1 "$STAGE_FILE" | awk '{print $1}')"
if [ "$FIRST_HAS_STAGED" != "0" ]; then
    echo "file pathspec delete stage entry should not carry staged_object, got flag $FIRST_HAS_STAGED" >&2
    exit 1
fi
