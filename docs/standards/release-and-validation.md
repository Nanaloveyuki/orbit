# Release and Validation

> **Status: Reference only.** This is the proposed release checklist for the
> first beta. It is not currently enforced as a beta gate because the first-party
> test application has not yet completed its validation cycle.

## Evidence levels

Release notes MUST distinguish these evidence levels:

1. **Static contract**: documentation, generated interfaces, manifests, and
   compatibility metadata agree.
2. **Focused verification**: a unit, white-box, black-box, or fixture test covers
   a behavior.
3. **Platform verification**: the behavior passes on the claimed native target
   and package environment.
4. **Application verification**: a first-party application exercises the contract
   through normal workflows over time.

Levels 1-3 do not imply level 4. A future beta release may use levels 1-3 for its
   framework gate, but the evidence level MUST be stated explicitly.

## Source and package consistency

- `moon.mod`, `orbit-cli/package.json`, the Git tag, and the release metadata MUST
  describe the same Orbit version.
- Direct dependencies that affect the core behavior MUST use published versions;
  local paths MUST NOT enter manifests or release artifacts.
- The package archive MUST be inspected with `moon package --list` before release.
  Ignored planning files, build output, local fixtures, and private references MUST
  not be published.
- Generated `.mbti`, embedded resources, bindings, package descriptors, and CLI
  compatibility metadata MUST be regenerated or checked when their inputs change.
- The resolved MoonBit compiler MUST be recorded. A moving installer channel MAY
  be used temporarily only when CI verifies the expected compiler and the release
  note states the reproducibility limitation.

## Framework validation

The future beta framework gate SHOULD include:

- `moon fmt --check`;
- native `moon check --deny-warn` and `moon info`;
- native MoonBit tests with failure-path coverage;
- Windows and Linux plugin fixture integration where the extension is present;
- CLI tests and npm artifact dry-run;
- Linux deb/rpm/Arch/archive package construction and verification;
- Windows GUI smoke for lifecycle, tray/file extensions, WebView, packaging, and
  installer behavior that is claimed by the release.

The check matrix MUST report unsupported or skipped platform features rather than
turning them into false passes.

## Release workflow

The intended maintainership sequence is:

1. update the reference or implementation on a focused branch;
2. run local focused validation and inspect package contents;
3. open a PR with compatibility impact and evidence levels;
4. require applicable CI and review checks;
5. squash-merge into `main` and delete the feature branch;
6. create the matching protected tag from the merged `main` commit;
7. publish MoonCake, npm, and GitHub artifacts through the release workflow;
8. record the resulting tag, package versions, checksums, and workflow result.

Stacked documentation PRs MAY be used for independent standard batches. A stack
MUST be verified as a whole before atomic merge, and each member MUST retain a
clear scope and validation record.

## Reference-to-gate transition

When a first-party test application exists, a separate change MUST:

- map every `MUST` rule to a focused, integration, GUI, or application check;
- identify rules that remain reference-only or experimental;
- define required evidence for Windows x64 and any promoted platform;
- update `docs/releasing.md`, CI, and release notes to consume the checklist;
- avoid treating green framework tests as a substitute for application evidence.
