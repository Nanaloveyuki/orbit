# IPC and Security

> **Status: Reference only.** This document describes the proposed IPC and
> capability contract for the Windows-first `0.1.0-beta.1` core. It is not a
> security certification.

## One command model

MoonView pages, HTTP clients, plugins, and background tasks MUST enter the same
transport-independent command registry. Adapters authenticate and construct
context; the registry performs command lookup, capability evaluation, parsing,
and handler dispatch.

The command registry MUST NOT infer permission from registration. Registering a
command makes it available to the host, but does not grant any principal the right
to invoke it.

## Principal and transport identity

Every invocation MUST carry an explicit principal and transport. The supported
categories are:

- local `window`;
- HTTPS `remote_page`;
- authenticated `http_client`;
- permissioned `plugin`;
- controlled `background_task`.

The transport and principal MUST be available to policy evaluation. A request MUST
NOT be able to select its own principal by supplying a field in an untrusted
payload.

## Capability policy

- A command is allowed only when a matching allow grant exists.
- A matching deny grant MUST take precedence over an allow grant.
- A grant MUST identify the command, principal selector, and any required scope.
- Remote page access MUST require both the MoonView transport scope and an exact
  HTTPS origin scope.
- File, print, and other UI-bound capabilities MUST be limited to an authorized
  local window principal.
- Plugin and HTTP principals MUST NOT inherit local-window privileges implicitly.
- Capability decisions MUST occur before the command handler receives the payload.

## Wire and parser behavior

- Request and response envelopes MUST use the documented protocol version.
- JSON parsing MUST be strict where the protocol requires strictness: malformed
  JSON, duplicate keys, invalid types, unknown required fields, and invalid
  identifiers MUST be rejected before handler execution.
- Command names and invocation IDs MUST use their documented validation rules and
  MUST NOT be accepted merely because they can be represented as strings.
- Message and response limits MUST be enforced before unbounded work or allocation.
- A rejected request MUST return a stable machine-readable error category without
  leaking native paths, capability handles, secrets, or arbitrary raw errors.

## Timeout, cancellation, and delivery

- Each invocation MUST have one terminal response at most.
- Completion, timeout, cancellation, transport failure, and host shutdown MUST be
  race-safe and MUST remove the corresponding pending entry.
- A page timeout SHOULD send a best-effort cancellation to the host, but the host
  MUST still prevent a late response from being delivered twice.
- Cancellation SHOULD be observable through `InvocationContext` for cooperative
  application and plugin handlers.
- A synchronous UI command MUST NOT be moved to an async worker when doing so
  would violate the native modal UI contract.

## Transport boundaries

### MoonView

The embedded page adapter MUST bind messages to the actual window label, page
origin, and MoonView transport. Navigation or origin changes MUST NOT silently
retain an authorization that no longer matches the page.

### HTTP

The HTTP adapter MUST be opt-in and MUST require an authentication callback. The
adapter MUST NOT listen on a port or choose TLS policy on behalf of the host. An
unauthenticated request MUST be rejected before its body is dispatched to a
command handler.

### Plugins

Plugin calls MUST use the plugin principal. Plugin permissions MUST come from the
host configuration and sidecar validation; a sidecar MUST NOT grant itself new
permissions. Host requests from a plugin MUST re-enter policy evaluation and MUST
not bypass the plugin boundary.

### Background work

Background tasks MUST use an explicit background principal and MUST NOT receive
window-only UI capabilities implicitly.

## Sensitive data boundary

- Native paths MUST NOT be placed in page-visible requests, responses, or public
  error messages.
- Opaque file handles MUST be scoped to their owning window and invalidated when
  that window is destroyed or suspended according to the extension contract.
- Capability manifests, plugin permissions, command arguments, secrets, and raw
  native error text MUST NOT be emitted into diagnostics by default.
- Remote pages, HTTP clients, plugins, and background tasks MUST be denied local
  file and modal UI capabilities unless an explicit future standard promotes them.

## Verification reference

The future beta checklist SHOULD cover malformed and duplicate-key payloads,
principal spoofing, deny-over-allow policy, origin mismatch, unauthenticated HTTP,
oversized messages, timeout/completion races, cancellation, late responses,
window-scoped handle invalidation, plugin host requests, and sensitive-data
redaction. These checks are reference coverage, not current security certification.
