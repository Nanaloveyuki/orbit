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
  --orbit-build .mooncakes/Nanaloveyuki/orbit/orbit-build \
  --config old-orbit.conf.json \
  --output orbit.conf.json
```

迁移器会把旧窗口 capability 转成 `window` principal 的 allow grant。publisher、图标、
Vite 等无法推断的字段需要应用作者补充。
