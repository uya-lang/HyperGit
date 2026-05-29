Official BLAKE3 C implementation vendored from:

- repository: `https://github.com/BLAKE3-team/BLAKE3`
- header version: `1.8.5`

Included files in this directory are the minimal set used by HyperGit's local
FFI shim:

- `blake3.c`
- `blake3.h`
- `blake3_impl.h`
- `blake3_dispatch.c`
- `blake3_portable.c`
- `blake3_sse2.c`
- `blake3_sse41.c`
- `blake3_avx2.c`
- `hypergit_blake3_bridge.c`

HyperGit currently enables official runtime dispatch for portable, SSE2, SSE4.1
and AVX2 code paths, and intentionally disables AVX-512 in the local build to
reduce compile and portability risk.
