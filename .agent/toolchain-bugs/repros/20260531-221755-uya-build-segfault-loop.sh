#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

for i in $(seq 1 20); do
    tmpdir="$(mktemp -d)"
    if "$HOME/uya/uya/bin/uya" build src/hgx/main.uya -o "$tmpdir/hgx" >/dev/null 2>&1; then
        status=0
    else
        status=$?
    fi
    if [ "$status" -ne 0 ]; then
        echo "iteration=$i status=$status"
        rm -rf "$tmpdir"
        exit "$status"
    fi
    rm -rf "$tmpdir"
done

echo "no failure observed"
