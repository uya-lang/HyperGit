# Uya Compiler Bugs

## Generic wrapper around `async_compute<T>` fails to link

- Trigger command: `~/uya/uya/bin/uya build docs/repros/uya_async_compute_generic_wrapper.uya -o /tmp/uya_async_compute_generic_wrapper`
- Expected behavior: build succeeds, because the code only wraps `async_compute<T>` in another generic function and instantiates it with `i32`.
- Actual behavior: host C toolchain link step fails with an undeclared symbol for the monomorphized async helper.

Observed error excerpt:

```text
/tmp/uya_output_*.c: In function `wrap_async_compute_i32_mono`:
warning: implicit declaration of function `std_async_compute_i32`
error: invalid initializer
错误：宿主工具链链接失败
```

Minimal reproduction:

```uya
use std.runtime.entry;
use std.async.Future;
use std.thread.ThreadPool;
use std.thread.async_compute;
use std.thread.thread_pool_new;
use std.thread.thread_pool_shutdown;

fn double_i32(value: i32) i32 {
    return value * 2;
}

fn wrap_async_compute<T>(pool: &ThreadPool, compute_fn: &void, arg: T) Future<!T> {
    return async_compute<T>(pool, compute_fn, arg);
}

export fn main() i32 {
    var pool: ThreadPool = thread_pool_new(1);
    defer {
        thread_pool_shutdown(&pool);
    }

    const future: Future<!i32> = wrap_async_compute<i32>(&pool, &double_i32 as &void, 21);
    _ = future;
    return 0;
}
```

## `return some_void_call() catch { ... }` can elide the call entirely

- Trigger command: `~/uya/uya/bin/uya build docs/repros/uya_void_return_catch_elides_call.uya -o /tmp/uya_void_return_catch_elides_call && /tmp/uya_void_return_catch_elides_call; echo $?`
- Expected behavior: process exits `0`, because `wrapper()` should invoke `mark_called()`, set `CALLED = true`, then return success.
- Actual behavior: process exits `2`. Inspecting generated C showed `wrapper()` returning success immediately without emitting the `mark_called()` call.

Observed generated C excerpt from `.uyacache/.../fetch.c` after compiling `src/hgx/commands/fetch.uya`:

```text
struct err_union_void fetch_write_empty_stage(...) {
    ...
    struct StageSnapshot snapshot = ...;
    {
        struct err_union_void _uya_ret = (struct err_union_void){ .error_id = 0 };
        return _uya_ret;
    }
}
```

Minimal reproduction:

```uya
use std.runtime.entry;

export var CALLED: bool = false;

error WrapperFailed;

fn mark_called() !void {
    CALLED = true;
    return;
}

fn wrapper() !void {
    return mark_called() catch {
        return error.WrapperFailed;
    };
}

export fn main() i32 {
    wrapper() catch {
        return 1;
    };
    if !CALLED {
        return 2;
    }
    return 0;
}
```

## External `uyagin` `AsyncHandler` can segfault on the first real request

- Trigger command: `~/uya/uya/bin/uya build docs/repros/uya_uyagin_async_handler_request_crash.uya -o /tmp/uya_uyagin_async_handler_request_crash && /tmp/uya_uyagin_async_handler_request_crash >/tmp/uya_uyagin_async_handler_request_crash.log 2>&1 & pid=$!; sleep 0.3; curl -sv http://127.0.0.1:48129/ok; wait $pid`
- Expected behavior: `curl` receives `HTTP/1.1 200 OK` with body `ok\n`, and the server exits cleanly after serving one request in `UyaginMode.Debug`.
- Actual behavior: `curl` reports `Empty reply from server`, and the generated server process exits with `Segmentation fault (core dumped)`.

Observed behavior excerpt:

```text
curl: (52) Empty reply from server
Segmentation fault
```

Minimal reproduction file: [docs/repros/uya_uyagin_async_handler_request_crash.uya](/media/winger/_dde_data/winger/uya/HyperGit/docs/repros/uya_uyagin_async_handler_request_crash.uya)

```uya
use std.runtime.entry;
use std.http.types.Status;
use std.http.uyagin.AsyncHandler;
use std.http.uyagin.Engine;
use std.http.uyagin.EngineRunOptions;
use std.http.uyagin.GinContext;
use std.http.uyagin.GinListener;
use std.http.uyagin.UyaginMode;
use std.http.uyagin.uyagin_listen_loopback_with_options;
use std.http.uyagin.uyagin_new;
use std.http.uyagin.uyagin_run_options_default;
use std.async.Future;
use std.string.strlen;

fn literal_bytes(text: &const byte) &[byte] {
    return (text as &byte)[0: strlen(text)];
}

fn ok_future(ctx: &GinContext) Future<!i32> {
    return ctx.string(Status.OK, "ok\n");
}

struct OkHandler : AsyncHandler {
    @async_fn
    fn handle(self: &Self, ctx: &GinContext) Future<!i32> {
        return try @await ok_future(ctx);
    }
}

export fn main() i32 {
    var engine: Engine = uyagin_new();
    var options: EngineRunOptions = uyagin_run_options_default();
    options.mode = UyaginMode.Debug;
    engine.run_options = options;

    const handler: AsyncHandler = OkHandler{};
    engine.GET(literal_bytes("/ok"), handler) catch {
        return 1;
    };

    const listener: GinListener = uyagin_listen_loopback_with_options(48129 as u16, &engine.run_options) catch {
        return 1;
    };
    _ = engine.run_shards(&listener) catch {
        return 1;
    };
    return 0;
}
```

## Git interop test compilation can segfault the compiler

- Trigger command: `~/uya/uya/bin/uya test src/hypergit/test_git_interop.uya`
- Expected behavior: compile succeeds and runs the Git interop prototype tests.
- Actual behavior: the compiler process exits with `Segmentation fault (core dumped)` before producing a runnable binary.

Observed shell output:

```text
/bin/bash: line 1: <pid> Segmentation fault ~/uya/uya/bin/uya test src/hypergit/test_git_interop.uya
STATUS=139
```

Current smallest known reproduction inputs:

- [src/hypergit/test_git_interop.uya](/media/winger/_dde_data/winger/uya/HyperGit/src/hypergit/test_git_interop.uya:1)
- [src/hypergit/git/interop.uya](/media/winger/_dde_data/winger/uya/HyperGit/src/hypergit/git/interop.uya:1)

Notes:

- 同一批 Git interop 代码在更早一次编译中曾成功通过，当前表现疑似 codegen/优化阶段的不稳定崩溃。
- 在把 `git interop` 测试接入默认 `Makefile test` 前，需要先把这个编译器崩溃独立缩小并稳定复现。

## `object.codec.decode_object_kind` 可触发 C 后端生成非法 `invalid initializer`

- Observed trigger command: `~/uya/uya/bin/uya test src/hypergit/test_git_interop.uya`
- Expected behavior: generated C compiles successfully, and `decode_object_kind` should just decode envelope kind into `ObjectKind`.
- Actual behavior: host C toolchain rejects generated C with `invalid initializer`, pointing at the generated `hypergit_object_codec_decode_object_kind` function.

Observed error excerpt:

```text
/tmp/uya_output_*.c: In function ‘hypergit_object_codec_decode_object_kind’:
error: invalid initializer
错误：宿主工具链链接失败
```

Known source trigger:

- [src/hypergit/object/codec.uya](/media/winger/_dde_data/winger/uya/HyperGit/src/hypergit/object/codec.uya:776)

Triggering source pattern:

```uya
export fn decode_object_kind(input: &[byte], offset: &usize) !ObjectKind {
    const decoded: DecodedObject = try codec_decode_object(input, offset);
    return object_kind_from_u16(decoded.envelope.kind) catch |err| {
        _ = err;
        return error.CodecNonCanonical;
    };
}
```

Current smallest known reproducer set:

- [src/hypergit/test_git_interop.uya](/media/winger/_dde_data/winger/uya/HyperGit/src/hypergit/test_git_interop.uya:1)
- [src/hypergit/git/interop.uya](/media/winger/_dde_data/winger/uya/HyperGit/src/hypergit/git/interop.uya:1)

Notes:

- 这个问题和上一条 “Git interop test compilation can segfault the compiler” 不是同一类现象；那条是编译器进程直接崩溃，这条是生成了宿主 C 编译器无法接受的代码。
- 目前还没有缩到一个不依赖项目模块、但仍稳定触发同一 `invalid initializer` 的更小单文件 repro。
