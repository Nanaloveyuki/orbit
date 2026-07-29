# Orbit

Orbit is a MoonBit desktop application framework built around a replaceable
WebView runtime, embedded Web assets, and a constrained command/event IPC
boundary.

This repository contains the Stage 1 foundation packages, native desktop
composition, and initial developer tooling:

- `orbit-utils`: configuration, resources, platform and CSP utilities.
- `orbit-event`: standalone application and runtime event contracts.
- `orbit-ipc`: command registration, capability policies and structured invocation envelopes.
- `orbit-runtime`: replaceable WebView runtime contracts.
- `orbit-runtime-moonview`: native MoonView implementation of `orbit-runtime`.
- `orbit-core`: Orby window lifecycle and runtime composition.
- `orbit-build`: strict configuration and embedded-resource generator.
- `orbit-cli`: Node.js development wrapper for generator, build and run flows.

Multi-window policy, npm publication, plugin support and production packaging
remain deferred until the desktop lifecycle and configuration contracts are
stable.

## Current Boundaries

- `orbit-build` strictly parses and validates `orbit.conf.json`, emits a
  canonical configuration fingerprint, injects CSP into the HTML entry, and
  embeds its resource directory. It deliberately supports exactly one window
  while `orbit-core` remains single-window.
- `orbit-core` owns the Orby window and destroys the selected runtime before
  its parent window. `orbit-runtime` remains free of Orby and MoonView types;
  factories receive an abstract `RuntimeHost`.
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
their handler.

When IPC is configured, Orbit installs `window.__ORBIT__.invoke(command,
payload?, { timeout? })` before page scripts run. It returns a Promise, matches
responses by invocation ID, preserves a page's legacy `window.moonview.onmessage`
handler, and rejects non-serializable, oversized, timed-out or failed commands
with an `OrbitIpcError` containing `code`, `message` and optional `data`.
Requests are limited to 256 KiB and strictly parsed with duplicate-key
rejection before they reach command handlers.

An embedded resource provider confines navigation to its own
`<scheme>://app/` origin. MoonView accepts only same-origin GET or HEAD resource
requests, and `WebViewRuntime::navigate` returns a checked error for an external
target. External navigation policy is intentionally not configurable yet.

## CLI

`orbit-cli` is a zero-dependency Node.js development wrapper around the
MoonBit generator and application package. It does not parse configuration or
embed assets itself.

```sh
node orbit-cli/bin/orbit.mjs generate --config orbit-example/orbit.conf.json
node orbit-cli/bin/orbit.mjs build --config orbit-example/orbit.conf.json
node orbit-cli/bin/orbit.mjs dev --config orbit-example/orbit.conf.json
```

The default `orbit-build` package is resolved from the Moon workspace. Until
Orbit publishes that executable as a Mooncake dependency, use `--orbit-build`
when the generator lives outside the current workspace.

## Development

```sh
moon check --target all --deny-warn --warn-list +73
moon test --target all --deny-warn
moon fmt --check
moon info
```
