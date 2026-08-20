# Extension Standards

> **Status: Reference only.** Extensions are intentionally experimental for the
> first Orbit beta. This document defines their safety boundary, not a promise to
> freeze every extension API in `0.1.0-beta.1`.

## Common extension rules

- An extension MUST have an explicit owner, identifier, startup hook, and shutdown
  behavior.
- Extension registration MUST be explicit; importing a package MUST NOT silently
  enable native capabilities.
- Extension commands MUST enter the normal Orbit capability policy with their
  correct principal and transport.
- An extension MUST validate its configuration before native resources are
  created.
- Startup failure MUST undo resources and registrations already created by that
  extension.
- Shutdown MUST stop new work before releasing resources. A failed shutdown MUST
  remain observable.
- Experimental extensions MUST state their supported platforms and compatibility
  level in their package and user documentation.

## Plugin ABI and sidecar

Plugin activation SHOULD follow this order:

1. strictly parse and validate the sidecar without loading the dynamic library;
2. validate platform, schema, ABI version, identity, commands, and permissions;
3. load the library and compare its reported manifest with the sidecar;
4. verify that host configuration grants every requested permission;
5. create the plugin instance and register only declared commands.

The sidecar MUST NOT grant permissions to itself. The plugin MUST NOT become
invokable until all identity, command, ABI, and permission checks pass.

ABI v1 and ABI v2 MAY coexist, but they MUST remain distinguishable. ABI v2's
native worker, host-request callback, cancellation, and shutdown behavior MUST
not be inferred from the synchronous v1 contract.

## Plugin invocation and reentrancy

- A plugin command MUST use a plugin principal and re-enter the normal capability
  policy for every host request.
- A host callback context MUST only be used within its documented invocation
  scope. A plugin-created thread MUST NOT retain or invoke it later.
- Direct or indirect re-entry into the same plugin while its worker waits for a
  host response MUST fail quickly with a stable error rather than deadlock.
- Plugin timeout and cancellation MUST cancel the native wait and its associated
  structured async task where supported.
- The dynamic library MUST remain loaded until the plugin instance and worker are
  confirmed stopped.

## HTTP extension

`orbit-ipc-http` is an optional transport, not an application server.

- It MUST be explicitly constructed and authenticated by the host.
- The host owns listener binding, TLS, proxy trust, connection limits, and
  shutdown.
- HTTP authentication MUST complete before request dispatch.
- HTTP clients MUST receive only permissions granted to their authenticated
  principal; request headers MUST NOT choose an Orbit principal.

## Tray and desktop-file extensions

- Tray support MUST remain an explicit extension and MUST not be enabled by a
  configuration field alone.
- Windows tray resources MUST be owned by the UI host and released on shutdown;
  non-Windows adapters MUST expose their documented unavailable behavior.
- File picker and file-handle operations MUST remain explicit extensions.
- File results MUST use opaque, window-scoped handles and MUST NOT expose native
  paths to pages or remote principals.
- Suspending or destroying a window MUST revoke or invalidate extension resources
  whose lifetime is bound to that window.

## Diagnostics extension

Diagnostics MUST be opt-in and bounded. They MUST exclude IPC payloads, paths,
handles, plugin manifests, command arguments, secrets, and uncontrolled native
error text unless a later standard explicitly allows a reviewed field.

Diagnostics are support material, not a telemetry or crash-reporting service.

## Promotion rule

An extension MAY leave experimental status only after a separate review covers its
public API, native ownership, failure model, platform claim, security boundary,
focused tests, integration fixture, migration documentation, and package release
policy. Core beta readiness MUST NOT depend on promoting every extension.

## Verification reference

The future extension checklist SHOULD cover invalid sidecars, manifest mismatch,
missing permissions, malformed plugin responses, cancellation, direct and indirect
reentrancy, worker shutdown failure, HTTP authentication failure, tray teardown,
window-scoped handle invalidation, and diagnostics redaction.
