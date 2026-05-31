# HyperGit Benchmarks

## 2026-05-29 BLAKE3 Official C/SIMD Shim

This run compares the old pure-Uya `std.crypto.blake3` path with the new
HyperGit-local shim that vendors the official BLAKE3 C implementation and
enables runtime dispatch across portable, SSE2, SSE4.1 and AVX2 code paths.

Command:

```bash
bash bench/bench_blake3_hot.sh 200000 128 3
```

Machine:

- `uname`: `Linux winger-PC 6.12.65-amd64-desktop-rolling #25.01.01.11 SMP PREEMPT_DYNAMIC Wed Jan 14 15:36:12 CST 2026 x86_64 GNU/Linux`
- `cpu`: `Intel(R) Core(TM) i7-14700`
- `cores`: `28`

Results:

| workload | before_ms | after_ms | speedup |
| --- | ---: | ---: | ---: |
| `blake3_digest(64B) * 200000` | 235 | 100 | `2.35x` |
| `blake3_digest(1MiB) * 128` | 2352 | 45 | `52.3x` |
| `hash_domain_payload(1MiB) * 128` | 2500 | 183 | `13.7x` |
| `prepare_chunked_blob_repository_parallel_default(10MiB) * 3` | 2063 | 446 | `4.63x` |

Takeaways:

- Direct large-buffer BLAKE3 throughput improved the most, which is exactly the
  hot path behind large-object hashing and pack/object validation.
- Domain-separated object hashing also sped up substantially, even after
  accounting for the extra buffer assembly step around the digest call.
- End-to-end large prepare is still bounded by chunking and object-shape work,
  but the hashing-heavy part is now much cheaper.
- The final implementation also keeps a strict-verify `segment_pack_read`
  alongside a pack-only read mode used by `composite_store`, so missing or
  corrupt sidecar indexes no longer block direct pack reads.

## 2026-05-29 Add Pathspec Hot Path

This run isolates the main `hgx add <pathspec>` bottleneck we optimized in this change:
loading base manifest inputs for a tiny pathspec from a very large committed manifest.

The benchmark compares:

- `full_avg_ms`: the old behavior of flattening the whole manifest before matching.
- `file_pathspec_avg_ms`: the new exact-file pathspec flatten.
- `dir_pathspec_avg_ms`: the new small-directory pathspec flatten.

Commands:

```bash
bash bench/bench_add_pathspec.sh 20000
bash bench/bench_add_pathspec.sh 100000
```

Machine:

- `uname`: `Linux winger-PC 6.12.65-amd64-desktop-rolling #25.01.01.11 SMP PREEMPT_DYNAMIC Wed Jan 14 15:36:12 CST 2026 x86_64 GNU/Linux`
- `cpu`: `Intel(R) Core(TM) i7-14700`
- `cores`: `28`

Results:

| entries | full_avg_ms | file_pathspec_avg_ms | dir_pathspec_avg_ms | file_matches | dir_matches |
| --- | ---: | ---: | ---: | ---: | ---: |
| 20000 | 238 | 12 | 24 | 1 | 1000 |
| 100000 | 1179 | 13 | 73 | 1 | 5000 |

Takeaways:

- At `20000` paths, exact-file pathspec load is about `19.8x` faster than full flatten.
- At `100000` paths, exact-file pathspec load is about `90.7x` faster than full flatten.
- Small-directory pathspec load also drops sharply: about `9.8x` to `16.3x` faster in these samples.

Notes:

- This benchmark is intentionally focused on the `add_load_base_inputs` hot path, because that was the dominant cost for "large committed manifest, tiny pathspec add".
- End-to-end absolute `hgx add` timings on this host were noisy during this session because another long-running `hgx add .` process was competing for CPU, so the isolated hot-path benchmark is the most trustworthy measurement from this run.
- Manual end-to-end validation still covered the actual command behavior: exact-file delete staging, directory delete staging, and single-file pathspec add without traversing unrelated/unreadable directories.
- Repeated runs on this host varied by a few milliseconds, so the table should be read as representative sample data rather than a hard constant.

## 2026-05-30 Manifest Lookup

This run measures recursive point lookup through a stored synthetic manifest.
Each lookup decodes the root node, follows child ranges as needed, and checks
the final leaf with `manifest_lookup_path`.

Command:

```bash
bash bench/bench_manifest_lookup.sh 100000 2000
```

Machine:

- `uname`: `Linux winger-PC 6.12.65-amd64-desktop-rolling #25.01.01.11 SMP PREEMPT_DYNAMIC Wed Jan 14 15:36:12 CST 2026 x86_64 GNU/Linux`
- `cpu`: `Intel(R) Xeon(R) CPU E5-2696 v4 @ 2.20GHz`
- `cores`: `44`

Results:

| entries | lookups | build_ms | hit_avg_ms | hit_us_per_lookup | hit_found | miss_avg_ms | miss_us_per_lookup | miss_found |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 100000 | 2000 | 320 | 2987 | 1493 | 2000 | 4478 | 2239 | 0 |

Takeaways:

- The benchmark now covers both exact hits and same-directory missing paths,
  so lookup cost includes the recursive manifest node decode and final leaf
  search rather than only in-memory path comparison.
- Misses are slower in this sample because they still descend into candidate
  child ranges before confirming absence at the leaf.

## 2026-05-30 Manifest Diff

This run measures the flat manifest diff path used by `hgx diff`. The synthetic
inputs are split across 20 top-level directories, with every 100th entry
modified on the right side.

Command:

```bash
bash bench/bench_manifest_diff.sh 100000 100 4
```

Machine:

- `uname`: `Linux winger-PC 6.12.65-amd64-desktop-rolling #25.01.01.11 SMP PREEMPT_DYNAMIC Wed Jan 14 15:36:12 CST 2026 x86_64 GNU/Linux`
- `cpu`: `Intel(R) Xeon(R) CPU E5-2696 v4 @ 2.20GHz`
- `cores`: `44`

Results:

| entries | change_stride | workers | changed | serial_avg_ms | parallel_avg_ms | pathspec_avg_ms | pathspec_changed |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 100000 | 100 | 4 | 1000 | 58 | 148 | 93 | 50 |

Takeaways:

- For this 100k-entry synthetic workload, serial flat diff is faster than the
  current parallel helper; thread-pool setup and the parallel two-pass count
  appear to dominate at this size.
- Pathspec-filtered parallel diff correctly limits output to the target
  top-level directory, but still scans enough structure that it is slower than
  the full serial run in this sample.

## 2026-05-30 Loose Object Get

This run writes a temporary loose object set, then measures repeated hot
`LooseObjectStore.get` calls. Each get rebuilds the loose object path, reads the
encoded object, decodes the envelope, and verifies the object hash.

Command:

```bash
bash bench/bench_loose_object_get.sh 5000 50000 128
```

Machine:

- `uname`: `Linux winger-PC 6.12.65-amd64-desktop-rolling #25.01.01.11 SMP PREEMPT_DYNAMIC Wed Jan 14 15:36:12 CST 2026 x86_64 GNU/Linux`
- `cpu`: `Intel(R) Xeon(R) CPU E5-2696 v4 @ 2.20GHz`
- `cores`: `44`

Results:

| objects | gets | payload_bytes | write_ms | get_avg_ms | get_us_per_op |
| --- | ---: | ---: | ---: | ---: | ---: |
| 5000 | 50000 | 128 | 205 | 781 | 15 |

Takeaways:

- Hot loose-object reads averaged about 15 us per get for 128-byte payloads on
  this host.
- The measured get path includes integrity verification, so this is not just
  filesystem cache read latency.

## 2026-05-30 Segment Pack Lookup

This run writes a temporary segment pack and measures repeated
`segment_pack_index_lookup` calls. The current lookup API reads and validates
the index sidecar and verifies the pack cross-reference on each lookup.

Command:

```bash
bash bench/bench_segment_pack_lookup.sh 2000 2000 128
```

Machine:

- `uname`: `Linux winger-PC 6.12.65-amd64-desktop-rolling #25.01.01.11 SMP PREEMPT_DYNAMIC Wed Jan 14 15:36:12 CST 2026 x86_64 GNU/Linux`
- `cpu`: `Intel(R) Xeon(R) CPU E5-2696 v4 @ 2.20GHz`
- `cores`: `44`

Results:

| objects | lookups | payload_bytes | prepare_ms | pack_bytes | index_bytes | lookup_avg_ms | lookup_us_per_op |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2000 | 2000 | 128 | 237 | 452112 | 128120 | 3779 | 1889 |

Takeaways:

- Segment pack lookup currently measures as a validated lookup rather than a
  cached in-memory index probe; each operation averaged about 1.9 ms here.
- The result gives a useful baseline for deciding whether to add a reusable
  decoded index/snapshot lookup path later.

## 2026-05-30 Small File Commit

This run measures an end-to-end first commit of many small files in a temporary
repo. The script records file generation separately from `hgx add` and
`hgx commit`.

Command:

```bash
bash bench/bench_small_file_commit.sh 1000 32
```

Machine:

- `uname`: `Linux winger-PC 6.12.65-amd64-desktop-rolling #25.01.01.11 SMP PREEMPT_DYNAMIC Wed Jan 14 15:36:12 CST 2026 x86_64 GNU/Linux`
- `cpu`: `Intel(R) Xeon(R) CPU E5-2696 v4 @ 2.20GHz`
- `cores`: `44`

Results:

| files | payload_bytes | write_ms | add_ms | commit_ms |
| --- | ---: | ---: | ---: | ---: |
| 1000 | 32 | 117 | 24 | 11 |

Takeaways:

- First commit of 1000 already-staged 32-byte files completed in 11 ms on this
  run.
- The add phase remains the larger part of this small-file workflow at this
  size, mostly from scanning, hashing and staging the files.

## 2026-05-30 Large File Chunk

This run measures the large-file content-defined chunking path separately from
full chunked-blob prepare. The prepare step includes chunking plus per-chunk
hash/reference construction.

Command:

```bash
bash bench/bench_large_file_chunk.sh 33554432 2 2
```

Machine:

- `uname`: `Linux winger-PC 6.12.65-amd64-desktop-rolling #25.01.01.11 SMP PREEMPT_DYNAMIC Wed Jan 14 15:36:12 CST 2026 x86_64 GNU/Linux`
- `cpu`: `Intel(R) Xeon(R) CPU E5-2696 v4 @ 2.20GHz`
- `cores`: `44`

Results:

| payload_bytes | iterations | workers | arena_bytes | chunks | chunk_avg_ms | prepare_avg_ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 33554432 | 2 | 2 | 33652736 | 7 | 1335 | 1458 |

Takeaways:

- CDC chunking is the dominant portion of the 32MiB prepare path in this
  sample.
- The randomish payload produced 7 content-defined chunks, so this run covers
  multi-chunk hashing and manifest reference construction as well as scanning.

## 2026-05-31 Manifest Diff Scheduling

This rerun revisits the 100k-entry flat diff hotspot after teaching
`manifest_flat_diff_parallel` to make an explicit execution plan:

- small full-tree diffs now short-circuit to the plain serial merge instead of
  paying the old parallel count/setup overhead;
- pathspec diffs first prune to matching top-level shards, then only walk those
  shards serially when parallelism would not amortize its own setup.

Command:

```bash
bash bench/bench_manifest_diff.sh 100000 100 4
```

Machine:

- `uname`: `Linux winger-PC 6.12.65-amd64-desktop-rolling #25.01.01.11 SMP PREEMPT_DYNAMIC Wed Jan 14 15:36:12 CST 2026 x86_64 GNU/Linux`
- `cpu`: `Intel(R) Xeon(R) CPU E5-2696 v4 @ 2.20GHz`
- `cores`: `44`

Results:

| entries | change_stride | workers | changed | serial_avg_ms | parallel_avg_ms | parallel_mode | parallel_shards | pathspec_avg_ms | pathspec_mode | pathspec_shards | pathspec_changed |
| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | --- | ---: | ---: |
| 100000 | 100 | 4 | 1000 | 55 | 56 | `serial` | 20 | 30 | `serial` | 1 | 50 |

Takeaways:

- The earlier `parallel diff slower than serial` result came from using the
  parallel helper even when the workload was too small to amortize its
  two-pass design and thread-pool setup.
- For this 100k-entry sample, the helper now deliberately chooses `serial`, so
  the "parallel" code path lands within noise of the direct serial baseline
  instead of regressing from `55ms` to `137ms` as it did on `2026-05-30`.
- Pathspec diff now prunes to the single matching top-level shard before diff
  emission, which cuts this sample from `85ms` to `30ms`.

## 2026-05-31 Segment Pack Lookup Snapshot

This rerun keeps the old validated one-shot lookup measurement, but also
measures the new reusable snapshot path:

- `validated_lookup_*`: repeated `segment_pack_index_lookup`, which still reads
  and validates the index sidecar and pack cross-reference every call;
- `snapshot_*`: one validated `segment_pack_index_read`, followed by repeated
  `segment_pack_index_lookup_snapshot` binary searches against that in-memory
  snapshot.

Command:

```bash
bash bench/bench_segment_pack_lookup.sh 2000 2000 128
```

Machine:

- `uname`: `Linux winger-PC 6.12.65-amd64-desktop-rolling #25.01.01.11 SMP PREEMPT_DYNAMIC Wed Jan 14 15:36:12 CST 2026 x86_64 GNU/Linux`
- `cpu`: `Intel(R) Xeon(R) CPU E5-2696 v4 @ 2.20GHz`
- `cores`: `44`

Results:

| objects | lookups | payload_bytes | prepare_ms | pack_bytes | index_bytes | validated_lookup_avg_ms | validated_lookup_us_per_op | snapshot_read_avg_ms | snapshot_lookup_avg_ms | snapshot_lookup_us_per_op |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2000 | 2000 | 128 | 215 | 452112 | 128120 | 3518 | 1759 | 2 | 14 | 7 |

Takeaways:

- The original `segment pack lookup` result was slow because it measured the
  fully validated path, not a hot reusable index probe. That explains the
  ~`1.76ms/op` figure.
- The codebase now exposes `segment_pack_index_lookup_snapshot`, so callers can
  amortize validation: on this host, one validated snapshot read costs about
  `2ms`, and steady-state lookup drops to about `7us/op`.
- Integrity semantics stay explicit: the one-shot lookup still validates on
  every call, while repeated lookup workloads now have a real fast path that
  reuses an already verified snapshot instead of re-reading both sidecars.

## 2026-05-30 Hydrate

This run measures restoring materialized files from the object store after a
successful `hgx dehydrate <pathspec>`. The temporary repo starts from a first
commit of 1000 small files.

Command:

```bash
bash bench/bench_hydrate.sh 1000 32
```

Machine:

- `uname`: `Linux winger-PC 6.12.65-amd64-desktop-rolling #25.01.01.11 SMP PREEMPT_DYNAMIC Wed Jan 14 15:36:12 CST 2026 x86_64 GNU/Linux`
- `cpu`: `Intel(R) Xeon(R) CPU E5-2696 v4 @ 2.20GHz`
- `cores`: `44`

Results:

| files | payload_bytes | dehydrate_ms | hydrate_ms |
| --- | ---: | ---: | ---: |
| 1000 | 32 | 205 | 280 |

Takeaways:

- Hydrating 1000 small files took 280 ms in this end-to-end sample, including
  local state reconciliation and writing file contents.
- Dehydrate is somewhat cheaper here because it deletes materialized files and
  updates virtual state rather than reading and writing object payloads.
