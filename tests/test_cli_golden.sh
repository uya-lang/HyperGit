#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

run_case() {
    local name="$1"
    local expected_exit="$2"
    local expected_stderr="$3"
    shift 3

    local stdout_file="$TMP_DIR/$name.stdout"
    local stderr_file="$TMP_DIR/$name.stderr"

    set +e
    "$TMP_DIR/hgx" "$@" >"$stdout_file" 2>"$stderr_file"
    local status=$?
    set -e

    if [ "$status" -ne "$expected_exit" ]; then
        echo "unexpected exit code for $name: got $status want $expected_exit" >&2
        return 1
    fi

    if [ -s "$stdout_file" ]; then
        echo "unexpected stdout for $name" >&2
        cat "$stdout_file" >&2
        return 1
    fi

    diff -u "$ROOT/$expected_stderr" "$stderr_file"
}

run_case unknown 2 tests/golden/unknown.stderr bogus
run_case add_usage 2 tests/golden/add_usage.stderr add
run_case doctor 3 tests/golden/doctor.stderr doctor
