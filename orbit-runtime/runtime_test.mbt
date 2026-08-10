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
test "resource providers require a scheme name" {
  let rejected = try {
    ignore(RuntimeResourceProvider::new(scheme="", handler=_request => None))
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
  mut handler : ((RuntimePageMessage) -> Unit)?
}

///|
impl WebViewRuntime for FakeRuntime with fn capabilities(_self) {
  {
    navigation: true,
    script_evaluation: true,
    message_transport: true,
    bounds_updates: true,
    devtools: false,
    file_dialogs: false,
  }
}

///|
impl WebViewRuntime for FakeRuntime with fn show_file_dialog(_self, _options) {
  raise Unsupported("file dialogs are unavailable in FakeRuntime")
}

///|
impl WebViewRuntime for FakeRuntime with fn open_print_dialog(_self) {
  raise Unsupported("print dialogs are unavailable in FakeRuntime")
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
    Some(handler) => handler(RuntimePageMessage::new(body=message))
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
impl RuntimeFactory for FakeFactory with fn create(_self, _host, _options) {
  FakeRuntime::{ destroyed: false, handler: None } as &WebViewRuntime
}

///|
test "runtime factories return replaceable trait objects" {
  let factory = FakeFactory::{  } as &RuntimeFactory
  let runtime = factory.create(
    RuntimeHost::new(1UL),
    RuntimeOptions::new(
      label="main",
      bounds=RuntimeBounds::new(width=800, height=600),
      initial_content=Url("orbit://index.html"),
    ),
  )
  let messages : Array[String] = []
  runtime.set_message_handler(
    Some(fn(message) { messages.push(message.body()) }),
  )
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

///|
test "unsupported runtimes reject file dialogs explicitly" {
  let runtime = FakeRuntime::{ destroyed: false, handler: None }
  let rejected = try {
    ignore(
      WebViewRuntime::show_file_dialog(
        runtime,
        RuntimeFileDialogOptions::new(kind=RuntimeFileDialogKind::OpenFile),
      ),
    )
    false
  } catch {
    Unsupported(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "unsupported runtimes reject print dialogs explicitly" {
  let runtime = FakeRuntime::{ destroyed: false, handler: None }
  let rejected = try {
    WebViewRuntime::open_print_dialog(runtime)
    false
  } catch {
    Unsupported(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "runtime hosts reject a missing native handle" {
  let rejected = try {
    ignore(RuntimeHost::new(0UL))
    false
  } catch {
    InvalidState(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "external navigation remains denied unless the host approves it" {
  let options = RuntimeOptions::new(
    label="main",
    bounds=RuntimeBounds::new(width=800, height=600),
    initial_content=Url("orbit://app/index.html"),
  )
  assert_false(options.external_navigation_handler()("https://example.com"))
  let approved = options.with_external_navigation_handler(url => {
    url == "https://docs.example.com/"
  })
  assert_true(
    approved.external_navigation_handler()("https://docs.example.com/"),
  )
  assert_false(approved.external_navigation_handler()("https://example.com/"))
}

///|
test "remote navigation requires a fallback and unique origins" {
  let navigation = RemoteNavigation::new(
    allowed_origins=["https://app.example"],
    fallback_url="orbit://app/fallback.html",
  )
  inspect(navigation.fallback_url(), content="orbit://app/fallback.html")
  let rejected = try {
    ignore(
      RemoteNavigation::new(
        allowed_origins=["https://app.example", "https://app.example"],
        fallback_url="orbit://app/fallback.html",
      ),
    )
    false
  } catch {
    InvalidState(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "remote navigation requires an embedded fallback provider" {
  let navigation = RemoteNavigation::new(
    allowed_origins=["https://app.example"],
    fallback_url="orbit://app/fallback.html",
  )
  let rejected = try {
    ignore(
      RuntimeOptions::new(
        label="main",
        bounds=RuntimeBounds::new(width=800, height=600),
        initial_content=Url("https://app.example"),
        remote_navigation=Some(navigation),
      ),
    )
    false
  } catch {
    InvalidState(_) => true
    _ => false
  }
  assert_true(rejected)
}
