#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

"$HOME/uya/uya/bin/uya" test src/hypergit/test_workspace_vfs.uya
