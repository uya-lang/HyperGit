# Uya `std.http` API 评估

本文记录 HyperGit `HTTP Remote` 阶段对 `~/uya/uya/lib/std/http/` 当前 API 的一次实际评估，目标是判断现有标准库是否足以支撑 `capabilities`、`manifest query`、`fetch`、`push` 等服务端接口。

评估时读取的核心实现：

- `std/http/types.uya`
- `std/http/parse.uya`
- `std/http/server.uya`
- `std/http/router.uya`
- `std/http/epoll_server.uya`
- `std/http/uyagin.uya`
- `std/http/uyagin_router.uya`
- `std/http/http1_async.uya`

## 结论

当前 `std.http` 已经足够支撑 HyperGit 的 HTTP skeleton、`capabilities`、基础鉴权 hook、`manifest query` 和一个小体积的 `fetch` 元数据接口。

最合适的落地入口不是最低层的 `server.uya`，而是更高一层的 `uyagin.uya`：

- 已有路由注册、方法分派、path param 绑定。
- 已有异步连接处理、`epoll` 驱动、基础错误恢复。
- 已有静态字节、arena 字节、文件体三种响应体封装。
- 已有 middleware / access log / limit 配置位。

但它还不适合直接承载“任意大对象上传”这一类请求体很大的接口。当前请求解析模型本质上仍是“把整个请求体读进固定缓冲后再解析”，默认上限是 `64 KiB`。

## 当前 API 分层

### 1. 低层阻塞式 HTTP 原语

`std.http.server` + `std.http.types` + `std.http.parse` 提供了：

- 监听、`accept`、读请求、写响应。
- `Request` / `Response` / `Context` / `Handler` 这些基础结构。
- chunked 请求体解码、header/query/path 解析。

适合：

- 做最小原型。
- 写非常小的协议 smoke test。
- 需要完全自己控制连接循环时使用。

限制：

- 公开的监听实现只绑定 `127.0.0.1`。
- 请求仍是固定缓冲读满后整体解析。
- 自己处理路由、错误映射和连接生命周期会比较重。

### 2. 低层 epoll server

`std.http.epoll_server` 在 `server` 之上补了：

- `epoll` 监听和连接槽管理。
- 非阻塞 `accept` / `read` / `write` 辅助。

适合：

- 需要明确控制事件循环，但不想直接手搓所有 `epoll` 细节。

限制：

- 还是固定大小连接缓冲。
- 还是 loopback-only 监听。
- API 更像“拼装件”，不是业务接口层。

### 3. 高层异步框架 `uyagin`

`std.http.uyagin` + `std.http.uyagin_router` 已经是一套可用的 HTTP 服务端框架：

- `Engine`、`GinListener`、`AsyncHandler`、`RouterGroup`。
- `GET/POST/PUT/PATCH/DELETE/OPTIONS/HEAD` 路由注册。
- path param 绑定。
- request limit 配置、access log、recovery、metrics。
- 字节响应、JSON 响应、文件响应、chunked 响应。
- `serve_conn` / `run` / `run_shards` 等运行入口。

对 HyperGit 来说，这是最值得复用的层。

## 和 HyperGit HTTP Remote 的匹配度

### 适合直接用现有 API 实现的部分

- `HTTP route skeleton`
- `capabilities endpoint`
- `manifest query endpoint`
- `fetch endpoint` 的“小响应元数据版”
- `request size limit`
- `基础鉴权 hook`
- `服务端 smoke test`

原因：

- 这些接口请求体很小，或者根本没有请求体。
- `uyagin` 已有路由与响应封装，脚手架成本低。
- `http1_async.uya` 还能直接拿来写客户端 smoke test。

### 需要谨慎推进的部分

- `object batch endpoint`
- `push endpoint`

原因：

- `std.http.types.MAX_BODY_SIZE` 目前是 `65536`。
- `std.http.server.HTTP_CONN_READ_CAP` 也是围绕这一量级设计。
- `parse.uya` 的 `Content-Length` / chunked 解码路径都以内存中的完整请求体为前提。

这意味着：

- 小批量对象推送可以先做。
- 大对象上传、长请求体批量推送暂时不适合直接压在现有解析路径上。
- 如果 HyperGit 的 `push` 要承载真正的对象批量上传，后面大概率需要“流式请求体读取”扩展，而不是只靠当前 parser。

## 明显约束

### 1. 默认只暴露 loopback 监听

现有公开监听入口基本都走：

- `http_server_listen`
- `epoll_server_listen`
- `uyagin_listen_loopback*`

它们内部都绑定 `127.0.0.1`。`ServerConfig.host` 结构存在，但当前低层监听实现没有真正按它做通用 bind。

这对当前阶段不是阻塞：

- 我们先做本机 smoke test 完全够用。

但它是后续真实远端部署前必须补的一层能力。

### 2. 请求体不是流式的

当前模型更接近：

1. 把请求读进固定缓冲。
2. 解析完整 HTTP 请求。
3. 再把 `Request.body` 作为切片交给 handler。

这对：

- `capabilities`
- `manifest query`
- 小 JSON 请求

很合适。

但对：

- 大对象上传
- 非常大的批量 push

不合适。

### 3. 有少量代码生成/实现层注意事项

标准库源码自己就写了几处“避坑注释”，例如：

- `router.uya` 注明不要对某些定长数组直接做切片比较。
- `server.uya` 注明 `match` 需要显式 `else`，否则 C 后端可能生成空转分支。

这说明 HTTP 相关代码虽然可用，但写法要偏保守，最好复用标准库已有模式，不要太激进地抽象。

## 推荐落地方案

### Phase 19 推荐实现顺序

1. 用 `uyagin.uya` 起一个 loopback-only HTTP skeleton。
2. 先实现 `GET /capabilities`。
3. 再实现 `POST /manifest/query` 这类小请求体接口。
4. `fetch endpoint` 先做“小请求体 + 小响应元数据”版本。
5. `object batch` / `push` 先限制请求体规模，作为过渡版。
6. 等 HTTP 路径跑通后，再决定是否为大请求体补“流式上传”能力。

### 推荐当前不要做的事

- 不要一上来把大对象 push 直接建在现有 `MAX_BODY_SIZE=64 KiB` 的解析路径上。
- 不要为了 HTTP server 第一版就自己绕开 `uyagin` 重新写一层完整框架。
- 不要把“公网可监听”当作 Phase 19 的完成前提；先把 loopback smoke 跑通更合理。

## 对 TODO 19 的直接影响

- `实现 HTTP route skeleton`：直接用 `uyagin`。
- `实现 capabilities endpoint`：无明显阻塞。
- `实现 object batch endpoint`：先做小体积版本。
- `实现 manifest query endpoint`：无明显阻塞。
- `实现 fetch endpoint`：先做元数据/小响应版本。
- `实现 push endpoint`：先做受请求体上限约束的过渡版。
- `实现 request size limit`：`uyagin` 已有 limits，可直接接。
- `实现基础鉴权 hook`：走 middleware。
- `实现服务端 smoke test`：客户端可直接用 `http1_async.uya`。

## 总结

对 HyperGit 当前阶段来说，`std.http` 不是“缺 HTTP”，而是“有一套够做 MVP 的 HTTP 栈，但大请求体上传能力还不成熟”。

因此 Phase 19 最现实的策略是：

- 先用 `uyagin` 做 loopback HTTP MVP。
- 先把控制面接口跑通。
- 把大对象/大批量上传留给下一轮流式请求体能力补足。
