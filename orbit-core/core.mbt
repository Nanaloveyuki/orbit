///|
pub(all) suberror CoreError {
  InitializationFailed(String)
  StartupFailed(String)
  RuntimeFailed(String)
} derive(Debug)

///|
pub struct DesktopOptions {
  window_title : String
  runtime_options : @runtime.RuntimeOptions
  resizable : Bool
  ipc_registry : @ipc.CommandRegistry?
  ipc_policy : @ipc.CommandPolicy?
}

///|
pub fn DesktopOptions::new(
  window_title : String,
  runtime_options : @runtime.RuntimeOptions,
  resizable? : Bool = true,
  ipc_registry? : @ipc.CommandRegistry? = None,
  ipc_policy? : @ipc.CommandPolicy? = None,
) -> DesktopOptions raise CoreError {
  if window_title.is_empty() {
    raise InitializationFailed("window title must not be empty")
  }
  match (ipc_registry, ipc_policy) {
    (Some(_), None) | (None, Some(_)) =>
      raise InitializationFailed(
        "IPC registry and command policy must be configured together",
      )
    _ => ()
  }
  { window_title, runtime_options, resizable, ipc_registry, ipc_policy }
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
  mut window : @orby.Window?
  mut runtime : &@runtime.WebViewRuntime?
  mut pending_runtime_failure : String?
  mut shutting_down : Bool
}

///|
fn DesktopApp::teardown(self : DesktopApp) -> Unit {
  if self.shutting_down {
    return
  }
  self.shutting_down = true
  match self.runtime {
    Some(runtime) => {
      self.runtime = None
      runtime.set_message_handler(None) catch {
        _ => ()
      }
      runtime.destroy() catch {
        _ => ()
      }
    }
    None => ()
  }
  match self.window {
    Some(window) => {
      self.window = None
      window.destroy()
    }
    None => ()
  }
}

///|
fn DesktopApp::dispatch_ipc_message(
  self : DesktopApp,
  message : String,
) -> Unit {
  match (self.options.ipc_registry, self.options.ipc_policy, self.runtime) {
    (Some(registry), Some(policy), Some(runtime)) => {
      let response = registry.dispatch_for_window(
        message,
        policy,
        self.options.runtime_options.label(),
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
fn DesktopApp::record_runtime_event(
  self : DesktopApp,
  event : @runtime.RuntimeLifecycleEvent,
) -> Unit {
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
  let bounds = self.options.runtime_options.bounds
  let window = active.create_window(
    @orby.WindowOptions::new(
      title=self.options.window_title,
      size=@orby.Size::new(width=bounds.width, height=bounds.height),
      visible=self.options.runtime_options.visible,
      resizable=self.options.resizable,
    ),
  ) catch {
    error => raise StartupFailed(window_reason(error))
  }
  self.window = Some(window)
  let host = window.webview_host() catch {
    error => {
      self.teardown()
      raise StartupFailed(window_reason(error))
    }
  }
  let native_handle = host.native_handle() catch {
    error => {
      self.teardown()
      raise StartupFailed(window_reason(error))
    }
  }
  let runtime_host = @runtime.RuntimeHost::new(native_handle) catch {
    InvalidState(message) => {
      self.teardown()
      raise StartupFailed(message)
    }
    _ => raise StartupFailed("runtime host creation failed")
  }
  let supplied_lifecycle_handler = self.options.runtime_options.lifecycle_handler()
  let runtime_options = self.options.runtime_options.with_lifecycle_handler(event => {
    supplied_lifecycle_handler(event)
    self.record_runtime_event(event)
  })
  let runtime = self.factory.create(runtime_host, runtime_options) catch {
    error => {
      self.teardown()
      raise StartupFailed(runtime_reason(error))
    }
  }
  self.runtime = Some(runtime)
  match self.options.ipc_registry {
    Some(_) =>
      runtime.set_message_handler(
        Some(message => self.dispatch_ipc_message(message)),
      ) catch {
        error => {
          self.teardown()
          raise StartupFailed(runtime_reason(error))
        }
      }
    None => ()
  }
}

///|
pub impl @orby.App for DesktopApp with fn window_event(self, _active, id, event) {
  let is_primary_window = match self.window {
    Some(window) => window.id() == id
    None => false
  }
  if !is_primary_window {
    return
  }
  match event {
    Resized(size) =>
      if size.width > 0 && size.height > 0 {
        match self.runtime {
          Some(runtime) =>
            try
              @runtime.RuntimeBounds::new(width=size.width, height=size.height)
            catch {
              _ => ()
            } noraise {
              bounds => runtime.set_bounds(bounds) catch { _ => () }
            }
          None => ()
        }
      }
    CloseRequested => self.teardown()
    Destroyed => {
      self.window = None
      match self.runtime {
        Some(runtime) => {
          self.runtime = None
          runtime.destroy() catch {
            _ => ()
          }
        }
        None => ()
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
    window: None,
    runtime: None,
    pending_runtime_failure: None,
    shutting_down: false,
  }
  event_loop.run_app(app) catch {
    error => raise app_reason(error)
  }
}
