[简体中文](./docs/README-cn.md) | English

# Orbit

<p align="center">
  <img src="docs/assets/orbit-logo.svg" alt="Orbit logo" width="160">
</p>

[![validation](https://github.com/Nanaloveyuki/orbit/actions/workflows/validation.yml/badge.svg)](https://github.com/Nanaloveyuki/orbit/actions/workflows/validation.yml)
[![npm](https://img.shields.io/npm/v/%40nanaloveyuki%2Forbit-cli?tag=alpha&label=orbit-cli)](https://www.npmjs.com/package/@nanaloveyuki/orbit-cli)

Orbit is a MoonBit-based desktop application framework. It combines native
windows and event loops, an embedded system WebView, and capability-controlled
IPC between a web frontend and a MoonBit backend.

Orbit does not require a specific frontend framework. A static HTML/CSS/
JavaScript application, React, Vue, and other Vite-based frontends can all be
embedded.

## Support

- Windows x64 is the primary target.
- Linux x64 is experimental and requires GTK3 and WebKitGTK 4.1.
- macOS does not currently have an Orbit top-level window host.
- Android is an optional preview host with a separate Activity/WebView runtime.

## Prerequisites

- [MoonBit](https://www.moonbitlang.com/download/)
- A native C/C++ compiler and linker
- Node.js 20 or newer when using the CLI or Vite
- Windows: MSVC and the Windows SDK
- Windows runtime: the Microsoft Edge WebView2 Evergreen Runtime when running
  the example directly with `moon run`
- Linux: `pkg-config`, GTK3, and WebKitGTK 4.1 development packages

On Ubuntu or Debian, install the Linux WebView dependencies with:

```sh
sudo apt-get install build-essential pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev
```

Headless Linux validation additionally needs `xvfb`; an interactive desktop run
does not.

On Windows, the first native build downloads and verifies the WebView2 SDK.
Set `MOONVIEW_WEBVIEW2_SDK_DIR`, or both
`MOONVIEW_WEBVIEW2_INCLUDE` and `MOONVIEW_WEBVIEW2_LOADER_LIB`, for an offline
or preinstalled SDK. The direct `moon run` example uses the installed Evergreen
Runtime; packaged Windows installers can bootstrap it according to
`bundle.windows.webview_install_mode`.

## Run the repository example

```sh
git clone https://github.com/Nanaloveyuki/orbit.git
cd orbit
moon update
moon run orbit-example
```

The example opens a native window and serves an embedded WebView page. The
page invokes `example.ping` and receives a JSON response from MoonBit.

## Create an application

Use the CLI to create a new application without overwriting an existing path:

```sh
npx @nanaloveyuki/orbit-cli@alpha init my-orbit-app --name "My Orbit App" --identifier com.example.my-orbit-app --module example/my-orbit-app
cd my-orbit-app
moon update
npm install
npm run orbit:run
```

The generated application includes a native MoonBit entry point, a schema v2
configuration, embedded frontend resources, capability-protected IPC, and the
scripts needed for development and production builds.

## Add Orbit to an existing app

```sh
moon add Nanaloveyuki/orbit@0.1.0-alpha.7
npm install --save-dev @nanaloveyuki/orbit-cli@alpha
npx orbit generate
npx orbit dev
```

The CLI reads build and development commands from `orbit.conf.json`. It does
not guess the frontend framework, package manager, development URL, or output
directory.

## Edit an application

1. Edit frontend files under the configured `assets/` directory or the
   frontend source directory used by Vite.
2. Register MoonBit commands in a `CommandRegistry`.
3. Grant those commands to the intended page or window in `ipc_policy`.
4. Regenerate embedded resources after changing a non-Vite `assets/` directory.
5. Run the application again and verify the IPC path.

For the repository example:

```sh
moon run --target native orbit-build orbit-example/orbit.conf.json orbit-example/generated_page.mbt
moon run orbit-example
```

The generated `generated_page.mbt` and `orbit-bindings.mjs` files describe the
current embedded inputs. Review their diff when configuration or permissions
change.

### Register and call IPC

MoonBit backend:

```moonbit
let registry = @ipc.CommandRegistry::new()
registry.register_json(@ipc.CommandName::new("example.ping"), _payload => {
  Ok({ "message": "IPC round trip completed." })
})
```

Browser frontend:

```javascript
const response = await window.__ORBIT__.invoke("example.ping", { value: 1 }, {
  timeout: 5000,
});
```

Commands are available only when the application policy grants them to the
calling page. Keep filesystem, HTTP, plugin, and remote-page capabilities
explicitly scoped.

## Troubleshooting

### `moon update` or dependency download fails

Check the MoonBit version in `.moon-version`, confirm network access, and retry
with a clean project-level dependency state. Do not edit generated dependency
files by hand.

### Windows native build cannot find WebView2

For native build failures, install the Windows SDK and allow MoonView to
download its pinned WebView2 SDK, or set `MOONVIEW_WEBVIEW2_SDK_DIR`. If using
separate paths, set both `MOONVIEW_WEBVIEW2_INCLUDE` and
`MOONVIEW_WEBVIEW2_LOADER_LIB`. For runtime failures, install the Microsoft
Edge WebView2 Evergreen Runtime.

### Linux cannot create a WebView

Install a native C/C++ toolchain, `pkg-config`, GTK3, and WebKitGTK 4.1
development packages. For headless validation, also install `xvfb`. For a Vite
application, run the frontend build separately and confirm that `dist_dir`
matches the directory in `orbit.conf.json`.

### Frontend changes are not visible

Development mode loads the configured Vite `dev_url`. Embedded production mode
loads generated resources, so rerun `orbit generate` or `orbit-build` after
changing the source assets.

### An IPC call is denied or times out

Check the command name, the page origin, the principal in `ipc_policy`, and the
configured timeout. Use `npx orbit diagnose --json` to inspect the local host
and build environment without exporting IPC payloads.

## Documentation

- [Documentation index](docs/README.md)
- [Getting started](docs/getting-started.md)
- [Configuration](docs/configuration.md)
- [IPC and plugins](docs/ipc-and-plugins.md)
- [Platform support](docs/platform-support.md)
- [Diagnostics](docs/diagnostics.md)
- [Packaging](docs/packaging.md)
- [Runnable examples](examples/)

## License

Orbit is licensed under the [Apache License 2.0](LICENSE).
