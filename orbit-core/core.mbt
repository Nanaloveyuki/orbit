///|
pub(all) suberror CoreError {
  InitializationFailed(String)
  StartupFailed(String)
  RuntimeFailed(String)
} derive(Debug)

///|
pub fn ipc_initialization_script(initialization_script : String) -> String {
  @ipc_moonview.initialization_script(initialization_script)
}

///|
pub struct DesktopWindowOptions {
  window_title : String
  runtime_options : @runtime.RuntimeOptions
  resizable : Bool
  ipc_principal : DesktopIpcPrincipal
}

///|
pub enum DesktopIpcPrincipal {
  Window
  RemotePage
} derive(Eq, Debug)

///|
pub fn DesktopIpcPrincipal::window() -> DesktopIpcPrincipal {
  Window
}

///|
pub fn DesktopIpcPrincipal::remote_page() -> DesktopIpcPrincipal {
  RemotePage
}

///|
pub fn DesktopWindowOptions::new(
  window_title : String,
  runtime_options : @runtime.RuntimeOptions,
  resizable? : Bool = true,
  ipc_principal? : DesktopIpcPrincipal = Window,
) -> DesktopWindowOptions raise CoreError {
  if window_title.is_empty() {
    raise InitializationFailed("window title must not be empty")
  }
  { window_title, runtime_options, resizable, ipc_principal }
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
fn resolve_plugin_development_directory(
  configured_directory : String?,
  environment_directory : String?,
) -> String? raise CoreError {
  let directory = match configured_directory {
    Some(directory) => Some(directory)
    None => environment_directory
  }
  match directory {
    Some(directory) if directory.trim().is_empty() =>
      raise InitializationFailed(
        "plugin development directory must not be empty",
      )
    _ => directory
  }
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
  let plugin_development_directory = resolve_plugin_development_directory(
    plugin_development_directory,
    @env.get_env_var("ORBIT_PLUGIN_DIRECTORY"),
  )
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
fn plugin_start_reason(error : @plugin.PluginRuntimeError) -> String {
  match error {
    @plugin.LoadFailure(id, @plugin.AsyncRuntimeRequired) =>
      "plugin requires run_async: \{id}"
    @plugin.LoadFailure(id, @plugin.ExecutorFailed) =>
      "plugin executor failed: \{id}"
    _ => "plugin activation failed"
  }
}

///|
fn start_configured_plugins(
  plugins : @plugin.PluginRuntime,
  options : DesktopOptions,
) -> Result[Unit, String] {
  if options.plugin_declarations.is_empty() {
    return Ok(())
  }
  match
    plugins.start(
      options.plugin_declarations,
      development_directory=options.plugin_development_directory,
    ) {
    Err(error) => return Err(plugin_start_reason(error))
    Ok(_) => ()
  }
  match options.ipc_registry {
    Some(registry) =>
      match plugins.register_ipc(registry) {
        Err(_) => Err("plugin IPC registration failed")
        Ok(_) => Ok(())
      }
    None => Err("plugins require an IPC registry")
  }
}

///|
struct DesktopApp {
  factory : &@runtime.RuntimeFactory
  options : DesktopOptions
  windows : Array[MountedWindow]
  plugins : @plugin.PluginRuntime
  files : @file.FileCapabilityRegistry
  async_exit : AsyncExit?
  async_ipc : AsyncIpcDispatcher?
  mut pending_runtime_failure : String?
  mut teardown_failure : String?
  mut shutting_down : Bool
}

///|
priv struct MountedWindow {
  label : String
  window : @orby.Window
  runtime : &@runtime.WebViewRuntime
  page_event_subscription : @event.EventSubscription?
}

///|
fn deliver_page_event(
  runtime : &@runtime.WebViewRuntime,
  event : @event.EventEnvelope,
) -> Result[Unit, @event.EventDeliveryFailure] {
  match @ipc_moonview.encode_page_event(event) {
    Err(error) => Err(error)
    Ok(message) => {
      runtime.post_message(message) catch {
        error =>
          return Err(
            @event.EventDeliveryFailure::new(
              code="page_event_delivery_failed",
              message=runtime_reason(error),
            ),
          )
      }
      Ok(())
    }
  }
}

///|
fn subscribe_page_events(
  router : @event.EventRouter?,
  label : String,
  principal : DesktopIpcPrincipal,
  runtime : &@runtime.WebViewRuntime,
) -> @event.EventSubscription? {
  match (router, principal) {
    (Some(router), Window) =>
      Some(
        router.subscribe_additional(Window(label), event => {
          deliver_page_event(runtime, event)
        }),
      )
    _ => None
  }
}

///|
fn DesktopApp::unsubscribe_page_events(
  self : DesktopApp,
  mounted : MountedWindow,
) -> Unit {
  match (self.options.event_router, mounted.page_event_subscription) {
    (Some(router), Some(subscription)) =>
      router.unsubscribe_additional(subscription)
    _ => ()
  }
}

///|
fn DesktopApp::teardown(self : DesktopApp) -> Unit {
  if self.shutting_down {
    return
  }
  self.shutting_down = true
  match self.async_ipc {
    Some(dispatcher) => dispatcher.cancel_all()
    None => ()
  }
  for mounted in self.windows {
    self.files.revoke_window(mounted.label)
    self.unsubscribe_page_events(mounted)
  }
  match self.plugins.shutdown() {
    Err(_) => self.teardown_failure = Some("plugin shutdown failed")
    Ok(_) => ()
  }
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
  self.files.clear()
}

///|
fn DesktopApp::deliver_ipc_response(
  self : DesktopApp,
  label : String,
  runtime : &@runtime.WebViewRuntime,
  response : String,
) -> Unit {
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

///|
fn DesktopApp::dispatch_ipc_message(
  self : DesktopApp,
  label : String,
  ipc_principal : DesktopIpcPrincipal,
  runtime : &@runtime.WebViewRuntime,
  page_message : @runtime.RuntimePageMessage,
) -> Unit {
  let message = page_message.body()
  self.emit_event(
    "orbit://ipc/request",
    Ipc(label),
    Window(label),
    Json::string(message),
  )
  match (self.options.ipc_registry, self.options.ipc_policy) {
    (Some(registry), Some(policy)) => {
      let principal = match ipc_principal {
        Window => @ipc_moonview.PagePrincipal::window()
        RemotePage => @ipc_moonview.PagePrincipal::remote_page()
      }
      let context = match
        @ipc_moonview.invocation_context(label, principal, page_message) {
        Some(context) => context
        None => return
      }
      let invocation_scope = match ipc_principal {
        Window => "window\u{0}\{label}"
        RemotePage => {
          let origin = context.origin().unwrap_or("")
          "remote\u{0}\{label}\u{0}\{origin}"
        }
      }
      match self.async_ipc {
        None => {
          let is_cancellation = try (
            @ipc.decode_client_message(message)
            is @ipc.InvocationClientMessage::Cancel(_)
          ) catch {
            _ => false
          }
          if is_cancellation {
            return
          }
          let response = registry.dispatch_with_context(
            message, policy, context,
          )
          self.deliver_ipc_response(label, runtime, response)
        }
        Some(dispatcher) => {
          let client_message = @ipc.decode_client_message(message) catch {
            _ => {
              self.deliver_ipc_response(
                label,
                runtime,
                registry.dispatch_with_context(message, policy, context),
              )
              return
            }
          }
          match client_message {
            @ipc.InvocationClientMessage::Cancel(id) =>
              dispatcher.cancel(invocation_scope, id)
            @ipc.InvocationClientMessage::Invoke(request) =>
              if is_dialog_command(request.command()) {
                self.deliver_ipc_response(
                  label,
                  runtime,
                  registry.dispatch_with_context(message, policy, context),
                )
              } else {
                dispatcher.schedule(
                  invocation_scope,
                  registry,
                  policy,
                  context,
                  request,
                  response => {
                    self.deliver_ipc_response(label, runtime, response)
                  },
                )
              }
          }
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
fn DesktopApp::finish_async_exit(self : DesktopApp) -> Unit {
  match self.async_ipc {
    Some(dispatcher) => dispatcher.cancel_all()
    None => ()
  }
  match self.async_exit {
    Some(exit) => exit.finish()
    None => ()
  }
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
  let page_events_enabled = self.options.event_router is Some(_) &&
    options.ipc_principal == Window
  let runtime_options = match (self.options.ipc_registry, page_events_enabled) {
    (Some(_), _) =>
      options.runtime_options.with_initialization_script(
        @ipc_moonview.initialization_script(
          options.runtime_options.initialization_script,
        ),
      )
    (None, true) =>
      options.runtime_options.with_initialization_script(
        @ipc_moonview.event_initialization_script(
          options.runtime_options.initialization_script,
        ),
      )
    (None, false) => options.runtime_options
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
            options.ipc_principal,
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
  let page_event_subscription = subscribe_page_events(
    self.options.event_router,
    options.runtime_options.label(),
    options.ipc_principal,
    runtime,
  )
  {
    label: options.runtime_options.label(),
    window,
    runtime,
    page_event_subscription,
  }
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
  match self.register_file_dialog_commands() {
    Err(reason) => {
      self.teardown()
      raise StartupFailed(reason)
    }
    Ok(_) => ()
  }
  match self.register_file_read_commands() {
    Err(reason) => {
      self.teardown()
      raise StartupFailed(reason)
    }
    Ok(_) => ()
  }
  if self.async_exit is None {
    match start_configured_plugins(self.plugins, self.options) {
      Err(reason) => {
        self.teardown()
        raise StartupFailed(self.teardown_failure.unwrap_or(reason))
      }
      Ok(_) => ()
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
      Destroyed =>
        if !self.has_live_windows() {
          self.finish_async_exit()
          active.exit()
        }
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
      self.files.revoke_window(mounted.label)
      self.unsubscribe_page_events(mounted)
      mounted.runtime.set_message_handler(None) catch {
        _ => ()
      }
      mounted.runtime.destroy() catch {
        _ => ()
      }
      mounted.window.destroy()
    }
    Destroyed => {
      self.files.revoke_window(mounted.label)
      self.unsubscribe_page_events(mounted)
      mounted.runtime.set_message_handler(None) catch {
        _ => ()
      }
      mounted.runtime.destroy() catch {
        _ => ()
      }
      if !self.has_live_windows() {
        self.finish_async_exit()
        active.exit()
      }
    }
    _ => ()
  }
}

///|
pub impl @orby.App for DesktopApp with fn about_to_wait(self, active) {
  if !self.shutting_down {
    match self.plugins.poll_events() {
      Err(error) =>
        self.pending_runtime_failure = Some(plugin_start_reason(error))
      Ok(_) => ()
    }
  }
  match self.pending_runtime_failure {
    Some(reason) => {
      self.pending_runtime_failure = None
      self.teardown()
      self.finish_async_exit()
      active.fail(self.teardown_failure.unwrap_or(reason))
    }
    None => ()
  }
}

///|
pub impl @orby.App for DesktopApp with fn exiting(self, active) {
  self.teardown()
  self.finish_async_exit()
  match self.teardown_failure {
    Some(reason) => active.fail(reason)
    None => ()
  }
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
    files: @file.FileCapabilityRegistry::new(),
    async_exit: None,
    async_ipc: None,
    pending_runtime_failure: None,
    teardown_failure: None,
    shutting_down: false,
  }
  event_loop.run_app(app) catch {
    error => raise app_reason(error)
  }
}

///|
/// Runs a desktop application with MoonBit async work on Orby's UI thread.
///
/// The existing `run` function remains the synchronous default. `run_async`
/// installs Orby's manually pumped loop before async work starts, so the async
/// poller stays on its own native thread while every MoonBit callback and UI
/// operation remains on the UI thread. After `main` finishes its asynchronous
/// initialization, Orbit keeps the runtime alive until the final window exits.
/// Call it before any other async work or `@async.run_async_main` starts.
pub fn run_async(
  factory : &@runtime.RuntimeFactory,
  options : DesktopOptions,
  main : async () -> Unit,
) -> Unit raise CoreError {
  let event_loop = @orby.EventLoop::new() catch {
    error => raise InitializationFailed(init_reason(error))
  }
  let async_exit = AsyncExit::new()
  let async_ipc = AsyncIpcDispatcher::new()
  let plugins = @plugin.PluginRuntime::new()
  let ipc_registry = options.ipc_registry
  let ipc_policy = options.ipc_policy
  let plugin_options = options
  let startup_failure : Ref[String?] = Ref(None)
  let app = {
    factory,
    options,
    windows: [],
    plugins,
    files: @file.FileCapabilityRegistry::new(),
    async_exit: Some(async_exit),
    async_ipc: Some(async_ipc),
    pending_runtime_failure: None,
    teardown_failure: None,
    shutting_down: false,
  }
  let app_loop = event_loop.start_external_app(app) catch {
    error => raise app_reason(error)
  }
  let wakeup_callback = app_loop.wakeup_callback_for_foreign_thread()
  let loop_control = app_loop
  let loop_failure : Ref[@orby.AppError?] = Ref(None)
  let external_loop = { app_loop, failure: loop_failure }
  @async.set_external_event_loop(external_loop)
  @async.run_async_main(() => {
    @async.with_task_group() <| group => {
      async_ipc.bind(group)
      match (ipc_registry, ipc_policy) {
        (Some(registry), Some(policy)) =>
          plugins.bind_async(group, wakeup_callback, registry, policy)
        _ => ()
      }
      match start_configured_plugins(plugins, plugin_options) {
        Err(reason) => {
          startup_failure.val = Some(reason)
          ignore(
            loop_control.terminate() catch {
              error => {
                loop_failure.val = Some(error)
                0
              }
            },
          )
          return
        }
        Ok(_) => ()
      }
      main()
      async_exit.wait()
    }
  })
  match loop_failure.val {
    Some(error) => raise app_reason(error)
    None => ()
  }
  match startup_failure.val {
    Some(reason) => raise StartupFailed(reason)
    None => ()
  }
}
