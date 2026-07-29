///|
fn runtime_error(
  operation : String,
  error : @moonview.WebViewError,
) -> @orbit_runtime.RuntimeError {
  match error {
    Unavailable => Unavailable("MoonView is unavailable")
    Unsupported(reason) => Unsupported(reason)
    ConfigurationLocked => InvalidState("MoonView configuration is locked")
    CreateRejected =>
      OperationFailed(operation, "MoonView rejected the operation")
    WrongThread => InvalidState("MoonView operations must run on the UI thread")
    Destroyed => InvalidState("MoonView runtime is destroyed")
    NativeFailure(code, message) =>
      OperationFailed(operation, "native error \{code}: \{message}")
  }
}

///|
fn report_lifecycle(
  lifecycle_handler : Ref[(@orbit_runtime.RuntimeLifecycleEvent) -> Unit],
  event : @orbit_runtime.RuntimeLifecycleEvent,
) -> Unit {
  (lifecycle_handler.val)(event)
}

///|
let registered_resource_schemes : Array[String] = []

///|
fn ensure_resource_scheme(
  provider : @orbit_runtime.RuntimeResourceProvider?,
) -> Unit raise @orbit_runtime.RuntimeError {
  match provider {
    Some(provider) => {
      let scheme = provider.scheme()
      if !registered_resource_schemes.contains(scheme) {
        match @moonview.register_custom_scheme(scheme) {
          Ok(_) => registered_resource_schemes.push(scheme)
          Err(error) => raise runtime_error("register custom scheme", error)
        }
      }
    }
    None => ()
  }
}

///|
fn embedded_origin(provider : @orbit_runtime.RuntimeResourceProvider) -> String {
  "\{provider.scheme()}://app"
}

///|
fn url_has_origin(url : String, origin : String) -> Bool {
  url == origin ||
  url.has_prefix("\{origin}/") ||
  url.has_prefix("\{origin}?") ||
  url.has_prefix("\{origin}#")
}

///|
fn remote_origin(
  navigation : @orbit_runtime.RemoteNavigation,
  url : String,
) -> String? {
  for origin in navigation.allowed_origins() {
    if url_has_origin(url, origin) {
      return Some(origin)
    }
  }
  None
}

///|
fn page_origin(
  provider : @orbit_runtime.RuntimeResourceProvider?,
  remote_navigation : @orbit_runtime.RemoteNavigation?,
  url : String,
) -> String? {
  match remote_navigation {
    Some(navigation) =>
      match remote_origin(navigation, url) {
        Some(origin) => Some(origin)
        None =>
          match provider {
            Some(provider) if url_has_origin(url, embedded_origin(provider)) =>
              Some(embedded_origin(provider))
            _ => None
          }
      }
    None =>
      match provider {
        Some(provider) if url_has_origin(url, embedded_origin(provider)) =>
          Some(embedded_origin(provider))
        _ => None
      }
  }
}

///|
fn allows_navigation(
  provider : @orbit_runtime.RuntimeResourceProvider?,
  remote_navigation : @orbit_runtime.RemoteNavigation?,
  external_navigation_handler : (String) -> Bool,
  url : String,
) -> Bool {
  match remote_navigation {
    Some(navigation) =>
      remote_origin(navigation, url) is Some(_) ||
      url == navigation.fallback_url() ||
      external_navigation_handler(url)
    None =>
      match provider {
        Some(provider) => {
          let origin = embedded_origin(provider)
          if url_has_origin(url, origin) {
            true
          } else {
            external_navigation_handler(url)
          }
        }
        None => external_navigation_handler(url)
      }
  }
}

///|
fn navigation_decision(
  provider : @orbit_runtime.RuntimeResourceProvider?,
  remote_navigation : @orbit_runtime.RemoteNavigation?,
  external_navigation_handler : (String) -> Bool,
  url : String,
) -> @moonview.NavigationDecision {
  if allows_navigation(
      provider, remote_navigation, external_navigation_handler, url,
    ) {
    Allow
  } else {
    Deny
  }
}

///|
fn navigate_fallback(
  view : @moonview.WebView?,
  remote_navigation : @orbit_runtime.RemoteNavigation?,
  fallback_active : Ref[Bool],
) -> Unit {
  match (view, remote_navigation) {
    (Some(view), Some(navigation)) if !fallback_active.val => {
      fallback_active.val = true
      ignore(view.navigate(navigation.fallback_url()))
    }
    _ => ()
  }
}

///|
fn accepts_resource_request(
  provider : @orbit_runtime.RuntimeResourceProvider,
  request : @moonview.ProtocolRequest,
) -> Bool {
  let origin = embedded_origin(provider)
  request.scheme == provider.scheme() &&
  request.uri.has_prefix("\{origin}/") &&
  (request.http_method == "GET" || request.http_method == "HEAD")
}

///|
fn respond_protocol(
  view : @moonview.WebView,
  request_id : String,
  response : @orbit_runtime.RuntimeResourceResponse,
) -> Unit {
  ignore(
    view.respond_protocol(
      request_id,
      @moonview.ProtocolResponse::new(
        status=response.status(),
        headers=[
          @moonview.HttpHeader::new(
            name="Content-Type",
            value=response.media_type(),
          ),
        ],
        body=response.body(),
      ),
    ),
  )
}

///|
fn respond_not_found(view : @moonview.WebView, request_id : String) -> Unit {
  ignore(
    view.respond_protocol(
      request_id,
      @moonview.ProtocolResponse::new(
        status=404,
        headers=[
          @moonview.HttpHeader::new(
            name="Content-Type",
            value="text/plain; charset=utf-8",
          ),
        ],
        body=b"Not Found",
      ),
    ),
  )
}

///|
fn respond_method_not_allowed(
  view : @moonview.WebView,
  request_id : String,
) -> Unit {
  ignore(
    view.respond_protocol(
      request_id,
      @moonview.ProtocolResponse::new(
        status=405,
        headers=[
          @moonview.HttpHeader::new(name="Allow", value="GET, HEAD"),
          @moonview.HttpHeader::new(
            name="Content-Type",
            value="text/plain; charset=utf-8",
          ),
        ],
        body=b"Method Not Allowed",
      ),
    ),
  )
}

///|
fn handle_protocol_request(
  view : @moonview.WebView,
  provider : @orbit_runtime.RuntimeResourceProvider?,
  request : @moonview.ProtocolRequest,
) -> Unit {
  match provider {
    Some(provider) if !accepts_resource_request(provider, request) =>
      if request.http_method != "GET" && request.http_method != "HEAD" {
        respond_method_not_allowed(view, request.id)
      } else {
        respond_not_found(view, request.id)
      }
    Some(provider) =>
      match
        provider.handle(
          @orbit_runtime.RuntimeResourceRequest::new(
            http_method=request.http_method,
            uri=request.uri,
            body=request.body,
          ),
        ) {
        Some(response) =>
          if request.http_method == "HEAD" {
            respond_protocol(
              view,
              request.id,
              @orbit_runtime.RuntimeResourceResponse::new(
                status=response.status(),
                media_type=response.media_type(),
                body=b"",
              ),
            )
          } else {
            respond_protocol(view, request.id, response)
          }
        None => respond_not_found(view, request.id)
      }
    None => respond_not_found(view, request.id)
  }
}

///|
pub struct MoonViewRuntimeFactory {
  priv marker : Unit
}

///|
pub fn MoonViewRuntimeFactory::new() -> MoonViewRuntimeFactory {
  { marker: () }
}

///|
struct MoonViewRuntime {
  view : @moonview.WebView
  resource_provider : @orbit_runtime.RuntimeResourceProvider?
  remote_navigation : @orbit_runtime.RemoteNavigation?
  external_navigation_handler : (String) -> Bool
  message_handler : Ref[((@orbit_runtime.RuntimePageMessage) -> Unit)?]
  lifecycle_handler : Ref[(@orbit_runtime.RuntimeLifecycleEvent) -> Unit]
  mut destroyed : Bool
}

///|
pub impl @orbit_runtime.RuntimeFactory for MoonViewRuntimeFactory with fn create(
  self,
  host,
  options,
) {
  ignore(self.marker)
  if !@moonview.available() {
    raise Unavailable("MoonView is unavailable")
  }
  let resource_provider = options.resource_provider()
  let remote_navigation = options.remote_navigation()
  let external_navigation_handler = options.external_navigation_handler()
  ensure_resource_scheme(resource_provider)
  let message_handler : Ref[((@orbit_runtime.RuntimePageMessage) -> Unit)?] = Ref(
    None,
  )
  let lifecycle_handler = Ref(options.lifecycle_handler())
  let view_slot : Ref[@moonview.WebView?] = Ref(None)
  let initial_url = match options.initial_content {
    Url(value) => value
    Html(_) => ""
  }
  let initial_html = match options.initial_content {
    Url(_) => ""
    Html(value) => value
  }
  let initial_origin = page_origin(
    resource_provider, remote_navigation, initial_url,
  )
  let current_origin = Ref(initial_origin)
  let fallback_active = Ref(false)
  let bounds = options.bounds
  let moonview_options = @moonview.WebViewOptions::new(
    bounds=@moonview.Rect::new(
      x=bounds.x,
      y=bounds.y,
      width=bounds.width,
      height=bounds.height,
    ),
    initial_url~,
    initial_html~,
    initialization_script=options.initialization_script,
    visible=options.visible,
    on_navigation=url => {
      let decision = navigation_decision(
        resource_provider, remote_navigation, external_navigation_handler, url,
      )
      match decision {
        Allow =>
          current_origin.val = page_origin(
            resource_provider, remote_navigation, url,
          )
        Deny => current_origin.val = None
      }
      decision
    },
    on_event=event => {
      match event {
        Ready => report_lifecycle(lifecycle_handler, Ready)
        CreationFailed(error) =>
          report_lifecycle(
            lifecycle_handler,
            Failed(runtime_error("create", error)),
          )
        PageMessage(message) =>
          match message_handler.val {
            Some(handler) =>
              handler(
                @orbit_runtime.RuntimePageMessage::new(
                  body=message,
                  origin=current_origin.val,
                ),
              )
            None => ()
          }
        SourceChanged(url) => {
          current_origin.val = page_origin(
            resource_provider, remote_navigation, url,
          )
          match remote_navigation {
            Some(navigation) if url_has_origin(url, navigation.fallback_url()) =>
              fallback_active.val = false
            _ => ()
          }
        }
        NavigationFailed(_url, _error) =>
          navigate_fallback(view_slot.val, remote_navigation, fallback_active)
        ProtocolRequest(request) =>
          match view_slot.val {
            Some(view) =>
              handle_protocol_request(view, resource_provider, request)
            None => ()
          }
        _ => ()
      }
    },
  )
  match @moonview.WebView::create(host.native_handle(), moonview_options) {
    Ok(view) => {
      view_slot.val = Some(view)
      MoonViewRuntime::{
        view,
        resource_provider,
        remote_navigation,
        external_navigation_handler,
        message_handler,
        lifecycle_handler,
        destroyed: false,
      }
      as &@orbit_runtime.WebViewRuntime
    }
    Err(error) => raise runtime_error("create", error)
  }
}

///|
pub impl @orbit_runtime.WebViewRuntime for MoonViewRuntime with fn capabilities(
  _self,
) {
  {
    navigation: true,
    script_evaluation: true,
    message_transport: true,
    bounds_updates: true,
    devtools: true,
  }
}

///|
fn MoonViewRuntime::require_live(
  self : MoonViewRuntime,
) -> Unit raise @orbit_runtime.RuntimeError {
  if self.destroyed {
    raise InvalidState("MoonView runtime is destroyed")
  }
}

///|
pub impl @orbit_runtime.WebViewRuntime for MoonViewRuntime with fn navigate(
  self,
  url,
) {
  self.require_live()
  if !allows_navigation(
      self.resource_provider,
      self.remote_navigation,
      self.external_navigation_handler,
      url,
    ) {
    raise Unsupported(
      "navigation outside the embedded application origin is blocked",
    )
  }
  match self.view.navigate(url) {
    Ok(_) => ()
    Err(error) => raise runtime_error("navigate", error)
  }
}

///|
pub impl @orbit_runtime.WebViewRuntime for MoonViewRuntime with fn evaluate_script(
  self,
  script,
  request_id,
) {
  self.require_live()
  match self.view.eval(script, request_id) {
    Ok(_) => ()
    Err(error) => raise runtime_error("evaluate script", error)
  }
}

///|
pub impl @orbit_runtime.WebViewRuntime for MoonViewRuntime with fn post_message(
  self,
  message,
) {
  self.require_live()
  match self.view.post_message(message) {
    Ok(_) => ()
    Err(error) => raise runtime_error("post message", error)
  }
}

///|
pub impl @orbit_runtime.WebViewRuntime for MoonViewRuntime with fn set_message_handler(
  self,
  handler,
) {
  self.require_live()
  self.message_handler.val = handler
}

///|
pub impl @orbit_runtime.WebViewRuntime for MoonViewRuntime with fn set_bounds(
  self,
  bounds,
) {
  self.require_live()
  match
    self.view.set_bounds(
      @moonview.Rect::new(
        x=bounds.x,
        y=bounds.y,
        width=bounds.width,
        height=bounds.height,
      ),
    ) {
    Ok(_) => ()
    Err(error) => raise runtime_error("set bounds", error)
  }
}

///|
pub impl @orbit_runtime.WebViewRuntime for MoonViewRuntime with fn destroy(self) {
  if !self.destroyed {
    self.destroyed = true
    self.message_handler.val = None
    match self.view.destroy() {
      Ok(_) => ()
      Err(error) => raise runtime_error("destroy", error)
    }
    report_lifecycle(self.lifecycle_handler, Destroyed)
  }
}

///|
test "embedded resource providers block external navigation" {
  let provider = Some(
    @orbit_runtime.RuntimeResourceProvider::new(scheme="orbit", handler=_request => {
      None
    }),
  )
  let deny = _url => false
  assert_true(allows_navigation(provider, None, deny, "orbit://app/index.html"))
  assert_true(
    allows_navigation(provider, None, deny, "orbit://app/assets/app.js"),
  )
  assert_false(
    allows_navigation(provider, None, deny, "orbit://application/index.html"),
  )
  assert_false(allows_navigation(provider, None, deny, "https://example.com/"))
  assert_true(
    allows_navigation(provider, None, _url => true, "https://example.com/"),
  )
}

///|
test "remote navigation accepts allowed origins and its fallback only" {
  let navigation = Some(
    @orbit_runtime.RemoteNavigation::new(
      allowed_origins=["https://app.example"],
      fallback_url="orbit://app/fallback.html",
    ),
  )
  assert_true(
    allows_navigation(
      None,
      navigation,
      _url => false,
      "https://app.example/path",
    ),
  )
  assert_true(
    allows_navigation(
      None,
      navigation,
      _url => false,
      "orbit://app/fallback.html",
    ),
  )
  assert_false(
    allows_navigation(None, navigation, _url => false, "https://other.example/"),
  )
}
