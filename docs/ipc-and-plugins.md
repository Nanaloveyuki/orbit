# IPC、HTTP 与插件

Orbit 的 MoonView、HTTP、插件和后台调用最终进入同一个传输无关的命令注册表与能力
策略。适配器负责认证上下文，注册表负责命令解析、权限和处理器执行。

## 页面 IPC

Orbit 注入：

```javascript
window.__ORBIT__.invoke(command, payload?, { timeout? })
```

调用返回 Promise。失败会抛出 `OrbitIpcError`，包含 `code`、`message` 和可选 `data`。
请求和响应上限为 256 KiB；JSON 使用严格解析，重复键在进入命令处理器前被拒绝。

每次调用携带 typed principal、transport 和 origin。待处理 ID 按已认证页面主体与 origin
隔离，重复 ID 被拒绝；超时、完成和取消竞争只允许一次响应交付。没有显式
`timeout_ms` 的 protocol-v1 请求默认 30 秒。

`CommandRegistry` 支持同步和异步 JSON 处理器。异步处理器要求 `orbit-core.run_async`。
页面 timeout 会取消结构化子任务，CPU 密集型处理器可以通过
`InvocationContext.cancellation()` 协作检查取消。

## HTTP 适配器

`orbit-ipc-http` 在默认精确路径 `POST /orbit/v1/invoke` 提供同一协议。它要求
`application/json`，并且构造适配器时必须提供认证回调。请求头不能直接选择 Orbit
principal；认证回调返回不透明的 `AuthenticatedHttpClient`，再由普通能力策略决定
命令权限。

适配器本身不监听端口。宿主负责创建 `moonbitlang/async/http.Server`，选择绑定地址、
TLS 或可信反向代理边界、连接限制和关闭时机，然后传给 `HttpAdapter::serve`。认证返回
`None` 时，适配器会在读取 body 前返回 HTTP 401。

Orbit 默认不开启 HTTP，也不会默认授权任何 HTTP principal。明文 bearer credential
只能用于 loopback 或其他明确可信的传输边界。

## 原生插件

Orbit 支持 `orbit-plugin-abi` v1 和 v2：

- ABI v1 是同步兼容路径；
- ABI v2 在单个专用 native worker 上执行 `create`、`invoke` 和 `destroy`，要求
  `orbit-core.run_async`。

sidecar 使用 `schema_version: 2`：

```json
{
  "schema_version": 2,
  "abi_version": 2,
  "id": "example.echo",
  "name": "Example Echo",
  "version": "1",
  "platforms": ["windows", "linux"],
  "requested_permissions": ["app.read"],
  "commands": [
    {
      "name": "echo",
      "request_schema": {},
      "response_schema": {}
    }
  ]
}
```

`orbit-build` 在不加载动态库的前提下严格解析并嵌入 sidecar。激活前，Orbit 再比较
sidecar 与库通过 ABI 报告的 id、名称、版本、命令和权限。配置中的权限必须覆盖
`requested_permissions`；sidecar 不能自行获得权限。

插件命令映射为 `plugin:<plugin-id>/<command>`，页面是否可调用仍由 capability 决定。

## ABI v2 宿主请求

ABI v2 插件可以从当前 executor 的 `invoke` 调用栈同步请求普通 Orbit 命令。该请求以
`plugin` principal 重新进入同一注册表，因此目标命令需要显式 grant。返回值是完整的
protocol-v1 response envelope。

边界要求：

- callback context 只能在当前 `invoke` 调用栈使用，不能保留或从插件自建线程调用；
- host request 不能调用 `plugin:*`；
- 当插件唯一 worker 正等待 host response 时，直接或间接再次调用该插件会快速失败；
- 外层取消和关闭会取消 native wait 与对应结构化异步任务；
- worker 未确认停止时，Orbit 不卸载动态库，并把 shutdown failure 返回给应用。

这些约束避免同一 executor 的重入死锁，以及 worker 仍执行代码时卸载动态库。

## 集成验证

仓库 fixture 会编译真实 ABI v1/v2 动态库，覆盖权限拒绝、manifest 不匹配、错误响应、
host request、取消、间接重入和关闭顺序。

Windows：

```powershell
./orbit-plugin-fixtures/run-integration.ps1
```

Linux：

```sh
./orbit-plugin-fixtures/run-integration.sh
```
