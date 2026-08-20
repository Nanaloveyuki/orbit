# Runtime Lifecycle

> **Status: Reference only.** This document describes the proposed lifecycle
> contract for the Windows-first `0.1.0-beta.1` core. It is not a certification
> of the current implementation.

## Ownership model

- The desktop host and WebView runtime MUST have one explicit owner for each
  native resource.
- UI-bound window and WebView operations MUST run on the host UI thread.
- Async application work, plugin work, and blocking operations MUST NOT block the
  UI thread. They MUST return through the configured async/executor boundary.
- A callback MUST NOT outlive the closure, runtime, or native resource it refers
  to. Native bridges MUST retain callback context for asynchronous use and release
  it exactly once after the final callback.
- A failed operation MUST either leave the previous valid state intact or fully
  tear down the newly created state. It MUST NOT expose a partially initialized
  runtime as active.

## Application lifecycle

The conceptual lifecycle is:

```text
constructed -> starting -> active -> shutting_down -> exited
                         -> suspended -> active
```

The implementation MAY use different internal data structures, but externally
observable behavior MUST follow these rules:

- `starting` MUST validate configuration, extensions, runtime options, and native
  prerequisites before exposing the application as active.
- `active` MUST be the only state in which normal window events and command
  dispatch are accepted.
- `shutting_down` MUST reject new work, finish or cancel owned async work according
  to its contract, and release resources in a deterministic order.
- `exited` MUST not deliver new application callbacks or reuse destroyed native
  handles.
- A startup failure MUST be returned as a structured application error and MUST
  release resources acquired before the failure.

## Window and WebView lifecycle

Each window label MUST identify one logical window within an application. A window
runtime MAY be destroyed and recreated during suspension, but its label and
application ownership remain stable.

- `show` and `hide` change visibility without implying WebView destruction.
- `destroy` releases the window runtime and MUST invalidate window-bound handles
  and callbacks.
- `suspend` MUST run application-owned state preparation before releasing the
  WebView runtime. If preparation fails, the current window and WebView MUST stay
  usable and the caller MUST receive a structured failure.
- Resuming a suspended window MUST create a fresh runtime using the original
  validated options. It MUST NOT silently reuse a destroyed native handle.
- A runtime-specific unsupported operation MUST return an explicit unavailable
  error rather than pretending that the operation succeeded.

## Host callback order

The host integration MUST preserve a documented order for lifecycle callbacks:

1. start the host and validate extensions;
2. mount the configured windows and runtimes;
3. deliver window and page events while active;
4. poll extension and async work at the host wait boundary;
5. stop accepting new work;
6. shut down extensions and runtimes;
7. release the host.

If a later startup step fails, earlier steps MUST be unwound. Extension startup
failure MUST NOT leave an extension registered as started. Shutdown SHOULD release
in reverse startup order so dependencies are still available to their consumers.

## Async, cancellation, and close

- Every async invocation MUST have one terminal result: success, structured error,
  cancellation, or executor shutdown.
- Timeout, cancellation, completion, and close races MUST deliver at most one
  response to the caller.
- Cancellation SHOULD be cooperative for application handlers. The runtime MUST
  still release its own timers, pending entries, and native wait resources when a
  request is cancelled.
- Closing the application MUST prevent new async work from being registered.
- A shutdown failure MUST remain observable to the owner. It MUST NOT be replaced
  by an unconditional success merely because the host is already closing.

## Error contract

- Public lifecycle errors MUST expose stable categories or variants suitable for
  programmatic handling.
- Error messages MAY contain human-readable detail and MAY change between releases
  unless documented otherwise.
- Native error codes MAY be retained as diagnostic data, but callers MUST receive
  a stable Orbit-level category when the error crosses a package boundary.
- Cleanup errors MUST be preserved when they affect resource ownership, native
  library unloading, or data integrity.

## Verification reference

The future beta checklist SHOULD cover startup failure at each initialization
stage, failed suspension, resume after suspension, close during async work,
duplicate terminal delivery, extension startup/shutdown ordering, and reuse of a
destroyed window or WebView handle. A green test is evidence for one scenario; it
does not by itself freeze the lifecycle contract.
