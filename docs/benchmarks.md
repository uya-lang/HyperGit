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
