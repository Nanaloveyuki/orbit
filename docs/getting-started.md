# Orbit 入门指南

本文面向应用开发者。框架源码的构建、测试和提交规则见
[`CONTRIBUTING.md`](../CONTRIBUTING.md)。

## 环境

所有平台都需要：

- MoonBit 工具链；
- 本机 C/C++ 编译和链接工具链；
- Node.js 20 或更高版本，仅在使用 Orbit CLI 或 Vite 时需要。

Windows 需要可用的 MSVC/Windows SDK。MoonView 会在第一次 native build 时下载官方
WebView2 SDK `1.0.4078.44`、校验固定 SHA-256，并缓存到
`%LOCALAPPDATA%\moonview\webview2\1.0.4078.44`。离线环境可以设置
`MOONVIEW_WEBVIEW2_SDK_DIR`，或同时设置 `MOONVIEW_WEBVIEW2_INCLUDE` 与
`MOONVIEW_WEBVIEW2_LOADER_LIB`。

Linux 需要 GTK3 和 WebKitGTK 4.1 开发包。Ubuntu/Debian 示例：

```sh
sudo apt-get install libgtk-3-dev libwebkit2gtk-4.1-dev
```

## 运行仓库示例

```sh
git clone https://github.com/Nanaloveyuki/orbit.git
cd orbit
moon update
moon run orbit-example
```

`orbit-example` 包含一个完整但尽量小的应用：

```text
orbit-example/
  assets/                 # HTML、CSS 和 JavaScript 源文件
  generated_page.mbt      # orbit-build 生成的嵌入资源和配置
  main.mbt                # MoonBit 命令注册与桌面入口
  moon.pkg                # 包依赖和 native executable 声明
  orbit-bindings.mjs      # 可选的页面 IPC bindings
  orbit.conf.json         # schema_version 2 应用配置
```

修改配置或 `assets/` 后重新生成并运行：

```sh
moon run --target native orbit-build orbit-example/orbit.conf.json orbit-example/generated_page.mbt
moon run orbit-example
```

生成器递归嵌入每个窗口入口文件所在目录中的普通文件，拒绝符号链接，并规范化文本换行。
运行时从 `orbit://app/` 提供这些资源，不读取源码目录。

## 创建应用

当前 alpha 版本没有脚手架命令。最直接的方式是复制 `orbit-example`，然后修改：

1. `orbit.conf.json` 中的应用标识、名称、版本和窗口；
2. `assets/` 或 Vite 前端目录；
3. `main.mbt` 中的命令注册；
4. `moon.pkg` 中的包名和 import。

在新 MoonBit 模块中安装发布版本：

```sh
moon add Nanaloveyuki/orbit@0.1.0-alpha.1
npm install --save-dev @nanaloveyuki/orbit-cli@alpha
```

外部模块中的生成器安装在 `.mooncakes` 下。现阶段需通过 `--orbit-build` 指出路径：

```sh
npx orbit generate \
  --orbit-build .mooncakes/Nanaloveyuki/orbit/orbit-build \
  --config orbit.conf.json
npx orbit run \
  --orbit-build .mooncakes/Nanaloveyuki/orbit/orbit-build \
  --config orbit.conf.json
```

配置、输出和应用包不在工作区根目录时，使用 `--config`、`--output`、`--package` 和
`--workspace` 显式指定。运行 `npx orbit --help` 查看完整参数。

## MoonBit 应用入口

应用至少需要命令注册表、由生成代码创建的能力策略、窗口配置和一个 runtime factory：

```moonbit
fn example_registry() -> @ipc.CommandRegistry raise @ipc.IpcError {
  let registry = @ipc.CommandRegistry::new()
  registry.register_json(@ipc.CommandName::new("example.ping"), _payload => {
    Ok({ "message": "IPC round trip completed." })
  })
  registry
}

fn main {
  let options = @core.DesktopOptions::new(
    windows=configured_windows(),
    ipc_registry=Some(example_registry()),
    ipc_policy=Some(configured_ipc_policy()),
    plugin_declarations=configured_plugins(),
  )
  let factory = @moonview_runtime.MoonViewRuntimeFactory::new()
    as &@runtime.RuntimeFactory
  ignore(@core.run(factory, options))
}
```

需要异步命令或 ABI v2 插件时使用 `@core.run_async`。它必须负责启动异步运行时，不能在
已经运行的 async runtime 内再次调用。

## 页面调用

Orbit 在页面脚本执行前注入 `window.__ORBIT__.invoke`：

```javascript
try {
  const result = await window.__ORBIT__.invoke(
    "example.ping",
    { value: 1 },
    { timeout: 5000 },
  );
  console.log(result);
} catch (error) {
  console.error(error.code, error.message, error.data);
}
```

也可以生成只包含页面实际获授权命令的 bindings：

```sh
npx orbit bindings --orbit-build .mooncakes/Nanaloveyuki/orbit/orbit-build
```

`orbit-bindings.mjs` 是调用便利层；运行时能力策略始终是最终权限依据。

## Vite 前端

React、Vue、Svelte 或普通 Vite 项目都使用同一配置：

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

开发时：

```sh
npx orbit dev --orbit-build .mooncakes/Nanaloveyuki/orbit/orbit-build
```

CLI 启动 `dev_command`、等待精确的 `dev_url`、运行桌面应用，并在应用退出后终止前端
进程树。构建和打包时，CLI 先运行 `build_command`，再从 `dist_dir` 嵌入资源。

Vite 模式与生产 `web.remote` 模式不能同时启用。

## 下一步

- 配置字段与权限声明：[`configuration.md`](configuration.md)
- IPC、HTTP 和插件：[`ipc-and-plugins.md`](ipc-and-plugins.md)
- 安装包和发布产物：[`packaging.md`](packaging.md)
