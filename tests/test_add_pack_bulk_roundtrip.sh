#!/usr/bin/env bash
# Pack-on-add (二合一: parallel malloc-free prepare + serial pack consume).
#
# Verifies that a bulk small-blob `hgx add` writes a streaming segment pack
# instead of loose objects, that the packed objects are byte-identical to the
# loose path (same content-addressed ids), that small adds still stay loose by
# default, and that the rest of the system (status/commit/log/checkout) reads
# packed objects correctly across a two-commit checkout roundtrip.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
HGX="$TMP_DIR/hgx"
"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$HGX" >/dev/null 2>&1

fail() { echo "FAIL: $*" >&2; exit 1; }

make_tree() {
    local dir="$1" i
    mkdir -p "$dir/src/a" "$dir/src/b" "$dir/docs"
    for i in $(seq 1 50); do printf 'alpha-%d-%d\n' "$i" $((i * 7)) >"$dir/src/a/f$i.txt"; done
    for i in $(seq 1 30); do printf 'beta-%d\n' $((i % 5)) >"$dir/src/b/g$i.dat"; done
    for i in $(seq 1 15); do printf '# doc %d\n' "$i" >"$dir/docs/d$i.md"; done
}

# Extract sorted hex object ids from every .hgi segment-pack index in a dir.
# Index layout: 48-byte header, then entry_count 64-byte entries (object id is
# the first 32 bytes of each), then a 72-byte footer.
pack_object_ids() {
    python3 - "$1" <<'PY'
import sys, glob, os
ids = []
for hgi in sorted(glob.glob(os.path.join(sys.argv[1], "*.hgi"))):
    data = open(hgi, "rb").read()
    n = (len(data) - 48 - 72) // 64
    for k in range(n):
        off = 48 + k * 64
        ids.append(data[off:off + 32].hex())
print("\n".join(sorted(ids)))
PY
}

# --- 1. forced pack add: objects land in packs, not loose ---
PACK="$TMP_DIR/pack"
LOOSE="$TMP_DIR/loose"
make_tree "$PACK"
make_tree "$LOOSE"
(cd "$PACK" && "$HGX" init >/dev/null && HGX_ADD_PACK=1 "$HGX" add src docs >/dev/null)
(cd "$LOOSE" && "$HGX" init >/dev/null && HGX_ADD_PACK=0 "$HGX" add src docs >/dev/null)

stray_loose="$(find "$PACK/.hgit/objects/loose" -type f | wc -l)"
[ "$stray_loose" -eq 0 ] || fail "pack add wrote $stray_loose loose objects (expected 0)"
pack_count="$(ls "$PACK/.hgit/objects/packs/"*.hgp 2>/dev/null | wc -l)"
[ "$pack_count" -ge 1 ] || fail "pack add wrote no .hgp pack"

# --- 2. packed objects are byte-identical to the loose path (same ids) ---
pack_object_ids "$PACK/.hgit/objects/packs" >"$TMP_DIR/pack_ids.txt"
find "$LOOSE/.hgit/objects/loose" -type f | sed "s|.*/loose/||; s|/||" | sort >"$TMP_DIR/loose_ids.txt"
[ -s "$TMP_DIR/pack_ids.txt" ] || fail "no object ids parsed from pack index"
if ! diff -u "$TMP_DIR/loose_ids.txt" "$TMP_DIR/pack_ids.txt" >"$TMP_DIR/iddiff.txt"; then
    cat "$TMP_DIR/iddiff.txt" >&2
    fail "packed object ids differ from loose object ids"
fi

# --- 3. gating: a small add without the override stays loose ---
SMALL="$TMP_DIR/small"
mkdir -p "$SMALL/x"
printf 'hello\n' >"$SMALL/x/a.txt"
(cd "$SMALL" && "$HGX" init >/dev/null && "$HGX" add x >/dev/null)
[ "$(find "$SMALL/.hgit/objects/loose" -type f | wc -l)" -ge 1 ] || fail "default small add wrote no loose objects"
[ "$(ls "$SMALL/.hgit/objects/packs/"*.hgp 2>/dev/null | wc -l)" -eq 0 ] || fail "default small add unexpectedly wrote packs"

# --- 4. status/commit/log read packs; two-commit checkout restores byte-identically ---
(cd "$PACK" && HGX_AUTHOR_NAME=t HGX_AUTHOR_EMAIL=t@t "$HGX" commit -m c1 >/dev/null)
C1="$(cd "$PACK" && "$HGX" log | sed -n 's/^commit //p' | head -1)"
[ -n "$C1" ] || fail "no commit id from log after packed commit"
cp -a "$PACK/src" "$TMP_DIR/orig_src"
cp -a "$PACK/docs" "$TMP_DIR/orig_docs"

for i in $(seq 1 50); do printf 'alpha-%d-CHANGED\n' "$i" >"$PACK/src/a/f$i.txt"; done
printf 'extra\n' >"$PACK/src/a/extra.txt"
(cd "$PACK" && HGX_ADD_PACK=1 "$HGX" add src >/dev/null && HGX_AUTHOR_NAME=t HGX_AUTHOR_EMAIL=t@t "$HGX" commit -m c2 >/dev/null)

status_out="$(cd "$PACK" && "$HGX" status 2>&1)"
echo "$status_out" | grep -q "nothing to commit" || fail "status not clean after packed second commit: $status_out"

(cd "$PACK" && "$HGX" checkout "$C1" >/dev/null 2>"$TMP_DIR/co.err") || {
    cat "$TMP_DIR/co.err" >&2
    fail "checkout of packed commit failed"
}
diff -r "$TMP_DIR/orig_src" "$PACK/src" >"$TMP_DIR/d_src.txt" 2>&1 || {
    cat "$TMP_DIR/d_src.txt" >&2
    fail "checkout did not restore src byte-identically from packs"
}
diff -r "$TMP_DIR/orig_docs" "$PACK/docs" >"$TMP_DIR/d_docs.txt" 2>&1 || {
    cat "$TMP_DIR/d_docs.txt" >&2
    fail "checkout did not restore docs byte-identically from packs"
}

echo "ok"
