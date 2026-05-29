#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'chmod -R u+rwx "$TMP_DIR" 2>/dev/null || true; rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

REPO_DIR="$TMP_DIR/repo"
mkdir -p "$REPO_DIR"

(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    mkdir -p src vendor/.hg/store meta/.svn nested/.hgit/objects .repo/cache
    printf 'hello metadata skip\n' >src/main.txt
    printf 'gitdir: /tmp/real.git\n' >vendor/.git
    printf 'hg metadata\n' >vendor/.hg/store/00changelog.i
    printf 'svn metadata\n' >meta/.svn/entries
    printf 'repo metadata\n' >.repo/manifest.xml
    printf 'nested hgit metadata\n' >nested/.hgit/config.json
)

status_stdout="$TMP_DIR/status.stdout"
status_stderr="$TMP_DIR/status.stderr"

set +e
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" status
) >"$status_stdout" 2>"$status_stderr"
status_code=$?
set -e

if [ "$status_code" -ne 0 ]; then
    echo "unexpected exit code for metadata status scan: got $status_code want 0" >&2
    cat "$status_stderr" >&2
    exit 1
fi

if [ -s "$status_stderr" ]; then
    echo "unexpected stderr for metadata status scan" >&2
    cat "$status_stderr" >&2
    exit 1
fi

if ! grep -q 'src/main.txt' "$status_stdout"; then
    echo "status output should include the real workspace file" >&2
    cat "$status_stdout" >&2
    exit 1
fi

if grep -E -q '\.git|\.hg|\.svn|\.repo|\.hgit' "$status_stdout"; then
    echo "status output should ignore repo metadata paths" >&2
    cat "$status_stdout" >&2
    exit 1
fi

add_stdout="$TMP_DIR/add.stdout"
add_stderr="$TMP_DIR/add.stderr"

set +e
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" add .
) >"$add_stdout" 2>"$add_stderr"
add_code=$?
set -e

if [ "$add_code" -ne 0 ]; then
    echo "unexpected exit code for metadata add scan: got $add_code want 0" >&2
    cat "$add_stderr" >&2
    exit 1
fi

printf 'src/main.txt\n' >"$TMP_DIR/add.expected"
diff -u "$TMP_DIR/add.expected" "$add_stdout"

if [ -s "$add_stderr" ]; then
    echo "unexpected stderr for metadata add scan" >&2
    cat "$add_stderr" >&2
    exit 1
fi

STAGE_FILE="$REPO_DIR/.hgit/workspace/stage.hgi"
ENTRY_COUNT="$(od -An -t u8 -j 40 -N 8 "$STAGE_FILE" | awk '{print $1}')"
if [ "$ENTRY_COUNT" != "1" ]; then
    echo "stage entry_count should be 1 after metadata add, got $ENTRY_COUNT" >&2
    exit 1
fi

OBJECT_COUNT="$(find "$REPO_DIR/.hgit/objects/loose" -type f | wc -l | tr -d ' ')"
if [ "$OBJECT_COUNT" != "1" ]; then
    echo "metadata add should only publish the real workspace file object: got $OBJECT_COUNT" >&2
    find "$REPO_DIR/.hgit/objects/loose" -maxdepth 3 -print >&2
    exit 1
fi
