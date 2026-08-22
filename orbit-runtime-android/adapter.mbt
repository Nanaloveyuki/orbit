///|
fn runtime_error(
  operation : String,
  error : @ajni.JniError,
) -> @runtime.RuntimeError {
  match error {
    NotInitialized => Unavailable("Android JNI runtime is not initialized")
    RuntimeDestroyed => InvalidState("Android JNI runtime is destroyed")
    NativeFailure(message) => OperationFailed(operation, message)
    JavaException(message) => OperationFailed(operation, message)
    InvalidClassName(message) => InvalidState(message)
    InvalidNativeMethodName(message) => InvalidState(message)
    DescriptorTooLong => InvalidState("Android JNI descriptor is too long")
    TooManyParameterSlots =>
      InvalidState("Android JNI descriptor has too many parameter slots")
    TooManyArrayDimensions =>
      InvalidState("Android JNI descriptor has too many array dimensions")
  }
}

///|
fn embedded_origin(provider : @runtime.RuntimeResourceProvider) -> String {
  "\{provider.scheme()}://app"
}

///|
fn embedded_path(
  provider : @runtime.RuntimeResourceProvider,
  url : String,
) -> String? {
  let origin = embedded_origin(provider)
  let prefix = origin + "/"
  if !url.has_prefix(prefix) || url.length() <= prefix.length() {
    None
  } else {
    Some(String::from_array(url.to_array()[prefix.length():]))
  }
}

///|
fn android_asset_url(
  provider : @runtime.RuntimeResourceProvider,
  trusted_origin : String,
  url : String,
) -> String? {
  match embedded_path(provider, url) {
    Some(path) => Some("\{trusted_origin}/assets/\{path}")
    None => None
  }
}

///|
fn response_mime_type(media_type : String) -> String {
  let parts = media_type.split(";").to_array()
  if parts.is_empty() {
    media_type
  } else {
    parts[0].trim().to_owned()
  }
}

///|
fn response_encoding(media_type : String) -> String {
  if media_type.to_lower().contains("charset=utf-8") {
    "utf-8"
  } else {
    ""
  }
}

///|
fn report_lifecycle(
  handler : Ref[(@runtime.RuntimeLifecycleEvent) -> Unit],
  event : @runtime.RuntimeLifecycleEvent,
) -> Unit {
  (handler.val)(event)
}

///|
pub struct AndroidRuntimeFactory {
  priv trusted_origin : String
}

///|
pub fn AndroidRuntimeFactory::new(
  trusted_origin? : String = "https://orbit.local",
) -> AndroidRuntimeFactory {
  { trusted_origin, }
}

///|
struct AndroidRuntime {
  view : @moonview_android.AndroidWebView
  provider : @runtime.RuntimeResourceProvider
  trusted_origin : String
  message_handler : Ref[((@runtime.RuntimePageMessage) -> Unit)?]
  next_operation : Ref[Int]
  mut destroyed : Bool
}

///|
fn next_operation_id(counter : Ref[Int], operation : String) -> String {
  let id = counter.val
  counter.val = id + 1
  "orbit-android-\{operation}-\{id}"
}

///|
fn respond_asset(
  view : @moonview_android.AndroidWebView,
  provider : @runtime.RuntimeResourceProvider,
  request : @moonview_android.AndroidAssetRequest,
  counter : Ref[Int],
) -> Unit {
  let uri = "\{embedded_origin(provider)}/\{request.path}"
  let response = provider.handle(
    @runtime.RuntimeResourceRequest::new(http_method="GET", uri~, body=b""),
  )
  let response = match response {
    Some(response) =>
      @moonview_android.AndroidAssetResponse::new(
        status=response.status(),
        mime_type=response_mime_type(response.media_type()),
        encoding=response_encoding(response.media_type()),
        body=response.body(),
      )
    None =>
      @moonview_android.AndroidAssetResponse::new(
        status=404,
        mime_type="text/plain",
        encoding="utf-8",
        body=b"Not Found",
      )
  }
  view.respond_asset(request.id, response, next_operation_id(counter, "asset")) catch {
    _ => ()
  }
}

///|
pub impl @runtime.RuntimeFactory for AndroidRuntimeFactory with fn create(
  self,
  host,
  options,
) {
  ignore(host)
  let provider = match options.resource_provider() {
    Some(provider) => provider
    None =>
      raise Unsupported(
        "Android runtime requires an embedded resource provider",
      )
  }
  if options.remote_navigation() is Some(_) {
    raise Unsupported("Android remote navigation is not implemented")
  }
  if !options.visible {
    raise Unsupported("Android WebView must be initially visible")
  }
  let initial_content = match options.initial_content {
    Url(url) =>
      match android_asset_url(provider, self.trusted_origin, url) {
        Some(url) => @moonview_android.AndroidInitialContent::Url(url)
        None =>
          raise Unsupported(
            "Android initial URL must use the embedded application origin",
          )
      }
    Html(html) => Html(html, "\{self.trusted_origin}/assets/index.html")
  }
  let message_handler : Ref[((@runtime.RuntimePageMessage) -> Unit)?] = Ref(
    None,
  )
  let lifecycle_handler = Ref(options.lifecycle_handler())
  let view_slot : Ref[@moonview_android.AndroidWebView?] = Ref(None)
  let next_operation = Ref(1)
  let bounds = options.bounds
  let view = @moonview_android.AndroidWebView::create(
    @moonview_android.AndroidWebViewOptions::new(
      bounds=@moonview_android.AndroidBounds::new(
        x=bounds.x,
        y=bounds.y,
        width=bounds.width,
        height=bounds.height,
      ),
      trusted_origin=self.trusted_origin,
      initial_content~,
      document_start_scripts=[options.initialization_script],
      on_event=event => {
        match event {
          Ready => report_lifecycle(lifecycle_handler, Ready)
          CreationFailed(operation, message) =>
            report_lifecycle(
              lifecycle_handler,
              Failed(OperationFailed(operation, message)),
            )
          PageMessage(message) if message.is_main_frame &&
            message.origin == self.trusted_origin =>
            match message_handler.val {
              Some(handler) =>
                handler(
                  @runtime.RuntimePageMessage::new(
                    body=message.body,
                    origin=Some(embedded_origin(provider)),
                  ),
                )
              None => ()
            }
          AssetRequest(request) =>
            match view_slot.val {
              Some(view) =>
                respond_asset(view, provider, request, next_operation)
              None => ()
            }
          Destroyed => report_lifecycle(lifecycle_handler, Destroyed)
          _ => ()
        }
      },
    ),
    next_operation_id(next_operation, "create"),
  ) catch {
    error => raise runtime_error("create", error)
  }
  view_slot.val = Some(view)
  AndroidRuntime::{
    view,
    provider,
    trusted_origin: self.trusted_origin,
    message_handler,
    next_operation,
    destroyed: false,
  }
  as &@runtime.WebViewRuntime
}

///|
fn AndroidRuntime::require_live(
  self : AndroidRuntime,
) -> Unit raise @runtime.RuntimeError {
  if self.destroyed {
    raise InvalidState("Android runtime is destroyed")
  }
}

///|
pub impl @runtime.WebViewRuntime for AndroidRuntime with fn capabilities(_self) {
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
pub impl @runtime.WebViewRuntime for AndroidRuntime with fn show_file_dialog(
  _self,
  _options,
) {
  raise Unsupported("Android file dialogs are not implemented")
}

///|
pub impl @runtime.WebViewRuntime for AndroidRuntime with fn open_print_dialog(
  _self,
) {
  raise Unsupported("Android printing is not implemented")
}

///|
pub impl @runtime.WebViewRuntime for AndroidRuntime with fn navigate(self, url) {
  self.require_live()
  let target = match
    android_asset_url(self.provider, self.trusted_origin, url) {
    Some(target) => target
    None =>
      raise Unsupported(
        "Android navigation outside the embedded application origin is blocked",
      )
  }
  self.view.navigate(target, next_operation_id(self.next_operation, "navigate")) catch {
    error => raise runtime_error("navigate", error)
  }
}

///|
pub impl @runtime.WebViewRuntime for AndroidRuntime with fn evaluate_script(
  self,
  script,
  request_id,
) {
  self.require_live()
  let operation_id = if request_id.is_empty() {
    next_operation_id(self.next_operation, "eval")
  } else {
    request_id
  }
  self.view.eval(script, operation_id) catch {
    error => raise runtime_error("evaluate script", error)
  }
}

///|
pub impl @runtime.WebViewRuntime for AndroidRuntime with fn post_message(
  self,
  message,
) {
  self.require_live()
  self.view.post_message(
    message,
    next_operation_id(self.next_operation, "message"),
  ) catch {
    error => raise runtime_error("post message", error)
  }
}

///|
pub impl @runtime.WebViewRuntime for AndroidRuntime with fn set_message_handler(
  self,
  handler,
) {
  self.require_live()
  self.message_handler.val = handler
}

///|
pub impl @runtime.WebViewRuntime for AndroidRuntime with fn set_bounds(
  self,
  bounds,
) {
  self.require_live()
  self.view.set_bounds(
    @moonview_android.AndroidBounds::new(
      x=bounds.x,
      y=bounds.y,
      width=bounds.width,
      height=bounds.height,
    ),
  ) catch {
    error => raise runtime_error("set bounds", error)
  }
}

///|
pub impl @runtime.WebViewRuntime for AndroidRuntime with fn set_visible(
  self,
  visible,
) {
  self.require_live()
  if !visible {
    raise Unsupported("Android WebView visibility changes are not implemented")
  }
}

///|
pub impl @runtime.WebViewRuntime for AndroidRuntime with fn destroy(self) {
  if !self.destroyed {
    self.destroyed = true
    self.message_handler.val = None
    self.view.destroy(next_operation_id(self.next_operation, "destroy")) catch {
      error => raise runtime_error("destroy", error)
    }
  }
}
