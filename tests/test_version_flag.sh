#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

run_case() {
    local name="$1"
    shift

    local stdout_file="$TMP_DIR/$name.stdout"
    local stderr_file="$TMP_DIR/$name.stderr"
    local expected_file="$TMP_DIR/$name.expected"

    set +e
    "$TMP_DIR/hgx" "$@" >"$stdout_file" 2>"$stderr_file"
    local status=$?
    set -e

    if [ "$status" -ne 0 ]; then
        echo "unexpected exit code for $name: got $status want 0" >&2
        return 1
    fi

    if [ -s "$stderr_file" ]; then
        echo "unexpected stderr for $name" >&2
        cat "$stderr_file" >&2
        return 1
    fi

    printf 'hgx 0.1.0\n' >"$expected_file"
    diff -u "$expected_file" "$stdout_file"
}

run_case version_flag --version
run_case version_short -v
run_case version_command version
