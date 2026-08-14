///|
test "diagnostic history retains bounded safe lifecycle records" {
  let history = DiagnosticHistory::new(capacity=1)
  history.record(
    DiagnosticEvent::new(
      RuntimeReady,
      window_label=Some("main"),
      configuration_fingerprint=Some("f00d"),
    ),
  )
  history.record(
    DiagnosticEvent::new(RuntimeSuspended, window_label=Some("main")),
  )

  inspect(history.capacity(), content="1")
  inspect(history.count(), content="1")
  inspect(history.dropped_count(), content="1")
  let record = history.snapshot()[0]
  inspect(record.target, content="orbit.diagnostics")
  inspect(record.message, content="runtime.suspended")
  inspect(record.fields.length(), content="3")
  inspect(record.fields[0].key, content="component")
  inspect(record.fields[0].value, content="orbit")
  inspect(record.fields[1].key, content="event")
  inspect(record.fields[1].value, content="runtime.suspended")
  inspect(record.fields[2].key, content="window_label")
  inspect(record.fields[2].value, content="main")
}

///|
test "diagnostic history clears its retained records" {
  let history = DiagnosticHistory::new()
  history.record(DiagnosticEvent::new(DesktopStarted))
  history.clear()
  inspect(history.count(), content="0")
  inspect(history.dropped_count(), content="0")
  inspect(history.support_bundle().events.length(), content="0")
  inspect(history.support_bundle().dropped_event_count, content="0")
}

///|
test "support bundles retain only reviewed lifecycle fields" {
  let history = DiagnosticHistory::new(capacity=1)
  history.record(
    DiagnosticEvent::new(
      RuntimeReady,
      window_label=Some("main"),
      configuration_fingerprint=Some("f00d"),
    ),
  )
  history.record(DiagnosticEvent::new(RuntimeSuspended))

  let bundle = history.support_bundle()
  inspect(bundle.schema_version, content="1")
  inspect(bundle.capacity, content="1")
  inspect(bundle.dropped_event_count, content="1")
  inspect(bundle.events.length(), content="1")
  inspect(bundle.events[0].level, content="info")
  inspect(bundle.events[0].event, content="runtime.suspended")
  debug_inspect(bundle.events[0].window_label, content="None")
  debug_inspect(bundle.events[0].configuration_fingerprint, content="None")
  let encoded = bundle.to_json().stringify()
  assert_true(!encoded.contains("target"))
  assert_true(!encoded.contains("message"))
  assert_true(!encoded.contains("fields"))
  assert_true(!encoded.contains("timestamp"))
}
