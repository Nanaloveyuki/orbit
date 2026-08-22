# 参与 Orbit 开发

本文面向修改 Orbit 框架、CLI、runtime adapter 和测试 fixture 的贡献者。应用开发请从
[`README.md`](README.md) 和[入门指南](docs/getting-started.md)开始。
beta 契约的参考标准见[标准文档](docs/standards/README.md)；在首个测试应用完成前，
这些标准不作为发布门禁。

## 开发环境

- MoonBit 工具链，版本入口由 [`.moon-version`](.moon-version) 记录；
- Node.js 20 或更高版本；
- 平台 native toolchain；
- Windows：MSVC/Windows SDK；MoonView 自动准备 WebView2 SDK；
- Linux：C compiler、GTK3、WebKitGTK 4.1、Xvfb；
- Android：JDK 17、Android SDK 35、Build Tools 36.1.0、NDK 29、CMake 4.1.2；
- 插件 fixture 在 Windows 使用 `cl.exe`，不可用时回退 `clang.exe`，Linux 使用 `cc`。

```sh
git clone https://github.com/Nanaloveyuki/orbit.git
cd orbit
moon update
npm install --prefix orbit-cli
```

## 仓库边界

| 目录 | 责任 |
| --- | --- |
| `orbit-utils` | schema v2 配置、迁移、资源、平台和 CSP 工具 |
| `orbit-event` | 应用与 runtime 事件契约 |
| `orbit-ipc` | 注册表、wire protocol、principal 和 capability policy |
| `orbit-ipc-async` | transport 共用的 deadline/cancellation 执行器 |
| `orbit-ipc-http` | 可选认证 HTTP adapter |
| `orbit-ipc-moonview` | MoonView 页面消息 adapter |
| `orbit-runtime` | 不依赖具体窗口/WebView 实现的 runtime contract |
| `orbit-runtime-moonview` | MoonView runtime 实现 |
| `orbit-runtime-android` | MoonView/Ajni Android WebView runtime 实现 |
| `orbit-android` | Android Activity 生命周期与 IPC 组合 |
| `orbit-plugin` | sidecar、动态库和 ABI v1/v2 runtime |
| `orbit-core` | Orby 窗口生命周期与整体组合 |
| `orbit-build` | 严格配置、嵌入资源、bindings 和元数据生成器 |
| `orbit-cli` | Node.js 开发与打包命令 |
| `orbit-example` | 可运行的端到端示例 |
| `orbit-plugin-fixtures` | 真实动态库集成测试 |

保持依赖方向：抽象包不能引入 Orby/MoonView 具体类型，配置和 IPC 核心不能依赖桌面
宿主。优先沿用已有包边界，不把平台细节泄漏到传输无关 API。

## 验证

提交前至少运行：

```sh
moon fmt --check
moon check --target native --deny-warn
moon test --target native --deny-warn
npm test --prefix orbit-cli
npm pack --dry-run ./orbit-cli
```

Windows 插件集成：

```powershell
./orbit-plugin-fixtures/run-integration.ps1
```

Linux 插件集成：

```sh
xvfb-run -a bash orbit-plugin-fixtures/run-integration.sh
```

修改 public MoonBit API 后运行 `moon info`，提交对应的 `pkg.generated.mbti`。不要手工编辑
生成接口。修改配置、打包或平台代码时，补充与风险对应的 focused test；跨模块契约变化
还需要相应的 integration fixture。

CI 在 Windows 和 Ubuntu 上运行 MoonBit/Node 验证，并在 Ubuntu、Fedora、Arch 环境
测试对应的 Linux package builder。

## 文件与生成物

- 仓库文本默认 LF；`.bat`/`.cmd` 使用 CRLF，规则由 `.gitattributes` 固定；
- 不提交 `_build/`、`.mooncakes/`、`tmp/`、`ref/` 或本地 fixture 动态库；
- `generated_page.mbt` 和 `orbit-bindings.mjs` 只有在其输入变化时更新；
- 不修改 vendored dependency 源码来掩盖上游问题；需要时升级已发布依赖。

## 提交流程

1. 从最新 `main` 创建单一目的分支；
2. 保持改动与测试范围一致；
3. 推送并向 `main` 创建 PR；
4. 等待全部 validation jobs 通过；
5. squash merge，并删除远端与本地功能分支。

PR 说明应写明行为变化、兼容影响和实际执行的验证。不要把发布 token、SDK、构建目录
或本地开发覆盖路径提交到仓库。

## 文档与发布

面向应用开发者的用法放在根 README 和 `docs/`；源码构建、测试、架构边界和提交规则放
在本文。配置或 CLI 行为变化必须同步更新相应用户文档。

只有维护者执行框架发布，具体过程见 [`docs/releasing.md`](docs/releasing.md)。
