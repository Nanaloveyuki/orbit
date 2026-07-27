///|
test "event names accept namespaced identifiers" {
  let name = EventName::new("orbit://runtime/ready")
  inspect(name.value(), content="orbit://runtime/ready")
}

///|
test "event names reject control characters" {
  let rejected = try {
    ignore(EventName::new("runtime\nready"))
    false
  } catch {
    InvalidName(_) => true
  }
  assert_true(rejected)
}

///|
test "event envelopes retain routing metadata" {
  let event = EventEnvelope::new(
    name=EventName::new("runtime:ready"),
    payload={ "ready": true },
    source=Runtime("main"),
    target=Window("main"),
  )
  debug_inspect(event.source, content="Runtime(\"main\")")
  debug_inspect(event.target, content="Window(\"main\")")
}

///|
priv struct RejectingSink {}

///|
impl EventSink for RejectingSink with fn emit(_self, _event) {
  Err(EventDeliveryFailure::new(code="offline", message="runtime unavailable"))
}

///|
test "event sinks report delivery failures as values" {
  let event = EventEnvelope::new(
    name=EventName::new("runtime:ready"),
    payload=null,
  )
  let result = (RejectingSink::{  } as &EventSink).emit(event)
  match result {
    Err(failure) => inspect(failure.code, content="offline")
    Ok(_) => abort("expected delivery failure")
  }
}
