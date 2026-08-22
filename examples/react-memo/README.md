# Orbit React Memo

这是一个可独立管理和复制的 Orbit 桌面与 Android 应用示例，使用 MoonBit、React、TypeScript、
Vite、Tailwind CSS 4 和 shadcn/ui 实现完整的本地备忘录工作流。

## 功能

- 创建、编辑、删除和置顶备忘录；
- 全文搜索以及 Work、Personal、Ideas 分类筛选；
- 自动保存到 WebView `localStorage`，重启后恢复；
- 亮色、暗色主题，以及桌面三栏和窄窗口单栏布局；
- 通过 `memo.runtime` IPC 确认页面运行在 Orbit 原生宿主中；
- schema v2 配置、CSP、Vite 开发流程和生产资源嵌入。

## 环境

- MoonBit `0.10.9` 对应工具链；
- Node.js 20 或更高版本；
- pnpm 11；
- Windows x64 上的 MSVC、Windows SDK 和 WebView2 Runtime；
- Linux x64 上的 C 编译器、GTK3 和 WebKitGTK 4.1 开发包。
- Android 需要 JDK 17、Android SDK 35、Build Tools 36.1.0、NDK
  `29.0.14206865` 和 CMake 4.1.2。

Ubuntu/Debian 可安装 `libgtk-3-dev` 与 `libwebkit2gtk-4.1-dev`；Fedora
对应 `gtk3-devel` 与 `webkit2gtk4.1-devel`；Arch 对应 `gtk3` 与
`webkit2gtk-4.1`。

## 运行

从本目录执行：

```sh
moon update
pnpm install
pnpm run orbit dev
```

`pnpm run orbit dev` 启动 Vite 开发服务器和 Orbit 窗口。生产资源嵌入并运行：

```sh
pnpm run orbit run
```

常用验证命令：

```sh
pnpm check
pnpm run orbit build
moon check --target native --deny-warn
pnpm run orbit diagnose --json
```

也保留了 `pnpm orbit:dev`、`pnpm orbit:run` 和 `pnpm orbit:build` 这些快捷别名。

### WSLg

本示例已在 Ubuntu 22.04、Fedora 44 和 Arch Linux 的 WSL2/WSLg 环境中完成
`pnpm check`、`pnpm run orbit build`、`pnpm run orbit run` 和
`pnpm run orbit dev` 实测。部分 Mesa/D3D12 组合会输出 EGL/Zink 警告；遇到窗口无法
创建时可临时切换到软件合成：

```sh
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
pnpm run orbit dev
```

这些变量是 WSLg 图形栈的兼容设置，不是普通 Linux 桌面的默认要求。

### Android

Android 使用独立 Activity host，不经过桌面 Orby 窗口层。生产 React bundle、CSP、
嵌入资源和配置生成的 IPC policy 与桌面入口共用，并保持相同的 `memo.runtime` 命令契约；
MoonView Android 和 Ajni 负责系统 WebView、可信 HTTPS origin、WebMessage 与 Activity 生命周期。

Windows PowerShell 示例：

```powershell
$env:ANDROID_SDK_ROOT = "$env:LOCALAPPDATA\Android\Sdk"
$env:ANDROID_NDK_HOME = "C:\path\to\android-ndk-r29"
pnpm run orbit android build
pnpm run orbit android dev
pnpm run orbit android test
```

`android build` 生成调试 APK；`android dev` 重新构建前端和 APK，安装到唯一连接的 ADB
设备并启动；`android test` 还会安装测试 APK，并验证 React 页面加载和 `memo.runtime` IPC
往返。连接多个设备时显式选择：

```sh
pnpm run orbit android dev --device <adb-serial>
```

APK 位于 `android/app/build/outputs/apk/debug/app-debug.apk`。首次构建会下载 Gradle 依赖并
为 `arm64-v8a`、`x86_64` 编译 MoonBit 生成 C，后续增量构建会复用产物。若本机已安装
Gradle 且暂时无法下载 wrapper，可设置 `ORBIT_GRADLE=gradle`。

当前 Android preview 是单 Activity、单 WebView、嵌入资源模式。它不提供 Vite 热更新、
远程页面、多窗口、文件对话框、打印或托盘。`dev` 表示构建、安装和启动循环，不是桌面
`orbit dev` 的热更新服务器模式。

## 独立项目边界

本目录有自己的 `moon.mod`、`.moon-version`、`package.json` 和 `pnpm-lock.yaml`；`android/`
另有独立的 `moon.mod`，因此桌面构建不会解析 Android host 包。
`scripts/orbit-tool.mjs` 在当前 monorepo 中优先使用本地 `orbit-build`，复制到其他位置后
自动使用 `@nanaloveyuki/orbit-cli`。Android 构建在 monorepo 中会临时创建相对路径
`moon.work` 以验证未发布的本地 Orbit 包，并在命令退出时删除；不会写入本机绝对路径。

当前 React bundle 依赖本仓库新增的大资源分块生成逻辑。包含该修复的 Orbit 版本发布前，
建议先把示例保留在主仓库；发布后再复制出去独立维护，并同步更新 `moon.mod` 与 CLI 版本。

根 `package.json` 有意不设置 `type: module`。Mooncakes 依赖中的 MoonView prebuild 是
CommonJS；Node 会沿父目录查找该字段，把它设为 `module` 会导致原生依赖安装失败。Vite
配置使用显式 ESM 的 `vite.config.mts`，不会影响 React 源码。

## 目录结构

```text
src/components/ui/       shadcn/ui 生成的基础组件
src/features/memos/      备忘录状态、持久化和工作区界面
android/                 MoonBit Android 入口、Gradle/NDK host 和 instrumentation
main.mbt                 MoonBit IPC 和桌面应用入口
orbit.conf.json          Orbit 窗口、Vite、CSP 和 capability
generated_page.mbt       构建生成的嵌入资源，提交以便审查
```
