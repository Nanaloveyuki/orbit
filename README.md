# Orbit

Orbit is a MoonBit desktop application framework built around a replaceable
WebView runtime, embedded Web assets, and a constrained command/event IPC
boundary.

This repository currently contains the Stage 1 foundation packages:

- `orbit-utils`: configuration, resources, platform and CSP utilities.
- `orbit-event`: standalone application and runtime event contracts.
- `orbit-ipc`: command registration and structured invocation envelopes.
- `orbit-runtime`: replaceable WebView runtime contracts.

`orbit-core`, concrete MoonView composition, CLI tooling, code generation and
plugins are intentionally deferred until the foundation APIs are validated.

## Stage 1 boundaries

- Configuration parsing, strict shape validation, normalization and SHA-256
  fingerprinting are available as a pure pipeline. A consumer-side MoonBit
  pre-build executable is still required to turn that pipeline into the fixed
  `orbit.conf.json` build failure and embedding contract. The built-in
  `:embed` tool embeds bytes but cannot validate or normalize JSON.
- `Nanaloveyuki/sync` and `Nanaloveyuki/orby` are not Mooncakes dependencies
  yet because neither module has a published registry release. Orbit does not
  use local path or unpinned Git dependencies as a substitute.
- CSP injection targets framework-controlled application shells containing a
  normal `<head>` element. It is not a general HTML parser. The evaluated
  `moonbit-community/html@0.1.2` parser does not expose the external DOM
  mutation needed for meta insertion and would add unrelated dependencies.
- MoonBit core JSON parsing overwrites duplicate object keys before schema
  validation. Unknown fields, missing fields, type mismatches and fractional
  integer fields are rejected; duplicate-key rejection remains a build-tool
  requirement.

## Development

```sh
moon check --target native --deny-warn
moon test --target native --deny-warn
moon fmt --check
moon info --target native
```
