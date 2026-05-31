#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

stdout_file="$TMP_DIR/help.stdout"
stderr_file="$TMP_DIR/help.stderr"

set +e
"$TMP_DIR/hgx" --help >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for help: got $status want 0" >&2
    exit 1
fi

if [ -s "$stderr_file" ]; then
    echo "unexpected stderr for help" >&2
    cat "$stderr_file" >&2
    exit 1
fi

require_line() {
    local expected="$1"
    if ! grep -Fqx "$expected" "$stdout_file"; then
        echo "missing expected help line: $expected" >&2
        cat "$stdout_file" >&2
        exit 1
    fi
}

require_line "Merge Scope:"
require_line "  merge CLI and conflict workflow remain deferred to v1.1+"
require_line "Branch / Clone Scope:"
require_line "  branch CLI remains deferred to v1.1+"
require_line "  clone CLI remains deferred to v1.1+; use 'hgx init' + 'hgx fetch file://...'"
