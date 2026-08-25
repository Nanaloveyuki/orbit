[English](../README.md)

# Orbit

Orbit 是一个基于 MoonBit 的桌面应用框架。它组合原生窗口和事件循环、系统 WebView，
以及网页前端与 MoonBit 后端之间受 capability 控制的 IPC。

Orbit 不绑定前端框架。静态 HTML/CSS/JavaScript、React、Vue 和其他 Vite 前端都可以嵌入。

## 支持范围

- Windows x64 是主要目标平台。
- Linux x64 为实验性支持，需要 GTK3 和 WebKitGTK 4.1。
- macOS 尚未实现 Orbit 顶层窗口宿主。
- Android 是可选 preview host，使用独立的 Activity/WebView runtime。

## 环境要求

- [MoonBit 工具链](https://www.moonbitlang.com/download/)
- 本机 C/C++ 编译和链接工具链
- 使用 CLI 或 Vite 时需要 Node.js 20 或更高版本
- Windows：MSVC 和 Windows SDK
- Windows 直接使用 `moon run` 运行示例时需要 Microsoft Edge WebView2
  Evergreen Runtime
- Linux：`pkg-config`、GTK3 和 WebKitGTK 4.1 开发包

Ubuntu 或 Debian 可以安装：

~~~sh
sudo apt-get install build-essential pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev
~~~

无头 Linux 验证还需要 `xvfb`；普通桌面运行不需要。

Windows 首次 native build 会下载并校验 WebView2 SDK。离线环境可以设置
`MOONVIEW_WEBVIEW2_SDK_DIR`，或者同时设置
`MOONVIEW_WEBVIEW2_INCLUDE` 和 `MOONVIEW_WEBVIEW2_LOADER_LIB`。
直接运行示例使用系统已安装的 Evergreen Runtime；Windows 安装器是否自动处理
Runtime 由 `bundle.windows.webview_install_mode` 决定。

## 运行仓库示例

~~~sh
git clone https://github.com/Nanaloveyuki/orbit.git
cd orbit
moon update
moon run orbit-example
~~~

示例会打开原生窗口并加载嵌入式 WebView 页面。页面调用 `example.ping`，
MoonBit 后端返回 JSON。

## 创建应用

CLI 可以创建一个不会覆盖已有目录的新应用：

~~~sh
npx @nanaloveyuki/orbit-cli@alpha init my-orbit-app --name "My Orbit App" --identifier com.example.my-orbit-app --module example/my-orbit-app
cd my-orbit-app
moon update
npm install
npm run orbit:run
~~~

生成的应用包含 MoonBit native 入口、schema v2 配置、嵌入式前端资源、
capability 保护的 IPC，以及开发和生产构建脚本。

## 接入已有应用

~~~sh
moon add Nanaloveyuki/orbit@0.1.0-alpha.8
npm install --save-dev @nanaloveyuki/orbit-cli@alpha
npx orbit generate
npx orbit dev
~~~

CLI 从 `orbit.conf.json` 读取构建和开发命令，不会猜测前端框架、包管理器、
开发 URL 或输出目录。

## 编辑应用

1. 修改 `assets/` 或 Vite 配置的前端源文件。
2. 在 MoonBit 中注册命令。
3. 在 `ipc_policy` 中把命令授予目标页面或窗口。
4. 修改非 Vite `assets/` 后重新生成嵌入资源。
5. 重新运行应用并验证 IPC 链路。

仓库示例的资源生成命令：

~~~sh
moon run --target native orbit-build orbit-example/orbit.conf.json orbit-example/generated_page.mbt
moon run orbit-example
~~~

`generated_page.mbt` 和 `orbit-bindings.mjs` 是由输入生成的文件。配置或权限变化时，
应检查它们的 diff。

## 故障处理

- `moon update` 失败：检查 `.moon-version`、网络和项目依赖状态，不要手工编辑生成的依赖文件。
- Windows native build 找不到 WebView2：安装 Windows SDK，或配置 WebView2
  SDK 环境变量；运行时不可用时安装 Microsoft Edge WebView2 Evergreen Runtime。
- Linux 无法创建 WebView：安装 C/C++ 编译工具链、`pkg-config`、GTK3 和
  WebKitGTK 4.1 开发包；无头验证还需要 `xvfb`。
- 前端修改未生效：开发模式检查 `dev_url`，嵌入式生产模式重新运行 `orbit generate` 或 `orbit-build`。
- IPC 被拒绝或超时：检查命令名、页面 origin、`ipc_policy` 中的 principal 和 timeout。
- 使用 `npx orbit diagnose --json` 查看本机 WebView 和构建环境。

## 更多文档

- [文档分类入口](README.md)
- [入门指南](getting-started.md)
- [配置](configuration.md)
- [IPC 与插件](ipc-and-plugins.md)
- [平台支持](platform-support.md)
- [Android WASI 集成](android-wasi.md)
- [诊断](diagnostics.md)
- [打包](packaging.md)
- [可运行示例](../examples/)

## 许可证

Orbit 使用 [Apache License 2.0](../LICENSE)。
