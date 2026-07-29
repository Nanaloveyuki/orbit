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
pub(all) enum RuntimeLifecycleEvent {
  Ready
  Failed(RuntimeError)
  Destroyed
} derive(Debug)

///|
pub struct RuntimeHost {
  native_handle : UInt64
} derive(Eq, Debug)

///|
pub fn RuntimeHost::new(
  native_handle : UInt64,
) -> RuntimeHost raise RuntimeError {
  if native_handle == 0UL {
    raise InvalidState("runtime host handle must not be zero")
  }
  { native_handle, }
}

///|
pub fn RuntimeHost::native_handle(self : RuntimeHost) -> UInt64 {
  self.native_handle
}

///|
pub(all) enum InitialContent {
  Url(String)
  Html(String)
} derive(Eq, Debug)

///|
pub struct RuntimeResourceRequest {
  http_method : String
  uri : String
  body : Bytes
}

///|
pub fn RuntimeResourceRequest::new(
  http_method~ : String,
  uri~ : String,
  body~ : Bytes,
) -> RuntimeResourceRequest {
  { http_method, uri, body }
}

///|
pub fn RuntimeResourceRequest::http_method(
  self : RuntimeResourceRequest,
) -> String {
  self.http_method
}

///|
pub fn RuntimeResourceRequest::uri(self : RuntimeResourceRequest) -> String {
  self.uri
}

///|
pub fn RuntimeResourceRequest::body(self : RuntimeResourceRequest) -> Bytes {
  self.body
}

///|
pub struct RuntimeResourceResponse {
  status : Int
  media_type : String
  body : Bytes
}

///|
pub fn RuntimeResourceResponse::new(
  status~ : Int,
  media_type~ : String,
  body~ : Bytes,
) -> RuntimeResourceResponse {
  { status, media_type, body }
}

///|
pub fn RuntimeResourceResponse::status(self : RuntimeResourceResponse) -> Int {
  self.status
}

///|
pub fn RuntimeResourceResponse::media_type(
  self : RuntimeResourceResponse,
) -> String {
  self.media_type
}

///|
pub fn RuntimeResourceResponse::body(self : RuntimeResourceResponse) -> Bytes {
  self.body
}

///|
pub struct RuntimeResourceProvider {
  scheme : String
  handler : (RuntimeResourceRequest) -> RuntimeResourceResponse?
}

///|
pub fn RuntimeResourceProvider::new(
  scheme~ : String,
  handler~ : (RuntimeResourceRequest) -> RuntimeResourceResponse?,
) -> RuntimeResourceProvider raise RuntimeError {
  if scheme.is_empty() || scheme.contains(":") || scheme.contains("/") {
    raise InvalidState(
      "runtime resource scheme must be a non-empty scheme name",
    )
  }
  { scheme, handler }
}

///|
pub fn RuntimeResourceProvider::scheme(
  self : RuntimeResourceProvider,
) -> String {
  self.scheme
}

///|
pub fn RuntimeResourceProvider::handle(
  self : RuntimeResourceProvider,
  request : RuntimeResourceRequest,
) -> RuntimeResourceResponse? {
  (self.handler)(request)
}

///|
pub struct RuntimeOptions {
  label : String
  initial_content : InitialContent
  initialization_script : String
  bounds : RuntimeBounds
  visible : Bool
  lifecycle_handler : (RuntimeLifecycleEvent) -> Unit
  resource_provider : RuntimeResourceProvider?
}

///|
pub fn RuntimeOptions::new(
  label~ : String,
  bounds~ : RuntimeBounds,
  initial_content~ : InitialContent,
  initialization_script? : String = "",
  visible? : Bool = true,
  lifecycle_handler? : (RuntimeLifecycleEvent) -> Unit = _event => (),
  resource_provider? : RuntimeResourceProvider? = None,
) -> RuntimeOptions raise RuntimeError {
  if label.is_empty() {
    raise InvalidState("runtime label must not be empty")
  }
  match initial_content {
    Url(value) | Html(value) if value.is_empty() =>
      raise InvalidState("runtime initial content must not be empty")
    _ => ()
  }
  {
    label,
    initial_content,
    initialization_script,
    bounds,
    visible,
    lifecycle_handler,
    resource_provider,
  }
}

///|
pub fn RuntimeOptions::with_lifecycle_handler(
  self : RuntimeOptions,
  lifecycle_handler : (RuntimeLifecycleEvent) -> Unit,
) -> RuntimeOptions {
  { ..self, lifecycle_handler, }
}

///|
pub fn RuntimeOptions::with_initialization_script(
  self : RuntimeOptions,
  initialization_script : String,
) -> RuntimeOptions {
  { ..self, initialization_script, }
}

///|
pub fn RuntimeOptions::lifecycle_handler(
  self : RuntimeOptions,
) -> (RuntimeLifecycleEvent) -> Unit {
  self.lifecycle_handler
}

///|
pub fn RuntimeOptions::label(self : RuntimeOptions) -> String {
  self.label
}

///|
pub fn RuntimeOptions::resource_provider(
  self : RuntimeOptions,
) -> RuntimeResourceProvider? {
  self.resource_provider
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
  fn create(Self, RuntimeHost, RuntimeOptions) -> &WebViewRuntime raise RuntimeError
}
