///|
pub(all) enum DiagnosticLevel {
  Info
  Warning
  Error
} derive(Eq, Debug)

///|
pub(all) enum DiagnosticKind {
  DesktopStarting
  DesktopStarted
  DesktopStartupFailed
  RuntimeReady
  RuntimeFailed
  RuntimeDestroyed
  RuntimeSuspended
  RuntimeSuspendFailed
  RuntimeResumed
  RuntimeResumeFailed
  ExtensionStartFailed
  ExtensionPollFailed
  ExtensionShutdownFailed
  PluginStartupFailed
  PluginPollFailed
  DesktopStopping
} derive(Eq, Debug)

///|
pub struct DiagnosticEvent {
  level : DiagnosticLevel
  kind : DiagnosticKind
  window_label : String?
  configuration_fingerprint : String?
}

///|
pub fn DiagnosticEvent::new(
  kind : DiagnosticKind,
  level? : DiagnosticLevel = Info,
  window_label? : String? = None,
  configuration_fingerprint? : String? = None,
) -> DiagnosticEvent {
  { level, kind, window_label, configuration_fingerprint }
}

///|
pub fn DiagnosticEvent::with_configuration_fingerprint(
  self : DiagnosticEvent,
  configuration_fingerprint : String,
) -> DiagnosticEvent {
  { ..self, configuration_fingerprint: Some(configuration_fingerprint) }
}

///|
fn DiagnosticKind::code(self : DiagnosticKind) -> String {
  match self {
    DesktopStarting => "desktop.starting"
    DesktopStarted => "desktop.started"
    DesktopStartupFailed => "desktop.startup_failed"
    RuntimeReady => "runtime.ready"
    RuntimeFailed => "runtime.failed"
    RuntimeDestroyed => "runtime.destroyed"
    RuntimeSuspended => "runtime.suspended"
    RuntimeSuspendFailed => "runtime.suspend_failed"
    RuntimeResumed => "runtime.resumed"
    RuntimeResumeFailed => "runtime.resume_failed"
    ExtensionStartFailed => "extension.start_failed"
    ExtensionPollFailed => "extension.poll_failed"
    ExtensionShutdownFailed => "extension.shutdown_failed"
    PluginStartupFailed => "plugin.startup_failed"
    PluginPollFailed => "plugin.poll_failed"
    DesktopStopping => "desktop.stopping"
  }
}

///|
fn DiagnosticLevel::bitlogger_level(self : DiagnosticLevel) -> @bitlogger.Level {
  match self {
    Info => @bitlogger.Level::Info
    Warning => @bitlogger.Level::Warn
    Error => @bitlogger.Level::Error
  }
}

///|
pub fn DiagnosticEvent::to_record(self : DiagnosticEvent) -> @bitlogger.Record {
  let fields = [
    @bitlogger.field("component", "orbit"),
    @bitlogger.field("event", self.kind.code()),
  ]
  match self.window_label {
    Some(label) => fields.push(@bitlogger.field("window_label", label))
    None => ()
  }
  match self.configuration_fingerprint {
    Some(fingerprint) =>
      fields.push(@bitlogger.field("configuration_fingerprint", fingerprint))
    None => ()
  }
  @bitlogger.Record::new(
    self.level.bitlogger_level(),
    self.kind.code(),
    target="orbit.diagnostics",
    fields~,
  )
}

///|
pub(open) trait DiagnosticSink {
  fn record(Self, DiagnosticEvent) -> Unit
}

///|
pub struct BitLoggerDiagnosticSink {
  sink : &@bitlogger.Sink
}

///|
pub fn BitLoggerDiagnosticSink::new(
  sink : &@bitlogger.Sink,
) -> BitLoggerDiagnosticSink {
  { sink, }
}

///|
pub impl DiagnosticSink for BitLoggerDiagnosticSink with fn record(self, event) {
  self.sink.write(event.to_record())
}

///|
pub struct DiagnosticHistory {
  priv sink : @bitlogger.HistorySink
  priv mut support_events : Array[SupportEvent]
  priv mut support_dropped_event_count : Int
}

///|
pub fn DiagnosticHistory::new(capacity? : Int = 128) -> DiagnosticHistory {
  {
    sink: @bitlogger.history_sink(capacity~),
    support_events: [],
    support_dropped_event_count: 0,
  }
}

///|
pub fn DiagnosticHistory::capacity(self : DiagnosticHistory) -> Int {
  self.sink.capacity()
}

///|
pub fn DiagnosticHistory::count(self : DiagnosticHistory) -> Int {
  self.sink.count()
}

///|
pub fn DiagnosticHistory::dropped_count(self : DiagnosticHistory) -> Int {
  self.sink.dropped_count()
}

///|
pub fn DiagnosticHistory::snapshot(
  self : DiagnosticHistory,
) -> Array[@bitlogger.Record] {
  self.sink.snapshot()
}

///|
pub fn DiagnosticHistory::clear(self : DiagnosticHistory) -> Unit {
  self.sink.clear()
  self.support_events = []
  self.support_dropped_event_count = 0
}

///|
pub fn DiagnosticHistory::support_bundle(
  self : DiagnosticHistory,
) -> SupportBundle {
  {
    schema_version: 1,
    capacity: self.capacity(),
    dropped_event_count: self.support_dropped_event_count,
    events: self.support_events.map(event => event),
  }
}

///|
fn DiagnosticHistory::append_support_event(
  self : DiagnosticHistory,
  event : SupportEvent,
) -> Unit {
  if self.support_events.length() >= self.capacity() {
    self.support_dropped_event_count += 1
    let retained = self.support_events[1:].to_owned()
    retained.push(event)
    self.support_events = retained
  } else {
    self.support_events.push(event)
  }
}

///|
pub impl DiagnosticSink for DiagnosticHistory with fn record(self, event) {
  self.sink.write(event.to_record())
  self.append_support_event(event.to_support_event())
}
