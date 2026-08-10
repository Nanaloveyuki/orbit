# Orbit 配置

Orbit 工具只接受严格 JSON 和 `schema_version: 2`。未知字段、重复键、非法资源路径和
不完整的权限声明会在生成阶段失败。

## 最小配置

```json
{
  "schema_version": 2,
  "app": {
    "identifier": "dev.example.app",
    "name": "Example App",
    "version": "0.1.0",
    "product_name": "Example App",
    "windows": [
      {
        "label": "main",
        "title": "Example App",
        "width": 1024,
        "height": 720,
        "entry": "assets/index.html",
        "visible": true,
        "resizable": true
      }
    ]
  },
  "bundle": {
    "icons": [],
    "windows": { "webview_install_mode": "embed_bootstrapper" }
  },
  "web": {
    "embedded": {
      "csp": "default-src 'self'; script-src 'self'; style-src 'self'"
    }
  },
  "build": {},
  "capabilities": [
    {
      "identifier": "main-window-commands",
      "effect": "allow",
      "principals": [{ "kind": "window", "identifier": "main" }],
      "scopes": [],
      "commands": ["example.ping"]
    }
  ],
  "plugins": []
}
```

## 顶层字段

| 字段 | 作用 |
| --- | --- |
| `app` | 应用身份、展示信息和窗口列表 |
| `bundle` | 图标、Windows WebView2 安装方式和 Linux 原生包元数据 |
| `web` | 嵌入资源 CSP，以及可选的远端 HTTPS 页面 |
| `build` | 可选的 Vite 开发与构建命令 |
| `capabilities` | 命令 allow/deny 策略 |
| `plugins` | 原生动态库、sidecar 和权限授予 |

`app.identifier` 是安装和打包身份，应使用稳定的反向域名形式。每个窗口 label 必须
唯一。每个窗口入口文件所在目录形成独立资源根，因此不同窗口可以包含同名相对资源。

## 能力策略

页面不会因为注册了命令就自动获得调用权。每条 capability 包含：

- 唯一 `identifier`；
- `effect`：`allow` 或 `deny`，匹配的 deny 优先；
- 一个或多个 `principals`；
- 可选的 transport/origin `scopes`；
- 一个或多个完整命令名。

支持的 principal kind：

- `window`
- `remote_page`
- `http_client`
- `plugin`
- `background_task`

支持的 scope kind：

- `transport`：值为 `moonview`、`http`、`plugin` 或 `background`；
- `origin`：值为精确 origin，例如 `https://app.example`。

为远端页面授权时必须同时限制 MoonView transport 和精确 HTTPS origin：

```json
{
  "identifier": "remote-read",
  "effect": "allow",
  "principals": [{ "kind": "remote_page", "identifier": "main" }],
  "scopes": [
    { "kind": "transport", "value": "moonview" },
    { "kind": "origin", "value": "https://app.example" }
  ],
  "commands": ["data.read"]
}
```

## 原生文件对话框

`orbit.dialog.open`、`orbit.dialog.open_multiple`、`orbit.dialog.save` 和
`orbit.dialog.pick_directory` 及 `orbit.fs.*` 属于可选的内建文件 capability bridge，不会
因为配置了 IPC registry 而自动注册。应用必须明确启用：

```moonbit
let options = @core.DesktopOptions::new(
  windows~,
  ipc_registry=Some(registry),
  ipc_policy=Some(policy),
).with_builtin_file_capabilities()
```

启用后这些命令默认仍没有权限，且仅接受 `window` principal；不要向 `remote_page`、
`http_client`、`plugin` 或 `background_task` 授予它们。应用若自行管理文件系统，应保持
bridge 关闭并只注册自己的业务命令。

```json
{
  "identifier": "main-file-dialogs",
  "effect": "allow",
  "principals": [{ "kind": "window", "identifier": "main" }],
  "scopes": [],
  "commands": ["orbit.dialog.open", "orbit.dialog.open_multiple"]
}
```

payload 是对象，可选字段为 `title`、`filters`、`default_name` 和
`initial_directory`。每个 filter 使用 `{ "name": "Text", "extensions": ["txt"] }`。

成功取消返回 `{ "cancelled": true, "files": [] }`；选择结果返回
`{ "cancelled": false, "files": [{ "id", "name", "kind" }] }`。`id` 是绑定到选择
窗口的随机 capability handle，页面永远不会收到原生路径。当前 Windows 支持 picker；
其他 runtime 返回 `dialog_unsupported`。

## 窗口打印

`orbit.window.print` 只接受空对象 `{}`，并且只允许已获授权的本地 `window` principal
为自己的当前 WebView 文档打开原生打印对话框。成功响应为 `{ "opened": true }`；未支持
的 runtime 返回 `print_unsupported`，窗口不存在、远端页面、HTTP、插件和后台调用返回
`print_unavailable`。它是同步窗口命令，即使应用使用 `run_async` 也不会移到异步 worker。

```json
{
  "identifier": "main-window-print",
  "effect": "allow",
  "principals": [{ "kind": "window", "identifier": "main" }],
  "scopes": [],
  "commands": ["orbit.window.print"]
}
```

## 句柄文件访问

`orbit.fs.read_binary`、`orbit.fs.read_text`、`orbit.fs.write_text` 和
`orbit.fs.read_directory` 仅在 `@core.run_async` 启动的
应用中可用。它们是异步命令，仍须显式向本地 `window` principal 授权；同步
`run` 应用会得到标准 `async_unavailable` 响应。

两个读取命令都只接受 picker 返回的 `{ "id": "..." }`，并且只接受 `Read` 句柄：
目录、保存和其他窗口的句柄均会被拒绝。单次读取最多 64 KiB，`read_binary`
返回 `{ "data": "<base64>", "size": <bytes> }`，`read_text` 返回
`{ "text": "<utf8>", "size": <bytes> }`。本机路径不会出现在请求、响应或
错误中。

```json
{
  "identifier": "main-file-reads",
  "effect": "allow",
  "principals": [{ "kind": "window", "identifier": "main" }],
  "scopes": [],
  "commands": ["orbit.fs.read_text", "orbit.fs.read_binary", "orbit.fs.write_text", "orbit.fs.read_directory"]
}
```

`orbit.fs.write_text` 只接受保存 picker 返回的 `Write` handle 和 `{ "text": "..." }`。
文本上限同为 64 KiB；Orbit 在目标同目录创建已完整同步的临时文件，再通过替换重命名完成
保存。成功响应为 `{ "size": <bytes> }`，失败路径不会出现在响应中。读取和目录句柄不能
用于写入。

`orbit.fs.read_directory` 只接受目录 picker 返回的 `Directory` handle 和
`{ "id": "..." }`。picker 返回时 Orbit 已取得目录的原生 no-follow handle；命令构造
最多 128 个非隐藏直接子项的 `{ "name", "kind", "id" }` 数组，不接受相对或本机路径。
能通过已持有父目录句柄安全打开的普通文件会携带新的 opaque `Read` `id`，可传给
`orbit.fs.read_text` 或 `orbit.fs.read_binary`；子目录携带新的 `Directory` `id`，可继续
调用 `orbit.fs.read_directory`。symlink、Windows junction 和其他 reparse point 不会被
跟随或发放 child handle。
同一父目录的同名子 capability 会复用；每个窗口最多保留 256 个目录派生的原生
capability（文件和目录合计），达到上限时条目仍可显示但不会携带新的 `id`。

目录 capability 目前只支持目录相对的只读文件与目录枚举；不支持写入、创建、删除或
页面提供的相对路径。

## 远端 HTTPS 页面

`web.remote` 是显式生产模式，不是开发服务器快捷方式：

```json
{
  "web": {
    "embedded": { "csp": "default-src 'self'" },
    "remote": {
      "http_url": "https://app.example/start",
      "allowed_origins": ["https://app.example"],
      "fallback_entry": "assets/fallback.html"
    }
  }
}
```

约束如下：

- 初始地址必须是 HTTPS，且 origin 必须出现在 `allowed_origins`；
- 不接受 HTTP、通配 origin 或重复 origin；
- 加载失败或被拒绝的远端导航会进入嵌入式 fallback；
- 远端页面使用独立 `remote_page` principal，默认没有 IPC 权限；
- IPC bridge 只注入顶层页面，iframe 不能使用宿主 IPC；
- `web.remote` 与 `build.vite` 互斥。

普通外部导航默认拒绝。应用可以在 runtime options 中提供回调，对单个 URL 做出决定。

## Vite

```json
{
  "build": {
    "vite": {
      "dev_command": "npm run dev",
      "dev_url": "http://127.0.0.1:5173",
      "build_command": "npm run build",
      "dist_dir": "dist"
    }
  }
}
```

命令相对于配置文件目录原样执行。CLI 不推断包管理器、框架、script 名或输出目录。
`dev_url` 必须是无尾部斜杠的 HTTP(S) URL，`dist_dir` 必须是规范化相对路径。

## 插件声明

```json
{
  "plugins": [
    {
      "id": "example.echo",
      "library": "plugins/example_echo.dll",
      "manifest": "plugins/example_echo.orbit-plugin.json",
      "permissions": ["app.read"]
    }
  ]
}
```

`library` 和 `manifest` 都是安装根目录下的规范化相对路径。开发覆盖目录只能通过 CLI
的 `--plugin-dir` / `ORBIT_PLUGIN_DIRECTORY` 传入，不会写入配置或配置指纹。

插件 sidecar 的 schema 和运行边界见
[`ipc-and-plugins.md`](ipc-and-plugins.md)。

## v1 迁移

正常工具不会隐式读取或升级 schema v1。迁移命令要求不同的输出路径，拒绝覆盖输入和
已有输出：

```sh
npx orbit migrate-config \
  --config old-orbit.conf.json \
  --output orbit.conf.json
```

迁移器会把旧窗口 capability 转成 `window` principal 的 allow grant。publisher、图标、
Vite 等无法推断的字段需要应用作者补充。
