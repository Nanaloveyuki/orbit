# Platform Support

Orbit `0.1.0-alpha.7` is a pre-release desktop framework. Its public support
claim is deliberately narrower than its build matrix.

The proposed beta support contract is maintained in the
[platform standards](standards/platforms.md). This page describes current
support status; it does not promote experimental targets.

| Capability | Windows x64 | Linux x64 | macOS |
| --- | --- | --- | --- |
| Native window and embedded WebView | Supported | Experimental | Not supported |
| MoonBit IPC, embedded resources, plugins | Supported | Experimental | Not supported |
| CLI build and directory package | Supported | Experimental | Not supported |
| Native installers/packages | NSIS supported | archive, deb, rpm, Arch experimental | Not supported |
| File picker and handle-bound file bridge | Supported | Unavailable | Not supported |
| Native print dialog | Supported | Unavailable | Not supported |
| System tray | Supported | Unavailable | Not supported |
| Per-window WebView suspension | Supported | Experimental | Not supported |

"Supported" means the feature is covered by the maintained Windows native test
and release workflow, documented for application developers, and included in
the Windows GUI acceptance checklist. "Experimental" means it is continuously
compiled and package-tested but may lack feature parity or a stable support
commitment.

Linux uses GTK3 and WebKitGTK 4.1. Destroying a suspended WebView releases the
GTK child but does not promise reclamation of every WebKitGTK process-level
cache. macOS has no Orbit top-level window host.

The React memo reference app has been run through native build, production
WebView startup, Vite development startup, IPC availability, and clean process
shutdown on Ubuntu 22.04, Fedora 44, and Arch Linux under WSL2/WSLg. This is
implementation evidence for the experimental Linux target, not a promotion to
first-class support. Some WSLg Mesa/D3D12 combinations require WebKit software
compositing (`WEBKIT_DISABLE_COMPOSITING_MODE=1`,
`LIBGL_ALWAYS_SOFTWARE=1`, and `GALLIUM_DRIVER=llvmpipe`).

## Android Preview

Android is optional platform work and is not part of the desktop beta support
claim. `orbit-runtime-android` maps the common runtime contract to MoonView's
Ajni-backed Android WebView, while `orbit-android` owns Activity lifecycle and
IPC composition without importing Orby.

The React memo reference app has completed a dual-ABI debug APK build and its
Ajni/MoonView foundation has passed WebView, trusted-origin message, embedded
asset, lifecycle, and UTF-16 JNI instrumentation on an Android 16 arm64 device.
The Orbit application instrumentation additionally exercises page load and a
real `memo.runtime` IPC round trip when device-side test installation is
available. This evidence keeps Android at preview status; it does not imply
desktop feature parity.

Current Android scope is one Activity, one visible WebView, embedded resources,
page IPC, responsive bounds updates, WebView local storage, and APK output for
`arm64-v8a` and `x86_64`. Remote pages, multiple windows, Vite hot reload, native
file and print dialogs, tray integration, AAB/release signing, and Play delivery
are not implemented.

## Known Limits

- WebView suspension recreates the page; Orbit cannot synchronously capture
  arbitrary DOM state. Persist application state through IPC or browser storage
  before returning success from the suspension preparation callback.
- `runtime_suspend_handler` runs on the UI thread. It must perform bounded,
  non-blocking preparation and return an error rather than silently discarding
  state when persistence cannot complete.
- Tray support is an explicit `orbit-tray-windows` extension. It is not enabled
  by configuration alone and unavailable on non-Windows targets.
- Orbit does not provide auto-updates, crash-report collection, enterprise
  policy management, or a process-global WebView runtime shutdown contract.
- Lifecycle diagnostics are memory-only, opt-in, and intentionally contain only
  reviewed fixed fields. Applications own retention beyond `DiagnosticHistory`
  and any export or upload policy.
- Android applications require API 24 or newer and use a dedicated Gradle/NDK
  host. They do not run the desktop Orby event loop inside an Activity.
