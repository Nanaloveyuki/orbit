# Orbit Beta Reference Standards

> **Status: Reference only.** These documents describe the proposed contract for
> `0.1.0-beta.1`. They are not a release gate and do not claim that the current
> implementation has satisfied every item. The standards become enforceable only
> after a first-party test application has exercised the intended core surface.

## Purpose

Orbit is moving from an alpha implementation to a beta contract. The purpose of
this directory is to define what must remain stable, what remains experimental,
and how a future beta release will be evaluated.

The standards are written for maintainers and package authors. Application usage
examples remain in the root README and the task-oriented documents under `docs/`.

## Target

The first target is `0.1.0-beta.1`, with the following default support claim:

- Windows x64 is the first-class native target.
- Linux remains experimental.
- macOS has no Orbit top-level window host.
- Android and OpenHarmony are optional platform work, not part of the Orbit beta
  core contract.

The target is a stable core contract, not a promise that every package in this
repository is stable. Optional extensions may continue to evolve independently.

## Normative terms

- **MUST** means a requirement for the future beta contract. An exception needs
  an explicit compatibility note and migration guidance.
- **SHOULD** means the default engineering rule. An exception must have a reason
  recorded in the change or release documentation.
- **MAY** means an allowed option that must not weaken a `MUST` requirement.

The word "current" always describes the repository at the time of writing. A
current CI result is evidence for implementation status, not automatic proof that
the proposed contract is complete.

## Document map

- [API and compatibility](api-compatibility.md)
- [Package status](package-status.md)
- [Runtime lifecycle](runtime-lifecycle.md)
- [IPC and security](ipc-security.md)
- [Native FFI](native-ffi.md)
- [Extensions](extensions.md)
- Platform and release standards will be added in later batches.

## Source of truth

Detailed normative rules belong in this directory. The user-facing documents may
summarize those rules and link here, but they MUST NOT define a conflicting
version of the compatibility or stability contract.

Until the reference is converted into a release checklist:

1. A document in this directory is a design reference, not a certification.
2. A green test suite proves the tested behavior only; it does not freeze APIs.
3. A package marked experimental must not be described as part of the stable core
   merely because it is shipped in the same MoonCake module.

## Change process

Standards changes SHOULD be submitted as focused documentation pull requests.
Each change MUST state whether it changes the proposed core surface, an
experimental boundary, or only explanatory text. Code and version changes belong
in separate pull requests unless they are required to make the documented
contract truthful.
