# Package Status

> **Status: Reference only.** This matrix is the proposed package boundary for
> `0.1.0-beta.1`; it is not a declaration that the current packages have already
> completed their stability review.

## Stability levels

| Level | Meaning | Compatibility promise |
| --- | --- | --- |
| Core candidate | Intended for the first beta core | Public API is expected to freeze after the beta boundary is accepted |
| Experimental | Available for evaluation but still changing | No beta compatibility promise; changes require release notes |
| Test/support | Repository infrastructure, not an application API | May change with the tests or release process |
| Out of scope | Not part of the Orbit beta target | No Orbit beta support claim |

## Core candidate

| Package | Responsibility | Beta boundary |
| --- | --- | --- |
| `orbit-utils` | schema v2 configuration, resources, CSP, platform helpers | Core configuration and resource behavior |
| `orbit-event` | application and runtime event contract | Event names, envelopes, and delivery semantics |
| `orbit-ipc` | wire protocol, registry, principals, capabilities | IPC request/response and authorization semantics |
| `orbit-ipc-async` | deadlines, cancellation, and async execution support | Cancellation and completion behavior used by core transports |
| `orbit-ipc-moonview` | MoonView page transport adapter | Page message mapping used by the core WebView path |
| `orbit-runtime` | implementation-independent runtime contract | Runtime factory, bounds, navigation, messages, and teardown |
| `orbit-runtime-moonview` | MoonView runtime implementation | Windows-first WebView behavior and error mapping |
| `orbit-core` | Orby window lifecycle and composition | Startup, window lifecycle, async entry, and core errors |
| `orbit-build` | strict config, embedded resources, bindings, metadata | Generated application inputs and compatibility metadata |
| `orbit-cli` | development, build, package, and verification commands | Command contract, machine-readable metadata, and package checks |

The core candidate depends on published Orby and MoonView releases, but Orbit
must pin compatible versions and document any upstream behavior that is visible
through the Orbit core contract.

## Experimental extensions

| Package or area | Current role | Required status wording |
| --- | --- | --- |
| `orbit-plugin` / `orbit-plugin-abi` | dynamic libraries, sidecars, ABI v1/v2 | Experimental plugin API; ABI changes require explicit compatibility notes |
| `orbit-ipc-http` | optional authenticated HTTP transport | Experimental transport; host owns listener, TLS, and shutdown policy |
| `orbit-tray` / `orbit-tray-windows` | pure tray model and Windows tray host | Experimental extension; Windows-only native support |
| `orbit-desktop-file` / `orbit-file` | picker and opaque-handle file operations | Experimental extension; no path exposure guarantee may be weakened |
| `orbit-diagnostics` | bounded lifecycle diagnostics and support bundles | Experimental, opt-in, memory-only support surface |

These extensions may be shipped and used by applications. They are not allowed
to force a breaking change in the core candidate without a separate compatibility
decision.

## Test and platform support

- `orbit-example` is a reference application, not a stable library package.
- `orbit-plugin-fixtures` is integration-test infrastructure, not an extension
  API.
- AJNI is an optional Android dependency. It is not an Orbit core package and is
  not a beta blocker for the Windows-first target.
- `orbit-runtime-android` and `orbit-android` are optional Android preview
  packages. They reuse the runtime and IPC contracts but do not expand the
  desktop beta compatibility promise.
- Linux and macOS status follows the platform standard once that document is
  added; the package being compilable on a target does not make the target
  supported.

## Promotion rule

An experimental package MAY be promoted only after its public API, failure model,
platform claim, compatibility policy, focused tests, and migration documentation
have been reviewed as one unit. Passing native tests alone is insufficient for
promotion.
