#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

"$HOME/uya/uya/bin/uya" build src/hgx/main.uya -o /tmp/hgx-audit-error-set-full
