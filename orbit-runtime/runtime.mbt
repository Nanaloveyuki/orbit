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
  file_dialogs : Bool
} derive(Eq, Debug)

///|
pub(all) enum RuntimeFileDialogKind {
  OpenFile
  OpenFiles
  SaveFile
  PickDirectory
} derive(Eq, Debug)

///|
pub(all) struct RuntimeFileDialogFilter {
  name : String
  extensions : Array[String]
} derive(Eq, Debug)

///|
pub(all) struct RuntimeFileDialogOptions {
  kind : RuntimeFileDialogKind
  title : String?
  filters : Array[RuntimeFileDialogFilter]
  default_name : String?
  initial_directory : String?
} derive(Eq, Debug)

///|
pub(all) enum RuntimeFileDialogResult {
  Cancelled
  Selected(Array[String])
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
/// A message delivered by the current top-level page. `origin` is absent when
/// an adapter cannot establish a trustworthy document origin.
pub struct RuntimePageMessage {
  body : String
  origin : String?
}

///|
pub fn RuntimePageMessage::new(
  body~ : String,
  origin? : String? = None,
) -> RuntimePageMessage {
  { body, origin }
}

///|
pub fn RuntimePageMessage::body(self : RuntimePageMessage) -> String {
  self.body
}

///|
pub fn RuntimePageMessage::origin(self : RuntimePageMessage) -> String? {
  self.origin
}

///|
pub fn RuntimeFileDialogFilter::new(
  name~ : String,
  extensions~ : Array[String],
) -> RuntimeFileDialogFilter {
  { name, extensions }
}

///|
pub fn RuntimeFileDialogOptions::new(
  kind~ : RuntimeFileDialogKind,
  title? : String? = None,
  filters? : Array[RuntimeFileDialogFilter] = [],
  default_name? : String? = None,
  initial_directory? : String? = None,
) -> RuntimeFileDialogOptions {
  { kind, title, filters, default_name, initial_directory }
}

///|
/// Describes the embedded fallback used when a configured remote page cannot
/// be loaded or a navigation is rejected.
pub struct RemoteNavigation {
  allowed_origins : Array[String]
  fallback_url : String
}

///|
pub fn RemoteNavigation::new(
  allowed_origins~ : Array[String],
  fallback_url~ : String,
) -> RemoteNavigation raise RuntimeError {
  if allowed_origins.is_empty() || fallback_url.is_empty() {
    raise InvalidState(
      "remote navigation requires allowed origins and a fallback URL",
    )
  }
  let seen : Map[String, Bool] = Map([])
  for origin in allowed_origins {
    if origin.is_empty() || seen.contains(origin) {
      raise InvalidState(
        "remote navigation origins must be non-empty and unique",
      )
    }
    seen[origin] = true
  }
  { allowed_origins, fallback_url }
}

///|
pub fn RemoteNavigation::allowed_origins(
  self : RemoteNavigation,
) -> Array[String] {
  self.allowed_origins
}

///|
pub fn RemoteNavigation::fallback_url(self : RemoteNavigation) -> String {
  self.fallback_url
}

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
  external_navigation_handler : (String) -> Bool
  resource_provider : RuntimeResourceProvider?
  remote_navigation : RemoteNavigation?
}

///|
pub fn RuntimeOptions::new(
  label~ : String,
  bounds~ : RuntimeBounds,
  initial_content~ : InitialContent,
  initialization_script? : String = "",
  visible? : Bool = true,
  lifecycle_handler? : (RuntimeLifecycleEvent) -> Unit = _event => (),
  external_navigation_handler? : (String) -> Bool = _url => false,
  resource_provider? : RuntimeResourceProvider? = None,
  remote_navigation? : RemoteNavigation? = None,
) -> RuntimeOptions raise RuntimeError {
  if label.is_empty() {
    raise InvalidState("runtime label must not be empty")
  }
  match initial_content {
    Url(value) | Html(value) if value.is_empty() =>
      raise InvalidState("runtime initial content must not be empty")
    _ => ()
  }
  match (remote_navigation, resource_provider) {
    (Some(_), None) =>
      raise InvalidState(
        "remote navigation requires an embedded resource provider for fallback content",
      )
    (Some(navigation), Some(provider)) if !navigation
      .fallback_url()
      .has_prefix("\{provider.scheme()}://app/") =>
      raise InvalidState(
        "remote fallback URL must use the embedded resource provider origin",
      )
    _ => ()
  }
  {
    label,
    initial_content,
    initialization_script,
    bounds,
    visible,
    lifecycle_handler,
    external_navigation_handler,
    resource_provider,
    remote_navigation,
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
/// Replaces the default-deny external navigation handler. The handler runs
/// only for URLs outside the embedded application origin.
pub fn RuntimeOptions::with_external_navigation_handler(
  self : RuntimeOptions,
  external_navigation_handler : (String) -> Bool,
) -> RuntimeOptions {
  { ..self, external_navigation_handler, }
}

///|
pub fn RuntimeOptions::lifecycle_handler(
  self : RuntimeOptions,
) -> (RuntimeLifecycleEvent) -> Unit {
  self.lifecycle_handler
}

///|
pub fn RuntimeOptions::external_navigation_handler(
  self : RuntimeOptions,
) -> (String) -> Bool {
  self.external_navigation_handler
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
pub fn RuntimeOptions::remote_navigation(
  self : RuntimeOptions,
) -> RemoteNavigation? {
  self.remote_navigation
}

///|
pub(open) trait WebViewRuntime {
  fn capabilities(Self) -> RuntimeCapabilities
  fn show_file_dialog(Self, RuntimeFileDialogOptions) -> RuntimeFileDialogResult raise RuntimeError
  fn open_print_dialog(Self) -> Unit raise RuntimeError
  fn navigate(Self, String) -> Unit raise RuntimeError
  fn evaluate_script(Self, String, String) -> Unit raise RuntimeError
  fn post_message(Self, String) -> Unit raise RuntimeError
  fn set_message_handler(Self, ((RuntimePageMessage) -> Unit)?) -> Unit raise RuntimeError
  fn set_bounds(Self, RuntimeBounds) -> Unit raise RuntimeError
  fn set_visible(Self, Bool) -> Unit raise RuntimeError
  /// Implementations must make repeated destruction safe and stop callbacks.
  fn destroy(Self) -> Unit raise RuntimeError
}

///|
pub(open) trait RuntimeFactory {
  fn create(Self, RuntimeHost, RuntimeOptions) -> &WebViewRuntime raise RuntimeError
}
