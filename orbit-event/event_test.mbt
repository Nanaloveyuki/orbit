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

///|
test "router delivers target events and rejects duplicate subscriptions" {
  let router = EventRouter::new()
  let received = Ref(false)
  assert_eq(
    router.subscribe(Window("main"), _event => {
      received.val = true
      Ok(())
    }),
    Ok(()),
  )
  let event = EventEnvelope::new(
    name=EventName::new("orbit://runtime/ready"),
    payload=null,
    target=Window("main"),
  )
  assert_eq((router as &EventSink).emit(event), Ok(()))
  assert_true(received.val)
  match router.subscribe(Window("main"), _event => Ok(())) {
    Err(failure) => inspect(failure.code, content="duplicate_subscription")
    Ok(_) => abort("duplicate subscription was accepted")
  }
}
