#!/usr/bin/env bash
set -euo pipefail

# Regression test for symlink-aware diff and robust handling of unreadable
# worktree files:
#   * A committed symlink that is unchanged must not crash `diff` and must not
#     show up as a spurious change (previously aborted with
#     "error: failed to compute diff").
#   * Changing a symlink target must render as a content diff of the target.
#   * A worktree file that cannot be read (permission denied) must be skipped
#     rather than aborting the whole command.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'chmod -R u+rwX "$TMP_DIR" 2>/dev/null || true; rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1
HGX="$TMP_DIR/hgx"

REPO_DIR="$TMP_DIR/repo"
mkdir -p "$REPO_DIR"

(
    cd "$REPO_DIR"
    "$HGX" init >/dev/null 2>&1
    printf 'hello\n' >file.txt
    ln -s file.txt link
    "$HGX" add file.txt link >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$HGX" commit -m "first" >/dev/null 2>&1
)

run_diff() {
    # usage: run_diff <stdout_file> [pathspec...]
    local out="$1"; shift
    local err="${out}.err"
    set +e
    ( cd "$REPO_DIR" && "$HGX" diff "$@" ) >"$out" 2>"$err"
    local status=$?
    set -e
    if [ "$status" -ne 0 ]; then
        echo "unexpected exit code for 'diff $*': got $status want 0" >&2
        cat "$err" >&2
        exit 1
    fi
    if [ -s "$err" ]; then
        echo "unexpected stderr for 'diff $*'" >&2
        cat "$err" >&2
        exit 1
    fi
}

# 1. Clean tree with a committed symlink: no output, no crash.
run_diff "$TMP_DIR/clean.stdout"
if [ -s "$TMP_DIR/clean.stdout" ]; then
    echo "expected empty diff on clean tree with committed symlink" >&2
    cat "$TMP_DIR/clean.stdout" >&2
    exit 1
fi

run_diff "$TMP_DIR/clean_dot.stdout" .
if [ -s "$TMP_DIR/clean_dot.stdout" ]; then
    echo "expected empty 'diff .' on clean tree with committed symlink" >&2
    cat "$TMP_DIR/clean_dot.stdout" >&2
    exit 1
fi

# 2. Modify only the regular file: the unchanged symlink must NOT appear.
( cd "$REPO_DIR" && printf 'hello2\n' >file.txt )
run_diff "$TMP_DIR/modify.stdout"
grep -F "diff --hgx a/file.txt b/file.txt" "$TMP_DIR/modify.stdout" >/dev/null
if grep -F "a/link" "$TMP_DIR/modify.stdout" >/dev/null; then
    echo "unchanged committed symlink should not appear in diff" >&2
    cat "$TMP_DIR/modify.stdout" >&2
    exit 1
fi

# 3. Change the symlink target: rendered as a target content diff.
( cd "$REPO_DIR" && rm link && ln -s other.txt link )
run_diff "$TMP_DIR/relink.stdout"
grep -F "diff --hgx a/link b/link" "$TMP_DIR/relink.stdout" >/dev/null
grep -F -- "-file.txt" "$TMP_DIR/relink.stdout" >/dev/null
grep -F "+other.txt" "$TMP_DIR/relink.stdout" >/dev/null

# 4. An unreadable untracked file must be skipped, not abort the diff.
#    (Skipped when running as root, where file permissions do not block reads.)
if [ "$(id -u)" -ne 0 ]; then
    ( cd "$REPO_DIR" && printf 'secret\n' >unreadable.bin && chmod 000 unreadable.bin )
    run_diff "$TMP_DIR/unreadable.stdout"
    if grep -F "unreadable.bin" "$TMP_DIR/unreadable.stdout" >/dev/null; then
        echo "unreadable file should be skipped, not shown in diff" >&2
        cat "$TMP_DIR/unreadable.stdout" >&2
        exit 1
    fi
    # The readable change (file.txt) should still be present alongside the skip.
    grep -F "diff --hgx a/file.txt b/file.txt" "$TMP_DIR/unreadable.stdout" >/dev/null
    ( cd "$REPO_DIR" && chmod u+rw unreadable.bin && rm -f unreadable.bin )
fi

echo "test_diff_symlink: OK"
