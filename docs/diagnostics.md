# Diagnostics

Orbit exposes a small, application-owned lifecycle diagnostic stream. It is
disabled by default and never writes files, sends network traffic, or records
IPC payloads. The built-in record mapping is deliberately fixed:

- `component=orbit`
- `event`, a stable lifecycle event code
- optional `window_label`
- optional `configuration_fingerprint`

It does not include native paths, raw errors, command arguments, plugin
manifests, capability handles, IPC payloads, or application state.

## Retain Recent Events

`DiagnosticHistory` retains the newest 128 records in memory by default. Pass
it to `DesktopOptions` as a `DiagnosticSink`; your application owns the history
and decides whether, when, and where a snapshot is exported.

```moonbit
let history = @diagnostics.DiagnosticHistory::new(capacity=128)
let options = @core.DesktopOptions::new(
  windows=configured_windows(),
  diagnostic_sink=Some(history as &@diagnostics.DiagnosticSink),
  diagnostic_configuration_fingerprint=Some(configuration_fingerprint),
)
```

`snapshot()` returns copied BitLogger records in oldest-to-newest order.
`dropped_count()` reports evictions since construction or the last `clear()`.
Persisting or uploading a snapshot is application policy: inspect its records,
apply any product-specific redaction, and use your own storage or transport.

## Event Contract

Orbit emits startup, runtime ready/failure/destroy, runtime suspend/resume,
extension failure, plugin startup/poll failure, and desktop shutdown events. Event
codes are intended for filtering and aggregation; user-facing error reporting
should continue to use the existing application error paths.

Diagnostics never changes lifecycle control flow. Omitting the sink preserves
the prior behavior and has no retained-memory cost.

## CLI Environment Report

`orbit diagnose --json` emits one JSON document with schema version `1`. It
contains the host platform and architecture, Moon version, configuration
fingerprint when package metadata is available, a best-effort WebView runtime
probe, and the result of `moon check --target native`. Compiler output is not
mixed into JSON output. A missing runtime is reported as `unknown`; it does not
make the command fail by itself.
