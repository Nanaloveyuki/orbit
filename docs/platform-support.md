# Platform Support

Orbit `0.1.0-alpha.3` is a pre-release desktop framework. Its public support
claim is deliberately narrower than its build matrix.

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
