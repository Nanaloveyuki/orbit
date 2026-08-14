# Production Readiness

Orbit `0.1.0-alpha.6` is pre-release software. Its current Windows x64
support and signed packaging workflow are suitable for integration testing and
early application delivery, but they are not yet Orbit 1.0 compatibility
promises.

This document records the production contract planned for Windows 1.0. It does
not expand the current alpha support claim.

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
