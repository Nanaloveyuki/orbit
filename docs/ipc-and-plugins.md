# IPC、HTTP 与插件

Orbit 的 MoonView、HTTP、插件和后台调用最终进入同一个传输无关的命令注册表与能力
策略。适配器负责认证上下文，注册表负责命令解析、权限和处理器执行。

## 页面 IPC

Orbit 注入：

```javascript
window.__ORBIT__.invoke(command, payload?, { timeout?, signal? })
```

调用返回 Promise。失败会抛出 `OrbitIpcError`，包含 `code`、`message` 和可选 `data`。
JSON 使用严格解析，重复键在进入命令处理器前被拒绝。当前实验版保留各层既有的限制单位：

- 页面 `invoke` 的完整请求 envelope 最多 262144 个 UTF-8 字节（256 KiB）。
- 传输无关解析器最多接受 262144 个 Unicode 标量值；单个解码后 JSON 字符串最多
  131072 个标量值。直接调用注册表仍受这些限制，但不经过页面的字节检查。
- 注册表对处理器结果或失败序列化后的完整响应检查 `max_response_chars`，默认上限
  为 262144 个 UTF-16 code unit，即 MoonBit `String.length()`，不是 UTF-8 字节数。
  超出时返回 `response_too_large`。协议拒绝及替代错误 envelope 不再递归受此限制。

这些限制不等价，也不是处理器执行过程或序列化过程的内存预算。

桌面异步 IPC 每个调用 scope 最多保留 64 个在途请求，全局最多 256 个；超出时返回
`ipc_busy`，完成或取消后释放名额。远程页面权限使用原生消息来源，不使用导航目标推断。
Linux 当前缺少可信消息来源元数据，因此不支持远程页面 IPC，本地页面 IPC 不受影响。

每次调用携带 typed principal、transport 和 origin。待处理 ID 按已认证页面主体与 origin
隔离；同一 scope 的在途 ID 重复提交返回 `duplicate_invocation`，原任务不被替换。
调用方不可用重复 ID 区分两次调用。每个已接受任务最多交付一次终止响应；取消消息本身
没有应答，迟到结果被丢弃。没有显式
`timeout_ms` 的 protocol-v1 请求默认 30 秒。

`CommandRegistry` 支持同步和异步 JSON 处理器。异步处理器要求 `orbit-core.run_async`。
页面 timeout 或 `AbortSignal` 会发送尽力而为的取消消息；桌面异步调度器取消对应结构化子任务。
窗口销毁、成功进入挂起清理或运行时失败会取消该窗口所有 origin 的在途任务，不影响
其他窗口。取消与超时不撤销已经发生的写入或其他副作用。

`run_async` 的 MoonBit 回调仍在 UI 线程执行，不会自动把同步处理器移到 worker。
处理器必须让出执行权，计时器与取消才能被处理；阻塞 FFI 和不让出的 CPU 循环无法被
强制抢占。`InvocationContext.cancellation()` 是协作信号，不是线程中断。
直接调用注册表的 `dispatch_async` 不启用计时器；自行接入异步传输时使用
`orbit-ipc-async.dispatch_with_deadline` 或 `dispatch_source_with_deadline`。

原生文件对话框是例外：`orbit.dialog.*` 在页面消息到达时同步由窗口 UI 线程执行，避免
将系统 modal UI 发送到 async worker。页面可取消前的超时不会关闭已显示的系统对话框；
用户取消会产生正常的 `{ "cancelled": true }` 结果。完整 capability 配置和 payload
格式见[配置文件](configuration.md#原生文件对话框)。

## 前端 bindings

```sh
npx orbit bindings --config orbit.conf.json
```

生成 `orbit-bindings.mjs` 和同名 `orbit-bindings.d.mts`。输出为 `.js` 时，声明文件为
`.d.ts`，该 JavaScript 文件仍是 ES module。两个文件均由 `orbit-build` 维护。
生成文件可以直接被 Vite 导入，不需要运行时 npm 依赖，也不要求 React 或 Vue。

```typescript
import { createClient, type CommandDefinition } from "./orbit-bindings.mjs";

interface Commands {
  "example.ping": CommandDefinition<{ value: number }, { message: string }>;
}
interface Events {
  "app.changed": { revision: number };
}
const client = createClient<Commands, Events>();
const controller = new AbortController();
const result = await client.commands["example.ping"]({ value: 1 }, {
  timeout: 5000,
  signal: controller.signal,
});
const unlisten = client.listen("app.changed", event => {
  console.log(event.payload.revision);
}, { signal: controller.signal });
unlisten();
client.dispose();
```

类型边界：

- 默认生成命令名，payload 和结果为 `unknown`。配置中的 grant 不是数据 schema，
  Orbit 不会据此猜测请求或响应类型。
- `createClient<Commands, Events>` 的业务类型由应用声明，不是从 MoonBit 源码自动推导。
  声明只提供编译期检查，不执行 JSON 校验。后端仍应使用类型化 `register` /
  `register_async`，前端处理不可信结果时应使用应用自己的解码器或字段校验。
- 当前可选的 `orbit.contract.json` 会同时生成 MoonBit 编解码/注册函数和 TypeScript
  类型；支持 string `enum`、固定 discriminator 的 `tagged_union`、对象、数组、字典和
  nullable。契约文件是当前阶段的输入格式，后续版本可能改为从更强的公开类型声明反向
    生成，因此应用不应把生成文件当作手写源文件。
    `schema_version` 使用对象形式：`orbit` 必须匹配当前 Orbit 发布版本，`contract`
    是契约编译器版本；不兼容的契约或生成器变化递增 `contract`，纯新增兼容字段保持不变。
- tagged union 的 `variants` 每项应是包含 discriminator 字段的完整对象；例如
  `tag: "kind"`、`variants: { "started": { ... "kind": { "enum": ["started"] } } }`。
  变体会生成带 payload 的 MoonBit enum 和 TypeScript 交叉类型，收到未知 discriminator
  时会以 `invalid_event` 或 `invalid_response` 拒绝。
- 类型化 client 的命令必须出现在生成列表里；导出的原始 `invoke` 保留动态命令调用能力，
  返回 `Promise<unknown>`。命令列表包含页面 allow grant 中的候选命令，不能用来判定
  当前页面权限；origin、principal 和 deny 仍由宿主在每次请求时判断。

生命周期：

- `createClient()` 在调用时读取当前 bridge；导入模块不会要求原生宿主存在。
  `isAvailable()` 只检查调用桥是否存在，不保证某个命令获授权。
- `createClient({ bridge })` 可以注入测试替身，不需要覆盖全局变量；Orbit 不自动选择 HTTP。
- `listen` 返回幂等清理函数，`once` 在第一次事件执行前解除订阅；监听可绑定 `AbortSignal`。
- `dispose()` 取消该 client 的在途调用并移除其订阅，不影响其他 client；销毁后调用返回
  `client_disposed`。组件卸载时应清理 client 或自己的 signal/订阅。
- `pagehide` 使该页面的在途调用以 `page_unloaded` 失败并发送取消消息，同时清除事件监听。
  浏览器历史缓存恢复后，页面可以重新调用，但应用需在 `pageshow` 重新订阅并查询当前状态。
  此清理不承诺在进程崩溃或强制终止时执行，也不是异步保存屏障。
- 取消返回 `cancelled`，超时返回 `timeout`。生成 client 会把宿主错误转换为可导入的
  `OrbitIpcError` 并保留 `code`、`message`、`data`。旧宿主若忽略 signal，client 仍会停止
  等待，但无法承诺旧宿主停止任务。

## HTTP 适配器

`orbit-ipc-http` 在默认精确路径 `POST /orbit/v1/invoke` 提供同一协议。它要求
`application/json`，并且构造适配器时必须提供认证回调。请求头不能直接选择 Orbit
principal；认证回调返回不透明的 `AuthenticatedHttpClient`，再由普通能力策略决定
命令权限。

适配器本身不监听端口。宿主负责创建 `moonbitlang/async/http.Server`，选择绑定地址、
TLS 或可信反向代理边界、连接限制和关闭时机，然后传给 `HttpAdapter::serve`。认证返回
`None` 时，适配器会在读取 body 前返回 HTTP 401。

HTTP 请求体按实际 UTF-8 字节计数，`max_request_bytes` 默认 262144，超出返回
HTTP 413 / `request_too_large`；响应的 `max_response_chars` 仍按上述 UTF-16 单位计数。

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


