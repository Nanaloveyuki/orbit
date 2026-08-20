# Changelog

This project follows semantic versioning after `1.0.0`. Before that milestone,
each prerelease may contain breaking API or configuration changes. Every release
notes those changes and the required application migration.

## Unreleased

## 0.1.0-alpha.7 - 2026-08-20

- Use the installer-supported `latest` channel, verified by CI to resolve to
  MoonBit `moonc` 0.10.9 for this release.
- Upgrade the desktop dependency line to `Nanaloveyuki/orby@0.1.0-beta.6`,
  `Nanaloveyuki/moonview@0.1.0-beta.9`, and `Nanaloveyuki/ajni@0.2.3`.
- Validate the dependency line through the native Orbit test suite and the
  Orbit CLI test and packaging checks.

## 0.1.0-alpha.6 - 2026-08-14

- Upgrade the Windows desktop host to `Nanaloveyuki/orby@0.1.0-beta.5` and
  explicitly handle external event-loop termination.
- Upgrade embedded WebView support to `Nanaloveyuki/moonview@0.1.0-beta.8`,
  including terminal browser-process failure handling.

## 0.1.0-alpha.5 - 2026-08-14

- Added application-controlled, versioned lifecycle support bundles that expose
  only reviewed diagnostic fields.
- The diagnose command can write the same explicit JSON environment report to
  stdout and a requested local file.

## 0.1.0-alpha.4 - 2026-08-11

- Added opt-in, bounded in-memory lifecycle diagnostics backed by BitLogger
  history, with fixed safe fields and no implicit persistence.
- `orbit diagnose --json` now emits a schema-versioned environment report while
  retaining the native MoonBit compilation check.
- `orbit init` now includes a Windows signed-release workflow, pinned MoonBit
  toolchain file, and application release checklist. The workflow requires a
  matching tag, a configured signing command, descriptor verification, and a
  valid Authenticode signature before publishing.

## 0.1.0-alpha.3 - 2026-08-11

- Declared Windows x64 as Orbit's first-class desktop target.
- Added the Windows tray, desktop extension lifecycle, and per-window WebView
  suspension to the public alpha release line.
- Made runtime suspension preparation fallible: state persistence can reject a
  suspend operation without destroying the active WebView.
- Added the `windows-lifecycle` lifecycle and tray reference implementation plus a
  Windows GUI acceptance checklist.

## Compatibility Policy

- `0.x` releases may remove or change public MoonBit APIs, CLI behavior, and
  configuration schemas.
- A release must document incompatible changes, migration steps, supported
  platforms, and validation performed.
- Beta releases will freeze the documented core API surface except for critical
  fixes and explicitly deprecated replacements.
