#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

EMPTY_DIR="$TMP_DIR/empty"
NONEMPTY_DIR="$TMP_DIR/nonempty"
mkdir -p "$EMPTY_DIR" "$NONEMPTY_DIR"
printf 'data' >"$NONEMPTY_DIR/file.txt"

run_init_case() {
    local dir="$1"
    local expected_exit="$2"
    local expected_stdout_substr="$3"
    local expected_stderr="$4"

    local stdout_file="$TMP_DIR/out.txt"
    local stderr_file="$TMP_DIR/err.txt"

    set +e
    (
        cd "$dir"
        "$TMP_DIR/hgx" init
    ) >"$stdout_file" 2>"$stderr_file"
    local status=$?
    set -e

    if [ "$status" -ne "$expected_exit" ]; then
        echo "unexpected exit code for init in $dir: got $status want $expected_exit" >&2
        return 1
    fi

    if [ -n "$expected_stdout_substr" ]; then
        grep -F "$expected_stdout_substr" "$stdout_file" >/dev/null
    else
        if [ -s "$stdout_file" ]; then
            echo "unexpected stdout for init in $dir" >&2
            cat "$stdout_file" >&2
            return 1
        fi
    fi

    if [ -n "$expected_stderr" ]; then
        printf '%s' "$expected_stderr" >"$TMP_DIR/expected.err"
        diff -u "$TMP_DIR/expected.err" "$stderr_file"
    else
        if [ -s "$stderr_file" ]; then
            echo "unexpected stderr for init in $dir" >&2
            cat "$stderr_file" >&2
            return 1
        fi
    fi
}

run_init_case "$EMPTY_DIR" 0 "initialized HyperGit repository in" ""

for path in \
    ".hgit" \
    ".hgit/config.json" \
    ".hgit/refs/heads" \
    ".hgit/objects/loose" \
    ".hgit/objects/packs" \
    ".hgit/indexes" \
    ".hgit/workspace"
do
    if [ ! -e "$EMPTY_DIR/$path" ]; then
        echo "missing initialized path: $path" >&2
        exit 1
    fi
done

grep -F '"format_version":1' "$EMPTY_DIR/.hgit/config.json" >/dev/null
grep -F '"default_branch":"main"' "$EMPTY_DIR/.hgit/config.json" >/dev/null

run_init_case "$EMPTY_DIR" 0 "reinitialized HyperGit repository in" ""
run_init_case "$NONEMPTY_DIR" 1 "" "error: refusing to initialize in a non-empty directory
"
