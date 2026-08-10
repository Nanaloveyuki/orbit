# Orbit

[![validation](https://github.com/Nanaloveyuki/orbit/actions/workflows/validation.yml/badge.svg)](https://github.com/Nanaloveyuki/orbit/actions/workflows/validation.yml)
[![npm](https://img.shields.io/npm/v/%40nanaloveyuki%2Forbit-cli?tag=alpha&label=orbit-cli)](https://www.npmjs.com/package/@nanaloveyuki/orbit-cli)

Orbit 是一个用 MoonBit 构建的原生桌面应用框架。它以 Orby 管理窗口和事件循环，
以 MoonView 嵌入系统 WebView，并在网页前端与 MoonBit 后端之间提供受能力策略约束的
IPC。应用可以使用原生 HTML/CSS/JavaScript，也可以接入 React、Vue 等 Vite 前端。

当前版本为 `0.1.0-alpha.2`。Windows 和 Linux 已进入持续集成验证；API 与配置仍可能在
正式版前调整。

## 已实现

- 多窗口桌面生命周期，以及每个窗口独立的嵌入资源根。
- 构建时嵌入 Web 资源，运行时不依赖源码目录中的前端文件。
- 同步与异步 MoonBit 命令、超时、取消、结构化错误和 256 KiB 消息限制。
- 以窗口、远端页面、HTTP 客户端、插件和后台任务为主体的 allow/deny 能力策略。
- 可选的、默认关闭的认证 HTTP IPC 适配器。
- HTTPS 远端页面、精确 origin 白名单和嵌入式失败回退页。
- 原生插件 ABI v1/v2、sidecar schema、权限声明和可观察的安全关闭。
- Vite 开发/生产流程，以及 JavaScript IPC bindings 生成。
- 图标生成、可校验目录包、Windows NSIS 安装包、Linux `tar.gz`、deb、rpm 和 Arch 包。

## 五分钟运行

先安装 [MoonBit 工具链](https://www.moonbitlang.com/download/) 和本机原生编译工具链，
然后执行：

```sh
git clone https://github.com/Nanaloveyuki/orbit.git
cd orbit
moon update
moon run orbit-example
```

运行后会打开一个由 Orby 创建、MoonView 渲染的原生窗口。页面按钮调用
`example.ping`，MoonBit 后端返回 JSON，完整路径可在
[`orbit-example`](orbit-example/) 中查看。

修改 `orbit-example/assets` 后，先重新生成嵌入资源：

```sh
moon run --target native orbit-build orbit-example/orbit.conf.json orbit-example/generated_page.mbt
moon run orbit-example
```

### 平台前置

| 平台 | 开发依赖 | 当前状态 |
| --- | --- | --- |
| Windows x64 | MSVC/Windows SDK；首次 native build 会自动下载并校验 WebView2 SDK | 主要开发平台，CI 与安装包流程已验证 |
| Linux x64 | C 编译器、GTK3、WebKitGTK 4.1 开发包 | Ubuntu/Fedora/Arch 构建与打包流程已验证 |
| macOS | - | Orbit 顶层窗口宿主尚未实现 |
| Android/OpenHarmony | - | 相关底层库有独立探索，当前不是 Orbit 应用目标平台 |

Windows 的 WebView2 SDK 默认缓存到
`%LOCALAPPDATA%\moonview\webview2\1.0.4078.44`；通常不需要手工配置 SDK。
目标机器使用系统 Evergreen WebView2 Runtime，安装包可按配置下载或携带安装程序。

Ubuntu/Debian 开发机可安装：

```sh
sudo apt-get install libgtk-3-dev libwebkit2gtk-4.1-dev
```

## 在应用中使用

新应用可以直接由 npm CLI 创建：

```sh
npx @nanaloveyuki/orbit-cli@alpha init my-orbit-app \
  --name "My Orbit App" \
  --identifier com.example.my-orbit-app \
  --module example/my-orbit-app
cd my-orbit-app
moon update
npm install
npm run orbit:run
```

`init` 原子创建一个不会覆盖现有目录的 vanilla 应用，包含 MoonBit native 入口、schema
v2 配置、受 capability 保护的 IPC 示例、前端资源和 npm scripts。第一次运行会生成
`generated_page.mbt`；建议将该文件提交，以便审查嵌入资源与权限变化。

向现有模块添加 Orbit：

```sh
moon add Nanaloveyuki/orbit@0.1.0-alpha.2
npm install --save-dev @nanaloveyuki/orbit-cli@alpha
npx orbit generate
npx orbit run
```

CLI 会优先使用工作区内的 `orbit-build`，其次使用 Mooncakes 已物化的生成器；首次构建
需要时会按 `moon.mod` 的固定版本 fetch 到项目级 `.repos`。`--orbit-build` 仅用于显式
覆盖。

MoonBit 后端注册命令，配置文件决定哪个页面可以调用它：

```moonbit
let registry = @ipc.CommandRegistry::new()
registry.register_json(@ipc.CommandName::new("example.ping"), _payload => {
  Ok({ "message": "IPC round trip completed." })
})
```

```javascript
const response = await window.__ORBIT__.invoke("example.ping", { value: 1 }, {
  timeout: 5000,
});
```

生成的 `orbit-bindings.mjs` 也可以为当前页面实际获授权的命令提供固定入口。完整安装、
`moon.pkg`、应用入口和生成步骤见[入门指南](docs/getting-started.md)。

## React、Vue 与 Vite

Orbit 不绑定前端框架。只要前端能够输出静态目录，就可以嵌入可执行文件；开发模式由
CLI 启动明确配置的 Vite 命令并等待 `dev_url`：

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

```sh
npx orbit dev
npx orbit build
```

CLI 不猜测 React、Vue、包管理器或输出目录；所有命令都来自 `orbit.conf.json`。

## CLI 与发布产物

[`@nanaloveyuki/orbit-cli`](https://www.npmjs.com/package/@nanaloveyuki/orbit-cli)
是零运行时依赖的 Node.js 20+ 工具，覆盖以下常用流程：

```sh
npx orbit init --help
npx orbit diagnose --json
npx orbit bindings
npx orbit icon --source assets/icon-1024.png --out-dir icons
npx orbit package --release --out-dir dist
npx orbit verify-package --package-dir dist
```

Windows 可以从已校验的目录包生成 NSIS 安装程序；Linux 可以生成可移植 archive 或
调用发行版原生工具生成 deb、rpm、Arch 包。生产产物要求外部签名命令，本地测试必须
显式使用 `--allow-unsigned`。详见[打包指南](docs/packaging.md)。

## 生态组成

| 项目 | 职责 |
| --- | --- |
| [Orbit on Mooncakes](https://mooncakes.io/docs/Nanaloveyuki/orbit) | 框架、构建器、运行时适配和 IPC 包 |
| [Orbit CLI on npm](https://www.npmjs.com/package/@nanaloveyuki/orbit-cli) | 生成、开发、构建、图标和分发命令 |
| [Orby](https://github.com/Nanaloveyuki/orby) | 原生窗口与宿主事件循环 |
| [MoonView](https://github.com/Nanaloveyuki/moonview) | 系统 WebView 嵌入层 |
| [orbit-plugin-abi](https://github.com/Nanaloveyuki/orbit-plugin-abi) | 稳定的 C 插件 ABI 与异步 executor |
| [Ajni](https://github.com/Nanaloveyuki/ajni) | 通用 JNI 与 Android JNI 基础设施 |
| [sync](https://github.com/Nanaloveyuki/sync) | 原生线程同步原语 |
| [dynlib](https://github.com/Nanaloveyuki/dynlib) | 动态库加载 |
| [image](https://github.com/Nanaloveyuki/image) | 图标解码、缩放和多格式输出 |
| [Parsec](https://github.com/Nanaloveyuki/parsec) | 严格 JSON 解析等解析基础设施 |
| [moonbitlang/async](https://github.com/moonbitlang/async) | 官方结构化异步运行时 |

Orbit 参考了 Tauri 的分层经验，但不是 Tauri API 的 MoonBit 移植。窗口、WebView、IPC、
插件与打包边界均按 MoonBit 当前语言能力和原生生态重新设计。

## 文档

- [入门与应用结构](docs/getting-started.md)
- [配置文件](docs/configuration.md)
- [IPC、HTTP 与插件](docs/ipc-and-plugins.md)
- [打包与验证](docs/packaging.md)
- [参与开发](CONTRIBUTING.md)
- [维护者发布流程](docs/releasing.md)

## 许可证

Orbit 使用 [Apache License 2.0](LICENSE)。
