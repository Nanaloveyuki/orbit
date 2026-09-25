///|
pub(all) struct SupportEvent {
  level : String
  event : String
  window_label : String?
  configuration_fingerprint : String?
} derive(Eq, Debug, ToJson)

///|
pub extend SupportEvent with Eq::{not_equal, equal}

///|
pub extend SupportEvent with Debug::{to_repr}

///|
pub extend SupportEvent with ToJson::{to_json}

///|
pub(all) struct SupportBundle {
  schema_version : Int
  capacity : Int
  dropped_event_count : Int
  events : Array[SupportEvent]
} derive(Eq, Debug, ToJson)

///|
pub extend SupportBundle with Eq::{not_equal, equal}

///|
pub extend SupportBundle with Debug::{to_repr}

///|
pub fn SupportBundle::to_json(self : SupportBundle) -> Json {
  @json.to_json(self)
}

///|
fn DiagnosticLevel::support_code(self : DiagnosticLevel) -> String {
  match self {
    Info => "info"
    Warning => "warning"
    Error => "error"
  }
}

///|
fn DiagnosticEvent::to_support_event(self : DiagnosticEvent) -> SupportEvent {
  {
    level: self.level.support_code(),
    event: self.kind.code(),
    window_label: self.window_label,
    configuration_fingerprint: self.configuration_fingerprint,
  }
}
