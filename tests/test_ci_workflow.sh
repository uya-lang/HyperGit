#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/ci.yml"
MAKEFILE="$ROOT/Makefile"

require_line() {
    local needle="$1"

    if ! grep -F "$needle" "$WORKFLOW" >/dev/null; then
        echo "missing workflow line: $needle" >&2
        exit 1
    fi
}

require_absent() {
    local needle="$1"

    if grep -F "$needle" "$WORKFLOW" >/dev/null; then
        echo "unexpected workflow line: $needle" >&2
        exit 1
    fi
}

line_number() {
    local needle="$1"
    local file="$2"
    local line

    line="$(grep -nF "$needle" "$file" | head -n1 | cut -d: -f1 || true)"
    if [ -z "$line" ]; then
        echo "missing order check line in $file: $needle" >&2
        exit 1
    fi

    printf '%s\n' "$line"
}

require_before() {
    local file="$1"
    local first="$2"
    local second="$3"
    local first_line
    local second_line

    first_line="$(line_number "$first" "$file")"
    second_line="$(line_number "$second" "$file")"
    if [ "$first_line" -ge "$second_line" ]; then
        echo "expected '$first' before '$second' in $file" >&2
        exit 1
    fi
}

if [ ! -f "$WORKFLOW" ]; then
    echo "missing workflow file: $WORKFLOW" >&2
    exit 1
fi

if [ ! -f "$MAKEFILE" ]; then
    echo "missing Makefile: $MAKEFILE" >&2
    exit 1
fi

require_line "name: CI"
require_line "  push:"
require_line "  pull_request:"
require_line "    timeout-minutes: 45"
require_absent "continue-on-error: true"

strict_mode_count="$(grep -c "set -euo pipefail" "$WORKFLOW")"
if [ "$strict_mode_count" -lt 4 ]; then
    echo "expected workflow steps to use strict bash mode" >&2
    exit 1
fi

require_line "      - name: Run Test Suite"
require_line "          make test"
require_line "      - name: Native Build Smoke"
require_line "          make build"
require_line "          test -x bin/hgx"
require_line "          bin/hgx help >/dev/null"
require_line "      - name: C99 Smoke"
require_line "          make c99"
require_line "          test -s build/hgx.c"

require_before "$WORKFLOW" "      - name: Native Build Smoke" "      - name: Run Test Suite"
require_before "$WORKFLOW" "      - name: C99 Smoke" "      - name: Run Test Suite"
require_before "$MAKEFILE" "./tests/test_ci_workflow.sh" '$(UYA) test src/hypergit/test_object_model.uya'
