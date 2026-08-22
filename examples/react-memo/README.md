# Orbit React Memo

这是一个可独立管理和复制的 Orbit 桌面应用示例，使用 MoonBit、React、TypeScript、
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
- Windows x64 上的 MSVC、Windows SDK 和 WebView2 Runtime。

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

## 独立项目边界

本目录有自己的 `moon.mod`、`.moon-version`、`package.json` 和 `pnpm-lock.yaml`。
`scripts/orbit-tool.mjs` 在当前 monorepo 中优先使用本地 `orbit-build`，复制到其他位置后
自动使用 `@nanaloveyuki/orbit-cli`。

当前 React bundle 依赖本仓库新增的大资源分块生成逻辑。包含该修复的 Orbit 版本发布前，
建议先把示例保留在主仓库；发布后再复制出去独立维护，并同步更新 `moon.mod` 与 CLI 版本。

根 `package.json` 有意不设置 `type: module`。Mooncakes 依赖中的 MoonView prebuild 是
CommonJS；Node 会沿父目录查找该字段，把它设为 `module` 会导致原生依赖安装失败。Vite
配置使用显式 ESM 的 `vite.config.mts`，不会影响 React 源码。

## 目录结构

```text
src/components/ui/       shadcn/ui 生成的基础组件
src/features/memos/      备忘录状态、持久化和工作区界面
main.mbt                 MoonBit IPC 和桌面应用入口
orbit.conf.json          Orbit 窗口、Vite、CSP 和 capability
generated_page.mbt       构建生成的嵌入资源，提交以便审查
```
