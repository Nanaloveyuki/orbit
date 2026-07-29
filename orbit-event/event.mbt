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

///|
type EventHandler = (EventEnvelope) -> Result[Unit, EventDeliveryFailure]

///|
/// A process-local routed event channel. Delivery is callback-driven so it can
/// be safely used from the desktop UI thread without introducing a second
/// runtime or changing the native plugin ABI.
pub struct EventRouter {
  priv handlers : Map[String, EventHandler]
}

///|
fn target_key(target : EventTarget) -> String {
  match target {
    Any => "any"
    Application => "application"
    Window(label) => "window:\{label}"
    Runtime(label) => "runtime:\{label}"
    Ipc(name) => "ipc:\{name}"
  }
}

///|
pub fn EventRouter::new() -> EventRouter {
  { handlers: Map([]) }
}

///|
pub fn EventRouter::subscribe(
  self : EventRouter,
  target : EventTarget,
  handler : EventHandler,
) -> Result[Unit, EventDeliveryFailure] {
  let key = target_key(target)
  if self.handlers.contains(key) {
    return Err(
      EventDeliveryFailure::new(
        code="duplicate_subscription",
        message="an event handler is already registered for \{key}",
      ),
    )
  }
  self.handlers[key] = handler
  Ok(())
}

///|
pub fn EventRouter::unsubscribe(
  self : EventRouter,
  target : EventTarget,
) -> Unit {
  self.handlers.remove(target_key(target))
}

///|
pub impl EventSink for EventRouter with fn emit(self, event) {
  let specific = target_key(event.target)
  match self.handlers.get(specific) {
    Some(handler) => handler(event)
    None =>
      match self.handlers.get("any") {
        Some(handler) => handler(event)
        None => Ok(())
      }
  }
}
