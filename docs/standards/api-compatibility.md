# API and Compatibility

> **Status: Reference only.** These rules are the proposed compatibility contract
> for `0.1.0-beta.1`; they are not yet release gates.

## Compatibility surfaces

Orbit has more than one public surface. A compatibility review MUST identify
which surface changed before deciding the version or migration impact.

| Surface | Examples | Default beta treatment |
| --- | --- | --- |
| MoonBit core API | public types, functions, traits, enums, error variants | Freeze documented core symbols and semantics |
| Configuration | `schema_version: 2`, fields, validation, normalization | Preserve accepted valid configurations and document migrations |
| IPC protocol | request/response envelopes, error codes, timeout/cancel behavior | Preserve protocol semantics and machine-readable error codes |
| CLI | commands, options, exit status, JSON output, generated files | Preserve documented automation behavior |
| Package metadata | compatibility profile, generated bindings, package descriptors | Reject incompatible artifacts explicitly |
| Plugin ABI and sidecar | ABI v1/v2, sidecar schema, permissions | Experimental until separately promoted |

## Alpha, beta, and stable

### Alpha

- Public APIs MAY change or be removed.
- Every breaking change MUST have a changelog entry and migration note when it
  affects documented usage.
- Compatibility profiles and generated interfaces MUST reflect the new behavior.

### Beta

- The documented core API MUST be frozen except for critical correctness,
  security, or data-integrity fixes.
- A replacement API SHOULD be introduced before removing a deprecated core API.
- A breaking change MUST NOT be silently introduced in a patch release or hidden
  behind a compatibility alias that changes the documented semantics.
- Configuration, CLI, protocol, and package metadata changes MUST state whether
  old artifacts remain readable and how users migrate.

### Stable

- The beta core contract becomes the baseline for the stable compatibility policy.
- Extensions can remain experimental and version independently, but their status
  MUST be visible in package and platform documentation.

## Public API rules

- A public MoonBit symbol MUST have a deliberate owner package and documented
  lifetime/ownership behavior where native resources are involved.
- Public errors MUST expose stable machine-readable categories or error variants.
  Human-readable messages MAY change unless explicitly documented as data.
- A public API change MUST update generated `.mbti` output through MoonBit tooling;
  generated interfaces MUST NOT be edited by hand.
- A change crossing package boundaries SHOULD include a focused contract test or
  integration fixture.
- New convenience aliases MUST NOT be added solely to preserve an alpha API when
  the alias would keep an unsafe or ambiguous contract alive.

## Configuration and CLI

- `schema_version` and compatibility profile changes MUST be intentional and
  documented together.
- Strict parsing behavior, duplicate-key rejection, unknown-field handling, and
  path/resource validation MUST remain explicit.
- CLI machine-readable output MUST have a documented schema and stable exit
  meaning. Human-readable wording MAY change.
- Generated application files MUST use the same compatibility versions as the
  Orbit package and CLI that generated them.
- A migration command or documented manual migration MUST exist before removing
  a supported configuration shape.

## Dependencies and releases

- A published Orbit package MUST use published dependency versions; local paths
  MUST NOT appear in manifests or generated artifacts.
- Direct dependencies that affect the core contract MUST be recorded in the
  release notes and compatibility profile when their behavior is exposed.
- The release workflow MUST verify that the MoonBit module version, CLI package
  version, tag, and compatibility profile agree.
- Toolchain selection MUST resolve to the compiler version used for the release.
  A moving installer channel is acceptable only while CI asserts the expected
  compiler and the release notes state the limitation.

## Deprecation and migration

Deprecation notes SHOULD contain:

1. the old symbol, field, command, or behavior;
2. the replacement and a concrete migration example;
3. the earliest release where removal may occur;
4. compatibility impact for generated files, plugins, and packaged artifacts.

The reference standard does not require preserving every alpha API. It requires
that a deliberate removal be visible, explainable, and mechanically discoverable
from the release documentation.
