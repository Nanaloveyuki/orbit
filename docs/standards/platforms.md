# Platform Standards

> **Status: Reference only.** These support claims are proposed for the first
> Orbit beta and do not promote a buildable target to supported status by
> themselves.

## Support levels

| Level | Meaning |
| --- | --- |
| First-class | Maintained native path, documented prerequisites, CI coverage, package validation, and an internal GUI smoke path |
| Experimental | Continuously compiled and package-tested, but feature parity or stable compatibility is not promised |
| Unsupported | No Orbit top-level support claim; an individual dependency may still build independently |
| Optional platform work | Separate package or plugin path that is not part of the Orbit desktop beta |

## Beta target

Windows x64 is the first-class target for `0.1.0-beta.1`.

The Windows contract assumes:

- Windows 10 22H2 x64 or Windows 11 x64;
- MSVC or a compatible native toolchain for development;
- the Microsoft Evergreen WebView2 Runtime on the target machine;
- MoonView WebView2 SDK preparation during native builds;
- Orby as the native window and event-loop host;
- documented behavior for window lifecycle, embedded resources, IPC, and the
  CLI/package flow.

Windows support MUST include explicit unavailable behavior for features that are
not enabled by the application, target, or optional extension. A successful build
alone is not a support claim.

## Linux

Linux x64 remains experimental. The repository may compile, run plugin fixtures,
and build deb/rpm/Arch/archive artifacts, but Linux beta documentation MUST NOT
claim Windows feature parity. In particular, unsupported file dialogs, print,
tray, or WebView behavior MUST remain visible as unavailable or experimental.

Linux support MAY be promoted independently after a platform-specific review of
native lifecycle, WebKitGTK process behavior, package installation, and GUI
acceptance. That promotion is not required for the Windows-first Orbit beta.

## macOS

macOS is unsupported by the Orbit top-level host until a native window host,
WebView runtime adapter, lifecycle integration, package flow, and acceptance path
exist. A dependency or low-level adapter being portable does not change this
claim.

## Android and OpenHarmony

Android and OpenHarmony are optional platform work. AJNI and related native
infrastructure MAY be distributed as optional subpackages or plugins, but they
MUST NOT be included in the Orbit desktop beta core promise. Their lifecycle,
packaging, emulator/device validation, and compatibility policy belong to separate
standards and releases.

## Platform change rule

A platform status change MUST update the support matrix, prerequisites, known
limits, CI jobs, packaging documentation, and acceptance checklist together. It
MUST NOT be inferred from a successful compilation on one runner.
