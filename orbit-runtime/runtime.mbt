///|
pub(all) suberror RuntimeError {
  Unavailable(String)
  Unsupported(String)
  InvalidState(String)
  OperationFailed(String, String)
} derive(Debug)

///|
pub struct RuntimeBounds {
  x : Int
  y : Int
  width : Int
  height : Int
} derive(Eq, Debug)

///|
pub fn RuntimeBounds::new(
  x? : Int = 0,
  y? : Int = 0,
  width~ : Int,
  height~ : Int,
) -> RuntimeBounds raise RuntimeError {
  if width <= 0 || height <= 0 {
    raise InvalidState("runtime bounds must have positive dimensions")
  }
  { x, y, width, height }
}

///|
pub(all) struct RuntimeCapabilities {
  navigation : Bool
  script_evaluation : Bool
  message_transport : Bool
  bounds_updates : Bool
  devtools : Bool
} derive(Eq, Debug)

///|
pub(all) enum InitialContent {
  Url(String)
  Html(String)
} derive(Eq, Debug)

///|
pub struct RuntimeOptions {
  label : String
  initial_content : InitialContent
  initialization_script : String
  bounds : RuntimeBounds
  visible : Bool
}

///|
pub fn RuntimeOptions::new(
  label~ : String,
  bounds~ : RuntimeBounds,
  initial_content~ : InitialContent,
  initialization_script? : String = "",
  visible? : Bool = true,
) -> RuntimeOptions raise RuntimeError {
  if label.is_empty() {
    raise InvalidState("runtime label must not be empty")
  }
  match initial_content {
    Url(value) | Html(value) if value.is_empty() =>
      raise InvalidState("runtime initial content must not be empty")
    _ => ()
  }
  { label, initial_content, initialization_script, bounds, visible }
}

///|
pub(open) trait WebViewRuntime {
  fn capabilities(Self) -> RuntimeCapabilities
  fn navigate(Self, String) -> Unit raise RuntimeError
  fn evaluate_script(Self, String, String) -> Unit raise RuntimeError
  fn post_message(Self, String) -> Unit raise RuntimeError
  fn set_message_handler(Self, ((String) -> Unit)?) -> Unit raise RuntimeError
  fn set_bounds(Self, RuntimeBounds) -> Unit raise RuntimeError
  /// Implementations must make repeated destruction safe and stop callbacks.
  fn destroy(Self) -> Unit raise RuntimeError
}

///|
pub(open) trait RuntimeFactory {
  fn create(Self, RuntimeOptions) -> &WebViewRuntime raise RuntimeError
}
