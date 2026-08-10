# Orbit 打包

Orbit CLI 先生成资源并编译应用，再从 Moon native build 输出创建可校验的目录包。安装
程序、archive 和发行版原生包都必须以通过校验的目录包为输入。

## 目录包

```sh
npx orbit package \
  --orbit-build .mooncakes/Nanaloveyuki/orbit/orbit-build \
  --release \
  --out-dir dist
npx orbit verify-package --package-dir dist
```

分发产物必须使用 `--release`。`orbit-package.json` 记录应用身份、配置指纹、平台与架构、
Orbit/MoonView/plugin ABI 兼容上限，以及所有 payload 文件的 SHA-256 清单。
`verify-package` 会拒绝丢失、修改和未声明文件。

前端资源已经嵌入可执行文件。插件目录和显式 `--runtime-dir` 会复制到目录包中。

## Windows NSIS

本地无签名测试：

```sh
npx orbit installer --package-dir dist --allow-unsigned
npx orbit verify-installer --installer dist/dev.example.app-0.1.0-setup.exe
```

生产构建必须提供外部签名命令：

```sh
npx orbit installer \
  --package-dir dist \
  --sign-command "sign-tool {installer} {package_dir} {package_manifest}"
```

首次使用时，CLI 下载并校验固定的 NSIS 工具包，缓存到 `~/.orbit/tools/windows/`。
`--makensis` 可以指定离线编译器。

`bundle.windows.webview_install_mode` 控制目标机器的 Evergreen WebView2 Runtime：

| 值 | 行为 |
| --- | --- |
| `embed_bootstrapper` | 在构建时下载并嵌入小型 bootstrapper；安装时仍需网络，当前默认值 |
| `download_bootstrapper` | 安装时通过 HTTPS 下载 bootstrapper，安装包更小 |
| `offline_installer` | 构建时下载并嵌入 x64 offline installer，安装时无需网络 |
| `skip` | 不处理 WebView2，仅适合部署环境已统一管理 runtime |

MoonView 当前通过系统 Evergreen loader 定位 runtime，不支持 fixed runtime。Windows
installer 因此也拒绝 `--runtime-dir`。

## Linux archive

```sh
npx orbit archive --package-dir dist --out-dir artifacts --allow-unsigned
npx orbit verify-archive \
  --archive artifacts/dev.example.app-0.1.0-linux-x64.tar.gz
```

archive 是确定性的 `tar.gz`，根目录包含未经改变的 `orbit-package/` 和可执行 `run`
launcher。解压后仍可对内部目录运行 `verify-package`。

Linux archive 不捆绑 GTK3/WebKitGTK 4.1，也不安装 desktop entry。生产构建必须提供
detached `--sign-command`；相邻的 `*.orbit-archive.json` 记录最终 hash、兼容 profile 和
签名 hook 是否运行。

## Linux 原生包

```sh
npx orbit linux-package \
  --package-dir dist \
  --format deb \
  --out-dir artifacts \
  --allow-unsigned
npx orbit verify-linux-package \
  --artifact artifacts/example_0.1.0-1_amd64.deb
```

可选格式为 `deb`、`rpm` 和 `arch`。CLI 直接调用当前宿主的 `dpkg-deb`、`rpmbuild` 或
`makepkg`，不会自动进入 WSL 或容器；Arch 构建必须由非 root 用户执行。

配置需要显式发行版元数据：

```json
{
  "bundle": {
    "icons": ["icons/128x128.png", "icons/icon.svg"],
    "linux": {
      "package_name": "example",
      "summary": "Example desktop application",
      "description": "An application built with Orbit.",
      "license": "Apache-2.0",
      "homepage": "https://example.com",
      "maintainer": "Example Project <maintainer@example.com>",
      "category": "Utility",
      "deb": {
        "depends": ["libgtk-3-0", "libwebkit2gtk-4.1-0"],
        "section": "utils",
        "priority": "optional"
      },
      "rpm": { "requires": ["gtk3", "webkit2gtk4.1"] },
      "arch": { "depends": ["gtk3", "webkit2gtk-4.1"] }
    }
  }
}
```

每个格式只有在对应对象存在时才启用。原生包把目录包安装到
`/usr/lib/<application-identifier>`，并安装 launcher、desktop entry 和 hicolor 图标。

生产 native package 的签名 hook 可以修改 artifact 以附加格式内签名；Orbit 在 hook
之后计算最终 SHA-256。元数据只证明 hook 已运行，发布前仍要使用所选签名系统验证
信任链。

## 图标

```sh
npx orbit icon --source assets/icon-1024.png --out-dir icons --compression 6
```

输入必须是 1024x1024 PNG。命令生成 16 至 1024 像素 PNG、`icon.ico`、`icon.icns` 和
`icon.svg`。SVG 是 PNG data URI wrapper，不是位图到矢量的转换。压缩级别范围为 0-9。

框架本身的发布流程见 [`releasing.md`](releasing.md)。
