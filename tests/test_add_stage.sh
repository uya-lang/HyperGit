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
    printf 'code' >src/main.uya
    printf 'readme' >docs/readme.md
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

run_add add_src src
run_add add_docs docs

STAGE_FILE="$REPO_DIR/.hgit/workspace/stage.hgi"
if [ ! -f "$STAGE_FILE" ]; then
    echo "missing stage file after add" >&2
    exit 1
fi

ENTRY_COUNT="$(od -An -t u8 -j 40 -N 8 "$STAGE_FILE" | awk '{print $1}')"
if [ "$ENTRY_COUNT" != "2" ]; then
    echo "unexpected stage entry_count: got $ENTRY_COUNT want 2" >&2
    od -An -t x1 "$STAGE_FILE" >&2
    exit 1
fi

OBJECT_COUNT="$(find "$REPO_DIR/.hgit/objects/loose" -type f | wc -l | tr -d ' ')"
if [ "$OBJECT_COUNT" != "2" ]; then
    echo "unexpected loose object count: got $OBJECT_COUNT want 2" >&2
    find "$REPO_DIR/.hgit/objects/loose" -maxdepth 3 -print >&2
    exit 1
fi

FIRST_KIND_HEX="$(od -An -v -t x1 -j 71 -N 2 "$STAGE_FILE" | tr -d ' \n')"
if [ "$FIRST_KIND_HEX" != "0000" ]; then
    echo "unexpected first stage entry kind bytes: $FIRST_KIND_HEX" >&2
    exit 1
fi

ZERO_HASH="$(printf '00%.0s' $(seq 1 32))"
FIRST_BASE_HEX="$(od -An -v -t x1 -j 73 -N 32 "$STAGE_FILE" | tr -d ' \n')"
if [ "$FIRST_BASE_HEX" != "$ZERO_HASH" ]; then
    echo "unexpected first base_object bytes: $FIRST_BASE_HEX" >&2
    exit 1
fi

FIRST_HAS_STAGED="$(od -An -t u1 -j 105 -N 1 "$STAGE_FILE" | awk '{print $1}')"
if [ "$FIRST_HAS_STAGED" != "1" ]; then
    echo "unexpected first has_staged_object flag: $FIRST_HAS_STAGED" >&2
    exit 1
fi

FIRST_STAGED_HEX="$(od -An -v -t x1 -j 106 -N 32 "$STAGE_FILE" | tr -d ' \n')"
if [ "$FIRST_STAGED_HEX" = "$ZERO_HASH" ]; then
    echo "first staged_object should not be zero" >&2
    exit 1
fi

FIRST_FILE_MODE="$(od -An -t u4 -j 138 -N 4 "$STAGE_FILE" | awk '{print $1}')"
if [ "${FIRST_FILE_MODE:-0}" -le 0 ]; then
    echo "unexpected first file_mode: $FIRST_FILE_MODE" >&2
    exit 1
fi
