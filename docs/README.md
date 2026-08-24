# Orbit Documentation

This directory is organized by audience. Start with the user guides when building
an application. Use the maintainer and agent guides only when changing this
repository or its release process.

## User guides

- [English user guide](../README.md)
- [Simplified Chinese user guide](README-cn.md)
- [Getting started](getting-started.md)
- [Configuration](configuration.md)
- [IPC and plugins](ipc-and-plugins.md)
- [Diagnostics](diagnostics.md)
- [Platform support](platform-support.md)
- [Packaging an application](packaging.md)

## Reference

- [Beta API and compatibility standards](standards/api-compatibility.md)
- [Package status](standards/package-status.md)
- [Runtime lifecycle](standards/runtime-lifecycle.md)
- [IPC and security](standards/ipc-security.md)
- [Native FFI](standards/native-ffi.md)
- [Extensions](standards/extensions.md)
- [Platform contract](standards/platforms.md)
- [Release and validation standard](standards/release-and-validation.md)

The standards are reference material for maintainers and package authors. They
are not a substitute for the user guides and do not turn experimental behavior
into a stable API promise.

## Examples

- [Minimal application](../examples/minimal/README.md)
- [Windows lifecycle and tray](../examples/windows-lifecycle/README.md)
- [React memo application](../examples/react-memo/README.md)

Examples are executable references. Prefer them when a user request is about a
complete application layout or a frontend integration.

## Maintainer and agent guides

- [LLM and automation guide](llm-guide.md)
- [Contributor guide](../CONTRIBUTING.md)
- [Production readiness](production-readiness.md)
- [Windows GUI acceptance](windows-gui-smoke.md)
- [Framework release process](releasing.md)

These documents describe repository changes, validation, release operations, or
internal boundaries. Keep that material out of the root README.

## Security

- [Security policy](../SECURITY.md)

## Documentation rules

- Keep the root README focused on application users.
- Keep private conversation text, prompts, credentials, and local machine paths
  out of committed documentation.
- Put Chinese user-facing content in `README-cn.md` or a clearly named localized
  document.
- Put maintainer, release, CI, and architecture details in the maintainer
  documents above.
- Update the relevant user guide when a public command, configuration field, or
  runtime behavior changes.
