///|
pub(all) suberror EventError {
  InvalidName(String)
} derive(Debug)

///|
pub struct EventName {
  priv value : String
} derive(Eq, Debug)

///|
fn valid_name_char(char : Char) -> Bool {
  let code = char.to_int()
  code > 31 && code != 127
}

///|
pub fn EventName::new(value : String) -> EventName raise EventError {
  if value.is_empty() || value.length() > 128 {
    raise InvalidName(value)
  }
  for char in value {
    if !valid_name_char(char) {
      raise InvalidName(value)
    }
  }
  { value, }
}

///|
pub fn EventName::value(self : EventName) -> String {
  self.value
}

///|
pub(all) enum EventTarget {
  Any
  Application
  Window(String)
  Runtime(String)
  Ipc(String)
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct EventEnvelope {
  name : EventName
  source : EventTarget
  target : EventTarget
  payload : Json
} derive(Eq, Debug)

///|
pub fn EventEnvelope::new(
  name~ : EventName,
  payload~ : Json,
  source? : EventTarget = Application,
  target? : EventTarget = Any,
) -> EventEnvelope {
  { name, source, target, payload }
}

///|
pub(all) struct EventDeliveryFailure {
  code : String
  message : String
} derive(Eq, Debug)

///|
pub fn EventDeliveryFailure::new(
  code~ : String,
  message~ : String,
) -> EventDeliveryFailure {
  { code, message }
}

///|
pub(open) trait EventSink {
  fn emit(Self, EventEnvelope) -> Result[Unit, EventDeliveryFailure]
}
