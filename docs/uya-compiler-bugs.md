# Uya Compiler Bugs

## Validation Refresh (2026-05-29)

使用 `~/uya/uya/bin/uya`（`v0.9.7`）重新逐条验证后，当前状态如下：

- `async_compute<T>` 泛型 wrapper 条目：`docs/repros/uya_async_compute_generic_wrapper.uya` 现在可直接构建成功，原始 link failure 已不再复现。
- `return some_void_call() catch { ... }` 条目：`docs/repros/uya_void_return_catch_elides_call.uya` 现在构建并运行后返回 `0`，调用不再被错误省略。
- `error enum wrapper` 条目：`docs/repros/uya_error_enum_wrapper_invalid_c.uya` 现在构建并运行后返回 `0`，错误联合重包场景未再触发 C 后端异常。
- `uyagin AsyncHandler` 首请求崩溃条目：`docs/repros/uya_uyagin_async_handler_request_crash.uya` 现在能返回 `ok` 响应，未再复现 `Segmentation fault`；当前行为是服务保持运行，需由外部终止。
- `git interop` 编译器崩溃条目：`~/uya/uya/bin/uya test src/hypergit/test_git_interop.uya` 当前通过，5 个测试均成功。
- `decode_object_kind` `invalid initializer` 条目：`~/uya/uya/bin/uya test src/hypergit/test_object_codec.uya` 当前通过；`docs/repros/uya_decode_object_kind_invalid_c.uya` 这个独立文件目前由于模块根不匹配，已经不是一个有效的 standalone repro。

为防止这些模式回归，仓库现在有显式回归测试 `src/hypergit/test_compiler_regressions.uya`，并已接入 `Makefile test`。
本次复验中，`~/uya/uya/bin/uya test src/hypergit/test_compiler_regressions.uya` 也通过，4 个场景全部为 `OK`，其中包含 `error enum wrapper` 重包错误联合的历史回归。
另外，编译器仓库现在有专门的 C99 回归脚本 `tests/verify_c99_struct_array_and_typed_route_regressions.sh`，并已接入 `make check`，用于覆盖本页这两个 2026-05-31 修复掉的 codegen 回归。
2026-05-31 补充复验：在 `~/uya/uya` 执行 `make uya` 重建默认自举编译器后，`./tests/verify_c99_struct_array_and_typed_route_regressions.sh` 也直接通过，因此这两个 C99 codegen 回归已经落到主线 `bin/uya`，不再只依赖 `bin/uya-hosted`。

## Array field copy in a struct literal generates a pointer-to-byte initializer

- Current status (2026-05-31): 不再复现。使用当前工作区源码重建后的 `~/uya/uya/bin/uya` 重新验证，`docs/repros/uya_array_field_copy_generates_pointer_initializer.uya` 现在可直接构建并运行成功，退出码为 `0`，宿主 C 编译阶段也不再出现 `-Wint-conversion` 警告。
- Validation command: `~/uya/uya/bin/uya build docs/repros/uya_array_field_copy_generates_pointer_initializer.uya -o /tmp/uya_array_field_copy_generates_pointer_initializer && /tmp/uya_array_field_copy_generates_pointer_initializer; echo $?`
- Expected behavior: build has no C warning, and the program exits `0` because both copied bytes match the source hash.
- Historical failure behavior: generated C initialized the first byte of the fixed array from a pointer expression, emitted `-Wint-conversion`, and the program exited non-zero.

Error excerpt:

```text
warning: initialization of 'unsigned char' from 'uint8_t *' {aka 'unsigned char *'} makes integer from pointer without a cast [-Wint-conversion]
```

Minimal reproduction file: [docs/repros/uya_array_field_copy_generates_pointer_initializer.uya](/media/winger/_dde_data/winger/uya/HyperGit/docs/repros/uya_array_field_copy_generates_pointer_initializer.uya)

## Generic wrapper around `async_compute<T>` fails to link

- Current status (2026-05-29): 不再复现。`docs/repros/uya_async_compute_generic_wrapper.uya` 在 `v0.9.7` 下可直接构建成功。
- Validation command: `~/uya/uya/bin/uya build docs/repros/uya_async_compute_generic_wrapper.uya -o /tmp/uya_async_compute_generic_wrapper`
- Expected behavior: build succeeds, because the code only wraps `async_compute<T>` in another generic function and instantiates it with `i32`.
- Historical failure behavior: host C toolchain link step fails with an undeclared symbol for the monomorphized async helper.

Historical error excerpt:

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

- Current status (2026-05-29): 不再复现。`docs/repros/uya_void_return_catch_elides_call.uya` 当前构建并运行后返回 `0`。
- Validation command: `~/uya/uya/bin/uya build docs/repros/uya_void_return_catch_elides_call.uya -o /tmp/uya_void_return_catch_elides_call && /tmp/uya_void_return_catch_elides_call; echo $?`
- Expected behavior: process exits `0`, because `wrapper()` should invoke `mark_called()`, set `CALLED = true`, then return success.
- Historical failure behavior: process exits `2`. Inspecting generated C showed `wrapper()` returning success immediately without emitting the `mark_called()` call.

Historical generated C excerpt from `.uyacache/.../fetch.c` after compiling `src/hgx/commands/fetch.uya`:

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

- Current status (2026-05-29): 首请求崩溃不再复现。当前实测返回 `HTTP/1.1 200 OK` 与 `ok` body；服务进程会继续存活，需要外部终止。
- Validation command: `~/uya/uya/bin/uya build docs/repros/uya_uyagin_async_handler_request_crash.uya -o /tmp/uya_uyagin_async_handler_request_crash && /tmp/uya_uyagin_async_handler_request_crash >/tmp/uya_uyagin_async_handler_request_crash.log 2>&1 & pid=$!; sleep 0.8; curl http://127.0.0.1:48129/ok; kill $pid; wait $pid`
- Expected behavior: `curl` receives `HTTP/1.1 200 OK` with body `ok\n`, and the server exits cleanly after serving one request in `UyaginMode.Debug`.
- Historical failure behavior: `curl` reports `Empty reply from server`, and the generated server process exits with `Segmentation fault (core dumped)`.

Historical behavior excerpt:

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

## `Engine.GET_T<T>` typed route registration generates invalid C

- Current status (2026-05-31): 不再复现。使用当前工作区源码重建后的 `~/uya/uya/bin/uya` 重新验证，`docs/repros/uya_uyagin_typed_route_generic_invalid_c.uya` 现在可直接构建成功，`GET_T<TypedHandler>` 会继续单态化到 `Engine.add_typed<TypedHandler>` 与 `uyagin_route_store_typed_handler<TypedHandler>`。
- Validation command: `~/uya/uya/bin/uya build docs/repros/uya_uyagin_typed_route_generic_invalid_c.uya -o /tmp/uya_uyagin_typed_route_generic_invalid_c`
- Expected behavior: build succeeds, because `GET_T<TypedHandler>` should monomorphize through `Engine.add_typed<TypedHandler>` and store the typed handler in the route.
- Historical failure behavior: generated `std/http/uyagin.c` referenced `uya_Engine_add_typed_H`, then failed with `implicit declaration of function` and `invalid initializer`.

Error excerpt:

```text
home/winger/uya/uya/lib/std/http/uyagin.c:1392:52: warning: implicit declaration of function 'uya_Engine_add_typed_H'
home/winger/uya/uya/lib/std/http/uyagin.c:1392:52: error: invalid initializer
错误：make 链接失败，返回码：512
```

Minimal reproduction file: [docs/repros/uya_uyagin_typed_route_generic_invalid_c.uya](/media/winger/_dde_data/winger/uya/HyperGit/docs/repros/uya_uyagin_typed_route_generic_invalid_c.uya)

```uya
use std.runtime.entry;
use std.async.Future;
use std.http.types.Status;
use std.http.uyagin.AsyncHandler;
use std.http.uyagin.Engine;
use std.http.uyagin.GinContext;
use std.http.uyagin.uyagin_new;
use std.string.strlen;

fn literal_bytes(text: &const byte) &[byte] {
    return (text as &byte)[0: strlen(text)];
}

struct TypedHandler : AsyncHandler {
    @async_fn
    fn handle(self: &Self, ctx: &GinContext) Future<!i32> {
        return try @await ctx.string(Status.OK, "ok\n");
    }
}

fn register_route(engine: &Engine, handler: &TypedHandler) !void {
    try engine.GET_T<TypedHandler>(literal_bytes("/ok"), handler);
}

export fn main() i32 {
    var engine: Engine = uyagin_new();
    const handler: TypedHandler = TypedHandler{};
    register_route(&engine, &handler) catch {
        return 1;
    };
    return 0;
}
```

## Git interop test compilation can segfault the compiler

- Current status (2026-05-29): 不再复现。`~/uya/uya/bin/uya test src/hypergit/test_git_interop.uya` 当前通过，2 个测试均成功。
- Validation command: `~/uya/uya/bin/uya test src/hypergit/test_git_interop.uya`
- Expected behavior: compile succeeds and runs the Git interop prototype tests.
- Historical failure behavior: the compiler process exits with `Segmentation fault (core dumped)` before producing a runnable binary.

Historical shell output:

```text
/bin/bash: line 1: <pid> Segmentation fault ~/uya/uya/bin/uya test src/hypergit/test_git_interop.uya
STATUS=139
```

Current smallest known reproduction inputs:

- [src/hypergit/test_git_interop.uya](/media/winger/_dde_data/winger/uya/HyperGit/src/hypergit/test_git_interop.uya:1)
- [src/hypergit/git/interop.uya](/media/winger/_dde_data/winger/uya/HyperGit/src/hypergit/git/interop.uya:1)

Notes:

- 这一条目前应视为历史回归记录；现有 `v0.9.7` 复验中未再出现编译器进程崩溃。
- `src/hypergit/test_git_interop.uya` 已接入默认 `Makefile test`。

## `object.codec.decode_object_kind` 可触发 C 后端生成非法 `invalid initializer`

- Current status (2026-05-29): 项目内路径不再复现。`~/uya/uya/bin/uya test src/hypergit/test_object_codec.uya` 当前通过；`docs/repros/uya_decode_object_kind_invalid_c.uya` 则因为模块根不匹配，已经失效为 standalone repro。
- Validation command: `~/uya/uya/bin/uya test src/hypergit/test_object_codec.uya`
- Historical trigger command: `~/uya/uya/bin/uya test src/hypergit/test_git_interop.uya`
- Expected behavior: generated C compiles successfully, and `decode_object_kind` should just decode envelope kind into `ObjectKind`.
- Historical failure behavior: host C toolchain rejects generated C with `invalid initializer`, pointing at the generated `hypergit_object_codec_decode_object_kind` function.

Historical error excerpt:

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
- `docs/repros/uya_decode_object_kind_invalid_c.uya` 当前会先在类型检查阶段因模块根不匹配失败，因此不再是可用的独立复现输入。
