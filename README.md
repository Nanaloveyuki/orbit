# Orbit

Orbit is a MoonBit desktop application framework built around a replaceable
WebView runtime, embedded or explicitly allowlisted HTTPS Web assets, and a
constrained command/event IPC boundary.

This repository contains the Stage 1 foundation packages, native desktop
composition, and initial developer tooling:

- `orbit-utils`: schema-v2 configuration, explicit v1 migration, resources, platform and CSP utilities.
- `orbit-event`: standalone application and runtime event contracts.
- `orbit-ipc`: transport-neutral command registration, principal-scoped capability policies and structured invocation envelopes.
- `orbit-runtime`: replaceable WebView runtime contracts.
- `orbit-runtime-moonview`: native MoonView implementation of `orbit-runtime`.
- `orbit-core`: Orby window lifecycle and runtime composition.
- `orbit-build`: strict configuration and embedded-resource generator.
- `orbit-cli`: Node.js development wrapper for generator, build and run flows.

Plugin loading and single-window production packaging are available. Multi-window
resource roots, plugin isolation/signing, external navigation and broader native
capabilities remain intentionally deferred.

## Current Boundaries

- `orbit-build` strictly parses and validates schema-version 2
  `orbit.conf.json`, emits a canonical configuration fingerprint, injects CSP
  from `web.embedded` into the HTML entry or remote fallback, and embeds the
  required resource directory.
  Application metadata and windows live below `app`; package assets and Windows
  installer settings live below `bundle`; explicit optional Vite commands live
  below `build.vite`.
- `orbit-core` owns the Orby window and destroys the selected runtime before
  its parent window. `orbit-runtime` remains free of Orby and MoonView types;
  factories receive an abstract `RuntimeHost`.
- Native plugins use only `orbit-plugin-abi` v1. Each configuration entry
  declares an ID, bundled `plugins/` relative library and sidecar-manifest
  paths, and explicit permission grants. Sidecars use `schema_version: 2`,
  declare ABI version, identity, supported platforms, requested permissions,
  command names, and request/response JSON Schema objects. `orbit-build`
  strictly validates and embeds the sidecar descriptor without loading native
  code. Before creating an instance, Orbit compares that descriptor with the
  ABI v1 manifest reported by the loaded library. A sidecar request never
  grants itself a permission: configuration grants must cover every requested
  permission. Orbit maps validated commands to `plugin:<plugin-id>/<command>`
  and destroys every instance before closing its dynamic library.
- A development plugin root is an explicit runtime option (`--plugin-dir` in
  `orbit-cli`, exposed as `ORBIT_PLUGIN_DIRECTORY`) and is never written into
  `orbit.conf.json`, generated source, or the configuration fingerprint.
- MoonView, Orby, AJNI, sync, and Parsec are exact Mooncake dependencies. No
  source package uses a local path or unpinned Git dependency.
- CSP injection targets framework-controlled application shells containing a
  normal `<head>` element. It is not a general HTML parser. The evaluated
  `moonbit-community/html@0.1.2` parser does not expose the external DOM
  mutation needed for meta insertion and would add unrelated dependencies.
- `Nanaloveyuki/parsec/json` supplies strict JSON parsing with duplicate-key
  rejection before the configuration reaches the ordinary JSON decoder.

## Native Prerequisites

MoonView uses the host platform's WebView SDK. On Windows, set
`MOONVIEW_WEBVIEW2_SDK_DIR` to a WebView2 SDK root, or set both
`MOONVIEW_WEBVIEW2_INCLUDE` and `MOONVIEW_WEBVIEW2_LOADER_LIB`. Linux requires
the WebKitGTK 4.1 development package. These are build-host prerequisites, not
runtime package paths recorded by Orbit.

## Example

Generate the example's embedded resources after changing a file below
`orbit-example/assets`, then open them through Orbit's `orbit://` protocol in an
Orby-owned MoonView window:

```sh
moon run --target native orbit-build orbit-example/orbit.conf.json orbit-example/generated_page.mbt
moon run orbit-example
```

Run the commands from the repository root. `orbit-example` consumes generated
source and does not read HTML, CSS, JavaScript, images, or fonts at runtime.
The generator recursively embeds regular files below the configured entry
file's directory, rejects symbolic links, and produces a deterministic
`orbit://app/<path>` resource table. Asset MIME detection currently covers common web formats;
unrecognized files use `application/octet-stream`. It strictly rejects
duplicate JSON keys, validates the complete Orbit schema, embeds its canonical
configuration and fingerprint, and injects the configured CSP into the HTML
entry document. The current desktop generator requires exactly one configured
window and applies its title, dimensions, visibility and resizable setting.
The example button dispatches `example.ping` through
`orbit-ipc` and displays the returned JSON response. Its `capabilities`
configuration grants that command only to the `main` window. The generator
emits `configured_ipc_policy`; pass it to `DesktopOptions` alongside the
command registry. An IPC registry without a policy is rejected, and commands
not granted to the current window return `permission_denied` without invoking
their handler. Internally, each invocation carries a typed principal and
transport context; `dispatch_for_window` remains the protocol-v1 compatibility
wrapper while future HTTP, plugin and background adapters use
`dispatch_with_context`. New principal grants support exact origin and
transport scopes, and a matching deny grant overrides every allow grant.

When IPC is configured, Orbit installs `window.__ORBIT__.invoke(command,
payload?, { timeout? })` before page scripts run. It returns a Promise, matches
responses by invocation ID, preserves a page's legacy `window.moonview.onmessage`
handler, and rejects non-serializable, oversized, timed-out or failed commands
with an `OrbitIpcError` containing `code`, `message` and optional `data`.
Requests are limited to 256 KiB and strictly parsed with duplicate-key
rejection before they reach command handlers.

An embedded resource provider confines navigation to its own
`<scheme>://app/` origin. MoonView accepts only same-origin GET or HEAD resource
requests. External navigation is denied by default. Applications can replace
`RuntimeOptions`' external navigation handler to display a permission prompt
and approve an individual URL; the handler is never used for embedded-origin
navigation.

`web.remote` is an explicit production HTTPS mode. It retains
`web.embedded.csp` and an embedded `fallback_entry`, then declares the initial
`http_url` and exact HTTPS `allowed_origins`:

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

The initial URL origin must appear in `allowed_origins`; HTTP URLs, wildcard
origins, duplicate origins and Vite workflows are rejected. Allowed remote
navigations stay in the WebView. Failed or rejected remote navigations load
the embedded fallback; URLs outside the allowlist still require the host's
external-navigation callback. Remote pages use the separate `remote_page`
principal and receive no desktop IPC by default. A remote command grant must
name that principal, scope `moonview`, and include an exact allowlisted HTTPS
origin scope. The injected bridge is top-level-only, so an iframe cannot use
the host IPC channel.

## CLI

`orbit-cli` is a zero-dependency Node.js development wrapper around the
MoonBit generator and application package. It does not parse configuration or
embed assets itself.

```sh
node orbit-cli/bin/orbit.mjs generate --config orbit-example/orbit.conf.json
node orbit-cli/bin/orbit.mjs bindings --config orbit-example/orbit.conf.json
node orbit-cli/bin/orbit.mjs migrate-config --config old-orbit.conf.json --output orbit.conf.json
node orbit-cli/bin/orbit.mjs icon --source assets/icon-1024.png --out-dir icons --compression 6
node orbit-cli/bin/orbit.mjs build --config orbit-example/orbit.conf.json
node orbit-cli/bin/orbit.mjs dev --config orbit-example/orbit.conf.json
node orbit-cli/bin/orbit diagnose --config orbit-example/orbit.conf.json --json
node orbit-cli/bin/orbit package --config orbit-example/orbit.conf.json --out-dir dist
node orbit-cli/bin/orbit verify-package --package-dir dist
node orbit-cli/bin/orbit installer --package-dir dist --allow-unsigned
node orbit-cli/bin/orbit installer --package-dir dist --webview2-bootstrapper path/to/MicrosoftEdgeWebview2Setup.exe --sign-command "sign-tool {installer} {package_dir} {package_manifest}"
node orbit-cli/bin/orbit verify-installer --installer dist/dev.orbit.example-0.1.0-setup.exe
```

`orbit-cli` is the npm-published boundary: its package contains only the Node
wrapper. `package` generates and builds first, then discovers the unique Moon
native launch artifact under `_build/native/debug/build/`. `--binary` remains
an explicit override. It copies the application `plugins/` directory and
optional `--runtime-dir` into the output. `orbit-package.json` records the
application identity, configuration fingerprint, host platform and
architecture, Orbit, MoonView, and fixed plugin-ABI compatibility values. The
generated Web assets remain embedded in the executable. The same manifest
contains a deterministic SHA-256 inventory of every packaged payload file;
`orbit verify-package` rejects missing, modified and undeclared files before
an installer or updater consumes the directory.

`orbit installer` produces a Windows NSIS installer for the current user. On
first use it downloads Tauri's pinned NSIS 3.11 archive, verifies its SHA-1
and SHA-256,
and caches it under `~/.orbit/tools/windows/`; it also downloads and caches the
Microsoft Evergreen WebView2 bootstrapper. `--makensis` and
`--webview2-bootstrapper` remain explicit offline overrides. Production
invocations must supply a `--sign-command`; it receives quoted `{installer}`,
`{package_dir}` and `{package_manifest}` paths. `--allow-unsigned` is an
explicit local-development opt-out. The installer rejects `--runtime-dir`
payloads because MoonView uses the system Evergreen runtime rather than a
fixed copied runtime.

`bundle.windows.webview_install_mode` controls how the installer handles that
Evergreen runtime. It is optional and defaults to `embed_bootstrapper` for
backward-compatible packages:

```json
{
  "bundle": {
    "icons": [],
    "windows": { "webview_install_mode": "embed_bootstrapper" }
  }
}
```

- `embed_bootstrapper`: downloads the small Microsoft bootstrapper while
  building the installer, then embeds it. The target machine still needs
  network access when the bootstrapper runs.
- `download_bootstrapper`: keeps the installer small and downloads the
  bootstrapper during installation through NSIS over HTTPS.
- `offline_installer`: downloads and embeds Microsoft's x64 offline Evergreen
  installer while building the installer. This is substantially larger, but
  installation itself does not need network access.
- `skip`: packages no WebView2 installer action; use only where Evergreen
  WebView2 is managed by the deployment environment.

`fixed_runtime` is intentionally unsupported: MoonView currently locates the
system Evergreen runtime through its WebView2 loader and has no fixed-runtime
path API. `--webview2-bootstrapper` remains an explicit local payload override
for `embed_bootstrapper` and `offline_installer`.

The default `orbit-build` package is resolved from the Moon workspace. Until
Orbit publishes that executable as a Mooncake dependency, use `--orbit-build`
when the generator lives outside the current workspace.

Normal Orbit tooling accepts only `schema_version: 2`. To move an existing v1
file forward, `migrate-config` requires an explicit `--output` path, rejects an
existing output and never overwrites its input. The migration maps v1 window
capabilities to explicit `allow` grants with `window` principals. It cannot
infer optional publisher metadata, icon declarations or Vite commands; those
remain absent until the application author supplies them.

When `build.vite` is declared, its commands are executed literally from the
configuration directory. `orbit dev` starts `dev_command`, waits for
`dev_url`, generates a page that loads that exact URL, and stops the Vite
process tree when the desktop application exits. `orbit build`, `orbit run`
and `orbit package` run `build_command` first, then embed resources from
`dist_dir`. The CLI does not infer package managers, framework names, scripts
or output paths. `dev_url` must be an HTTP(S) URL without a trailing slash;
only that URL and descendants are approved for development navigation.

`orbit icon` consumes one required 1024x1024 PNG and writes deterministic
`16x16.png` through `1024x1024.png`, `icon.ico`, `icon.icns`, and `icon.svg`.
The SVG is a PNG data-URI wrapper, not an attempted vector conversion. The
command accepts `--compression 0..9`; source decoding is bounded and output
generation uses premultiplied-alpha Lanczos3 resizing through
`Nanaloveyuki/image`.

`orbit bindings` emits a deterministic `orbit-bindings.mjs` module beside the
configuration. It exports the exact page-callable command map from `allow`
capabilities targeting a local window or explicitly scoped remote page,
including explicitly granted plugin command namespaces. Commands limited to
HTTP, plugins or background tasks are not emitted, and a matching page-level
deny removes a command from the map.
The generated module is a client convenience only; the IPC policy remains the
authority at runtime.

## Development

```sh
moon check --target all --deny-warn --warn-list +73
moon test --target all --deny-warn
moon fmt --check
moon info
```

## Plugin Fixture Integration

The native plugin integration fixture compiles a small ABI v1 DLL and loads it
through the published `dynlib` and `orbit-plugin-abi` packages. It verifies
explicit permission denial, duplicate identifiers, JSON command dispatch,
plugin command failures, and that instance destruction occurs before DLL
unload.

```powershell
./orbit-plugin-fixtures/run-integration.ps1
```

The script uses `cl.exe` when the Visual Studio developer tools are active and
otherwise falls back to `clang.exe`. The compiled DLL and teardown log are
ignored build artifacts.
