# Production Readiness

Orbit `0.1.0-alpha.8` is pre-release software. Its current Windows x64
support and signed packaging workflow are suitable for integration testing and
early application delivery, but they are not yet Orbit 1.0 compatibility
promises.

This document records the production contract planned for Windows 1.0. It does
not expand the current alpha support claim.

The proposed `0.1.0-beta.1` framework boundaries are maintained in the
[beta reference standards](standards/README.md). The 1.0 gates below remain a
separate, stricter target.

## Experimental-Stage Priorities

Orbit remains experimental. Performance and engineering quality take priority
over expanding the feature surface or promoting APIs to beta. The Windows 1.0
contract below is a future target, not the current iteration plan or a release
schedule. Public APIs may still change with explicit migration notes.

Near-term work should focus on reproducible correctness fixes, native resource
ownership, deterministic cleanup, actionable errors, and reliable build,
generation, dependency, and release workflows. Add tests for demonstrated
failure modes and application-used boundaries rather than speculative features
or compatibility abstractions.

Dedicated IPC latency and startup-time optimization is deferred until the
MoonBit stable release is available and evaluated with Orbit. That milestone
does not automatically make Orbit stable. Deadlocks, unbounded waits, resource
leaks, and data-integrity defects remain actionable now. Later performance work
should start with reproducible measurements on pinned toolchain and WebView
versions, separating framework costs from application and host costs.

### Contract Reconciliation

Reconciliation records current behavior and resolves ambiguity; it does not
freeze every public symbol or require a runtime redesign. Source and focused
automated checks now cover the following areas; native GUI and application-data
upgrade acceptance remain separate from those checks:

| Area | Scope | Completion evidence |
| --- | --- | --- |
| Window lifecycle | Visibility versus suspension/destruction; preparation failure; close, exit, and crash cleanup | Documented transitions agree with focused failure and cleanup tests |
| IPC semantics | Terminal responses, timeout/cancel races, duplicate requests, busy errors, and limit units | Protocol documentation agrees with boundary tests, including non-ASCII payloads |
| Execution and errors | Supported sync/async entry points, UI-thread ownership, cancellation versus side effects, machine-readable errors | Application-facing behavior is explicit and exercised by focused tests |
| Configuration and artifacts | Schema v2, generated-file ownership, CLI exit/JSON behavior, upgrade effects on stored application data | Existing generation and packaging checks cover the documented behavior; actual migrations have instructions |
| Compatibility scope | Application-used core versus experimental extensions | Deliberate status and migration notes without freezing all public APIs |

The [IPC guide](ipc-and-plugins.md) now distinguishes page/HTTP request bytes,
parser Unicode scalars, and response UTF-16 units without changing those existing
limits. Regression tests cover non-ASCII boundaries, scoped cancellation,
duplicate IDs, late completion, and failed-resume subscription cleanup.

The generator and CLI compatibility profiles now agree with the declared
dependency versions. Native validation runs
`node orbit-cli/scripts/verify-build-compatibility.mjs` against the compiled
generator; release-version validation checks the CLI profile against `moon.mod`.
Existing configuration and CLI tests cover explicit v1 migration, schema v2
validation, generated-file restoration, and package integrity checks.

Remaining experimental boundaries are explicit: cancellation cannot roll back
side effects or preempt blocking FFI; failed native destruction has no general
transactional recovery guarantee; controller/extension text errors are not frozen.
Windows GUI acceptance, real storage upgrades, and install/uninstall behavior
still need application-level validation. See the
[lifecycle reference](standards/runtime-lifecycle.md) and
[packaging guide](packaging.md). No package is promoted to stable by this review.

Use existing applications, including `react-memo`, for application-level
validation. Android daily use is relevant evidence for exercised Android paths,
but does not establish Windows lifecycle or installer behavior. Do not require
a new application or unrelated features merely to demonstrate framework maturity;
record platform, version, exercised workflows, and remaining gaps separately.

## Planned Windows 1.0 Contract

The stable target is Windows 10 22H2 x64 and Windows 11 x64 with the Microsoft
Evergreen WebView2 Runtime available. The stable surface will include:

- configuration schema v2;
- desktop lifecycle, local-window IPC, and capability policy;
- embedded-resource generation;
- CLI build, package, and verification commands;
- signed Windows installer creation and verification; and
- offline, privacy-bounded diagnostic support materials.

Linux remains experimental. macOS is outside the 1.0 target. Orbit will not
provide automatic application updates, remote telemetry, enterprise policy
management, or automatic OS-level crash-dump collection in 1.0.

The tray extension, desktop file bridge, plugin ABI/runtime, HTTP IPC adapter,
and optional lifecycle features remain experimental until each has a separate
stability review. Applications may use them during beta validation, but must
plan for explicit migration notes before relying on them as stable contracts.

## Application Delivery Requirements

Production applications should:

1. Pin compatible Orbit and CLI versions in their own manifests.
2. Build a release package, sign its Windows installer, and publish the
   installer descriptor and SHA-256 checksums with the artifact.
3. Run `orbit verify-package` and `orbit verify-installer` in release CI.
4. Test fresh install, signed upgrade, normal uninstall/reinstall, and the
   application's rollback procedure on every supported Windows baseline.
5. Run the Windows GUI acceptance checklist for every Orbit upgrade that
   changes enabled desktop features.

Orbit's package and installer verification confirms the generated artifact
matches its descriptor. It does not choose an application's signing service,
hosting provider, update mechanism, retention policy, or rollback operation.

## Offline Support Materials

Lifecycle diagnostics are disabled by default and remain application-owned.
The planned 1.0 support bundle will contain only allowlisted environment
metadata, a configuration fingerprint when the application supplies one, and
bounded lifecycle records. It will not automatically persist data or send
network traffic.

Applications will choose whether to serialize, store, inspect, or upload a
bundle. Built-in reports must continue to exclude paths, capability handles,
IPC payloads, plugin manifests, command arguments, raw error text, secrets,
and application state. The `orbit diagnose` environment report is separate:
it cannot see an application's in-memory lifecycle history.

Fatal process crash dumps remain an application or operating-system concern in
1.0. Orbit support materials describe bounded framework lifecycle failures;
they are not a crash-reporting service.

## Release Gates

Before a stable Windows 1.0 release:

- all security, application-data integrity, installer, and upgrade corruption
  defects are release blockers;
- the Windows native, CLI, package, and integration test matrix must pass;
- manual GUI acceptance must pass on Windows 10 22H2 and Windows 11;
- the supported core API and configuration v2 surface must remain compatible
  throughout beta; and
- one first-party application must complete eight weeks of real use, including
  fresh installation, signed upgrade, failed-start recovery, support-material
  collection, and normal uninstall/reinstall.

Pre-beta alpha releases may make incompatible corrections when a documented
migration is provided. Orbit will not retain API aliases solely to preserve an
alpha interface that is unsuitable for the stable contract.
