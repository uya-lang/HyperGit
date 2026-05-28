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
    printf 'base\n' >src/main.uya
    "$TMP_DIR/hgx" add src/main.uya >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m initial >/dev/null 2>&1
)

run_add() {
    local name="$1"
    shift
    local stdout_file="$TMP_DIR/$name.stdout"
    local stderr_file="$TMP_DIR/$name.stderr"

    set +e
    (
        cd "$REPO_DIR"
        "$TMP_DIR/hgx" add "$@"
    ) >"$stdout_file" 2>"$stderr_file"
    local status=$?
    set -e

    if [ "$status" -ne 0 ]; then
        echo "unexpected exit code for $name: got $status want 0" >&2
        cat "$stderr_file" >&2
        exit 1
    fi

    if [ -s "$stdout_file" ]; then
        echo "unexpected stdout for $name" >&2
        cat "$stdout_file" >&2
        exit 1
    fi

    if [ -s "$stderr_file" ]; then
        echo "unexpected stderr for $name" >&2
        cat "$stderr_file" >&2
        exit 1
    fi
}

STAGE_FILE="$REPO_DIR/.hgit/workspace/stage.hgi"

chmod 000 "$REPO_DIR/src/main.uya"
run_add clean_fast_path src/main.uya

ENTRY_COUNT="$(od -An -t u8 -j 40 -N 8 "$STAGE_FILE" | awk '{print $1}')"
if [ "$ENTRY_COUNT" != "0" ]; then
    echo "stage entry_count should remain 0 for unchanged fast-path add, got $ENTRY_COUNT" >&2
    exit 1
fi

chmod 600 "$REPO_DIR/src/main.uya"
printf 'changed\n' >"$REPO_DIR/src/main.uya"
run_add first_stage src/main.uya

ENTRY_COUNT="$(od -An -t u8 -j 40 -N 8 "$STAGE_FILE" | awk '{print $1}')"
if [ "$ENTRY_COUNT" != "1" ]; then
    echo "stage entry_count should be 1 after staging modified file, got $ENTRY_COUNT" >&2
    exit 1
fi

OBJECT_COUNT_BEFORE="$(find "$REPO_DIR/.hgit/objects/loose" -type f | wc -l | tr -d ' ')"

chmod 000 "$REPO_DIR/src/main.uya"
run_add repeat_fast_path src/main.uya

ENTRY_COUNT="$(od -An -t u8 -j 40 -N 8 "$STAGE_FILE" | awk '{print $1}')"
if [ "$ENTRY_COUNT" != "1" ]; then
    echo "stage entry_count should stay 1 after repeat fast-path add, got $ENTRY_COUNT" >&2
    exit 1
fi

OBJECT_COUNT_AFTER="$(find "$REPO_DIR/.hgit/objects/loose" -type f | wc -l | tr -d ' ')"
if [ "$OBJECT_COUNT_AFTER" != "$OBJECT_COUNT_BEFORE" ]; then
    echo "repeat fast-path add should not publish extra loose objects: before $OBJECT_COUNT_BEFORE after $OBJECT_COUNT_AFTER" >&2
    exit 1
fi
