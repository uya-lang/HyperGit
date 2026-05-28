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
    python3 -c "from pathlib import Path; p=Path('big.bin'); chunk=b'abcd1234'*131072; f=p.open('wb'); [f.write(chunk) for _ in range(9)]; f.close()"
    "$TMP_DIR/hgx" add big.bin >/dev/null 2>&1
)

CHUNK_COUNT="$(find "$REPO_DIR/.hgit/cache/chunks" -type f | wc -l | tr -d ' ')"
if [ "$CHUNK_COUNT" -lt 1 ]; then
    echo "expected cached chunks after large-file add" >&2
    exit 1
fi

set +e
(
    cd "$REPO_DIR"
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "big"
) >"$TMP_DIR/commit.stdout" 2>"$TMP_DIR/commit.stderr"
commit_status=$?
set -e

if [ "$commit_status" -ne 0 ]; then
    echo "unexpected exit code for large-file commit: got $commit_status want 0" >&2
    cat "$TMP_DIR/commit.stderr" >&2
    exit 1
fi

if [ -s "$TMP_DIR/commit.stdout" ]; then
    echo "unexpected stdout for large-file commit" >&2
    cat "$TMP_DIR/commit.stdout" >&2
    exit 1
fi

if [ -s "$TMP_DIR/commit.stderr" ]; then
    echo "unexpected stderr for large-file commit" >&2
    cat "$TMP_DIR/commit.stderr" >&2
    exit 1
fi

ENTRY_COUNT="$(od -An -t u8 -j 40 -N 8 "$REPO_DIR/.hgit/workspace/stage.hgi" | awk '{print $1}')"
if [ "$ENTRY_COUNT" != "0" ]; then
    echo "stage entry_count should be 0 after large-file commit, got $ENTRY_COUNT" >&2
    exit 1
fi

set +e
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" status
) >"$TMP_DIR/status.stdout" 2>"$TMP_DIR/status.stderr"
status_code=$?
set -e

if [ "$status_code" -ne 0 ]; then
    echo "unexpected exit code for large-file clean status: got $status_code want 0" >&2
    cat "$TMP_DIR/status.stderr" >&2
    exit 1
fi

cat >"$TMP_DIR/expected.stdout" <<'EOF'
On branch main

nothing to commit
EOF

diff -u "$TMP_DIR/expected.stdout" "$TMP_DIR/status.stdout"

if [ -s "$TMP_DIR/status.stderr" ]; then
    echo "unexpected stderr for large-file clean status" >&2
    cat "$TMP_DIR/status.stderr" >&2
    exit 1
fi
