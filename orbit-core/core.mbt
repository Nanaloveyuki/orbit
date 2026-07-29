///|
pub(all) suberror CoreError {
  InitializationFailed(String)
  StartupFailed(String)
  RuntimeFailed(String)
} derive(Debug)

///|
pub struct DesktopWindowOptions {
  window_title : String
  runtime_options : @runtime.RuntimeOptions
  resizable : Bool
}

///|
pub fn DesktopWindowOptions::new(
  window_title : String,
  runtime_options : @runtime.RuntimeOptions,
  resizable? : Bool = true,
) -> DesktopWindowOptions raise CoreError {
  if window_title.is_empty() {
    raise InitializationFailed("window title must not be empty")
  }
  { window_title, runtime_options, resizable }
}

///|
pub struct DesktopOptions {
  windows : Array[DesktopWindowOptions]
  ipc_registry : @ipc.CommandRegistry?
  ipc_policy : @ipc.CommandPolicy?
  plugin_declarations : Array[@plugin.PluginDeclaration]
  plugin_development_directory : String?
  event_router : @event.EventRouter?
}

///|
pub fn DesktopOptions::new(
  windows~ : Array[DesktopWindowOptions],
  ipc_registry? : @ipc.CommandRegistry? = None,
  ipc_policy? : @ipc.CommandPolicy? = None,
  plugin_declarations? : Array[@plugin.PluginDeclaration] = [],
  plugin_development_directory? : String? = None,
  event_router? : @event.EventRouter? = None,
) -> DesktopOptions raise CoreError {
  if windows.is_empty() {
    raise InitializationFailed("at least one desktop window is required")
  }
  let labels : Map[String, Bool] = Map([])
  for window in windows {
    let label = window.runtime_options.label()
    if labels.contains(label) {
      raise InitializationFailed(
        "desktop window labels must be unique: \{label}",
      )
    }
    labels[label] = true
  }
  match (ipc_registry, ipc_policy) {
    (Some(_), None) | (None, Some(_)) =>
      raise InitializationFailed(
        "IPC registry and command policy must be configured together",
      )
    _ => ()
  }
  if !plugin_declarations.is_empty() && ipc_registry is None {
    raise InitializationFailed(
      "plugins require an IPC registry and command policy",
    )
  }
  {
    windows,
    ipc_registry,
    ipc_policy,
    plugin_declarations,
    plugin_development_directory,
    event_router,
  }
}

///|
fn runtime_reason(error : @runtime.RuntimeError) -> String {
  match error {
    Unavailable(message) => message
    Unsupported(message) => message
    InvalidState(message) => message
    OperationFailed(operation, message) => "\{operation}: \{message}"
  }
}

///|
fn window_reason(error : @orby.WindowError) -> String {
  match error {
    CreationFailed(message) => message
    MonitorUnavailable(_) => "requested monitor is unavailable"
    Destroyed => "window was destroyed during startup"
  }
}

///|
fn init_reason(error : @orby.InitError) -> String {
  match error {
    UnsupportedHost(message) => message
    PlatformFailure(message) => message
  }
}

///|
fn app_reason(error : @orby.AppError) -> CoreError {
  match error {
    StartupFailed(message) => StartupFailed(message)
    RuntimeFailed(message) => RuntimeFailed(message)
  }
}

///|
struct DesktopApp {
  factory : &@runtime.RuntimeFactory
  options : DesktopOptions
  windows : Array[MountedWindow]
  plugins : @plugin.PluginRuntime
  mut pending_runtime_failure : String?
  mut shutting_down : Bool
}

///|
priv struct MountedWindow {
  window : @orby.Window
  runtime : &@runtime.WebViewRuntime
}

///|
fn DesktopApp::teardown(self : DesktopApp) -> Unit {
  if self.shutting_down {
    return
  }
  self.shutting_down = true
  self.plugins.shutdown()
  for mounted in self.windows {
    mounted.runtime.set_message_handler(None) catch {
      _ => ()
    }
    mounted.runtime.destroy() catch {
      _ => ()
    }
  }
  for mounted in self.windows {
    mounted.window.destroy()
  }
  self.windows.clear()
}

///|
fn DesktopApp::dispatch_ipc_message(
  self : DesktopApp,
  label : String,
  runtime : &@runtime.WebViewRuntime,
  message : String,
) -> Unit {
  self.emit_event(
    "orbit://ipc/request",
    Ipc(label),
    Window(label),
    Json::string(message),
  )
  match (self.options.ipc_registry, self.options.ipc_policy) {
    (Some(registry), Some(policy)) => {
      let response = registry.dispatch_for_window(message, policy, label)
      self.emit_event(
        "orbit://ipc/response",
        Ipc(label),
        Window(label),
        Json::string(response),
      )
      runtime.post_message(response) catch {
        error =>
          if !self.shutting_down && self.pending_runtime_failure is None {
            self.pending_runtime_failure = Some(runtime_reason(error))
          }
      }
    }
    _ => ()
  }
}

///|
fn DesktopApp::emit_event(
  self : DesktopApp,
  name : String,
  source : @event.EventTarget,
  target : @event.EventTarget,
  payload : Json,
) -> Unit {
  match self.options.event_router {
    Some(router) => {
      let event = @event.EventEnvelope::new(
        name=@event.EventName::new(name) catch { _ => return },
        payload~,
        source~,
        target~,
      )
      ignore((router as &@event.EventSink).emit(event))
    }
    None => ()
  }
}

///|
fn DesktopApp::mounted_window(
  self : DesktopApp,
  id : @orby.WindowId,
) -> MountedWindow? {
  for mounted in self.windows {
    if mounted.window.id() == id {
      return Some(mounted)
    }
  }
  None
}

///|
fn DesktopApp::has_live_windows(self : DesktopApp) -> Bool {
  self.windows.any(mounted => !mounted.window.is_destroyed())
}

///|
fn DesktopApp::mount_window(
  self : DesktopApp,
  active : @orby.ActiveApp,
  options : DesktopWindowOptions,
) -> MountedWindow raise CoreError {
  let bounds = options.runtime_options.bounds
  let window = active.create_window(
    @orby.WindowOptions::new(
      title=options.window_title,
      size=@orby.Size::new(width=bounds.width, height=bounds.height),
      visible=options.runtime_options.visible,
      resizable=options.resizable,
    ),
  ) catch {
    error => raise StartupFailed(window_reason(error))
  }
  let host = window.webview_host() catch {
    error => {
      window.destroy()
      raise StartupFailed(window_reason(error))
    }
  }
  let native_handle = host.native_handle() catch {
    error => {
      window.destroy()
      raise StartupFailed(window_reason(error))
    }
  }
  let runtime_host = @runtime.RuntimeHost::new(native_handle) catch {
    InvalidState(message) => {
      window.destroy()
      raise StartupFailed(message)
    }
    _ => raise StartupFailed("runtime host creation failed")
  }
  let runtime_options = match self.options.ipc_registry {
    Some(_) =>
      options.runtime_options.with_initialization_script(
        ipc_initialization_script(options.runtime_options.initialization_script),
      )
    None => options.runtime_options
  }
  let supplied_lifecycle_handler = runtime_options.lifecycle_handler()
  let runtime_options = runtime_options.with_lifecycle_handler(event => {
    supplied_lifecycle_handler(event)
    self.record_runtime_event(options.runtime_options.label(), event)
  })
  let runtime = self.factory.create(runtime_host, runtime_options) catch {
    error => {
      window.destroy()
      raise StartupFailed(runtime_reason(error))
    }
  }
  match self.options.ipc_registry {
    Some(_) =>
      runtime.set_message_handler(
        Some(message => {
          self.dispatch_ipc_message(
            options.runtime_options.label(),
            runtime,
            message,
          )
        }),
      ) catch {
        error => {
          runtime.destroy() catch {
            _ => ()
          }
          window.destroy()
          raise StartupFailed(runtime_reason(error))
        }
      }
    None => ()
  }
  { window, runtime }
}

///|
fn DesktopApp::record_runtime_event(
  self : DesktopApp,
  label : String,
  event : @runtime.RuntimeLifecycleEvent,
) -> Unit {
  let payload = match event {
    Ready => Json::string("ready")
    Destroyed => Json::string("destroyed")
    Failed(_) => Json::string("failed")
  }
  self.emit_event(
    "orbit://runtime/lifecycle",
    Runtime(label),
    Window(label),
    payload,
  )
  match event {
    Failed(error) =>
      if !self.shutting_down && self.pending_runtime_failure is None {
        self.pending_runtime_failure = Some(runtime_reason(error))
      }
    _ => ()
  }
}

///|
pub impl @orby.App for DesktopApp with fn started(self, active) {
  for options in self.options.windows {
    let mounted = self.mount_window(active, options) catch {
      error => {
        self.teardown()
        match error {
          InitializationFailed(message)
          | StartupFailed(message)
          | RuntimeFailed(message) => raise StartupFailed(message)
        }
      }
    }
    self.windows.push(mounted)
  }
  if !self.options.plugin_declarations.is_empty() {
    match
      self.plugins.start(
        self.options.plugin_declarations,
        development_directory=self.options.plugin_development_directory,
      ) {
      Err(_) => {
        self.teardown()
        raise StartupFailed("plugin activation failed")
      }
      Ok(_) => ()
    }
    match self.options.ipc_registry {
      Some(registry) =>
        match self.plugins.register_ipc(registry) {
          Err(_) => {
            self.teardown()
            raise StartupFailed("plugin IPC registration failed")
          }
          Ok(_) => ()
        }
      None => {
        self.teardown()
        raise StartupFailed("plugins require an IPC registry")
      }
    }
  }
}

///|
pub impl @orby.App for DesktopApp with fn window_event(self, active, id, event) {
  let mounted = match self.mounted_window(id) {
    Some(mounted) => mounted
    None => return
  }
  if mounted.window.is_destroyed() {
    match event {
      Destroyed => if !self.has_live_windows() { active.exit() }
      _ => ()
    }
    return
  }
  match event {
    Resized(size) =>
      if size.width > 0 && size.height > 0 {
        try
          @runtime.RuntimeBounds::new(width=size.width, height=size.height)
        catch {
          _ => ()
        } noraise {
          bounds => mounted.runtime.set_bounds(bounds) catch { _ => () }
        }
      }
    CloseRequested => {
      mounted.runtime.set_message_handler(None) catch {
        _ => ()
      }
      mounted.runtime.destroy() catch {
        _ => ()
      }
      mounted.window.destroy()
    }
    Destroyed => {
      mounted.runtime.set_message_handler(None) catch {
        _ => ()
      }
      mounted.runtime.destroy() catch {
        _ => ()
      }
      if !self.has_live_windows() {
        active.exit()
      }
    }
    _ => ()
  }
}

///|
pub impl @orby.App for DesktopApp with fn about_to_wait(self, active) {
  match self.pending_runtime_failure {
    Some(reason) => {
      self.pending_runtime_failure = None
      self.teardown()
      active.fail(reason)
    }
    None => ()
  }
}

///|
pub impl @orby.App for DesktopApp with fn exiting(self, _active) {
  self.teardown()
}

///|
pub fn run(
  factory : &@runtime.RuntimeFactory,
  options : DesktopOptions,
) -> Int raise CoreError {
  let event_loop = @orby.EventLoop::new() catch {
    error => raise InitializationFailed(init_reason(error))
  }
  let app = {
    factory,
    options,
    windows: [],
    plugins: @plugin.PluginRuntime::new(),
    pending_runtime_failure: None,
    shutting_down: false,
  }
  event_loop.run_app(app) catch {
    error => raise app_reason(error)
  }
}
