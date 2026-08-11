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
}
