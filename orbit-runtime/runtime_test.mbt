///|
test "runtime bounds reject non-positive dimensions" {
  let rejected = try {
    ignore(RuntimeBounds::new(width=0, height=600))
    false
  } catch {
    InvalidState(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "runtime options require initial content" {
  let bounds = RuntimeBounds::new(width=800, height=600)
  let rejected = try {
    ignore(RuntimeOptions::new(label="main", bounds~, initial_content=Url("")))
    false
  } catch {
    InvalidState(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
priv struct FakeRuntime {
  mut destroyed : Bool
  mut handler : ((String) -> Unit)?
}

///|
impl WebViewRuntime for FakeRuntime with fn capabilities(_self) {
  {
    navigation: true,
    script_evaluation: true,
    message_transport: true,
    bounds_updates: true,
    devtools: false,
  }
}

///|
impl WebViewRuntime for FakeRuntime with fn navigate(self, _url) {
  if self.destroyed {
    raise InvalidState("navigate after destroy")
  }
}

///|
impl WebViewRuntime for FakeRuntime with fn evaluate_script(self, _script, _id) {
  if self.destroyed {
    raise InvalidState("evaluate after destroy")
  }
}

///|
impl WebViewRuntime for FakeRuntime with fn post_message(self, message) {
  if self.destroyed {
    raise InvalidState("post_message after destroy")
  }
  match self.handler {
    Some(handler) => handler(message)
    None => ()
  }
}

///|
impl WebViewRuntime for FakeRuntime with fn set_message_handler(self, handler) {
  if self.destroyed {
    raise InvalidState("set handler after destroy")
  }
  self.handler = handler
}

///|
impl WebViewRuntime for FakeRuntime with fn set_bounds(self, _bounds) {
  if self.destroyed {
    raise InvalidState("set bounds after destroy")
  }
}

///|
impl WebViewRuntime for FakeRuntime with fn destroy(self) {
  self.handler = None
  self.destroyed = true
}

///|
priv struct FakeFactory {}

///|
impl RuntimeFactory for FakeFactory with fn create(_self, _options) {
  FakeRuntime::{ destroyed: false, handler: None } as &WebViewRuntime
}

///|
test "runtime factories return replaceable trait objects" {
  let factory = FakeFactory::{  } as &RuntimeFactory
  let runtime = factory.create(
    RuntimeOptions::new(
      label="main",
      bounds=RuntimeBounds::new(width=800, height=600),
      initial_content=Url("orbit://index.html"),
    ),
  )
  let messages : Array[String] = []
  runtime.set_message_handler(Some(fn(message) { messages.push(message) }))
  runtime.post_message("ready")
  debug_inspect(messages, content="[\"ready\"]")
  runtime.destroy()
  runtime.destroy()
  let rejected = try {
    runtime.post_message("late")
    false
  } catch {
    InvalidState(_) => true
    _ => false
  }
  assert_true(rejected)
  debug_inspect(messages, content="[\"ready\"]")
}
