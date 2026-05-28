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
