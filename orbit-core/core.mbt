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
  extensions : Array[&DesktopExtension]
  close_request_handler : ((String, DesktopController) -> DesktopCloseAction)?
  runtime_suspend_handler : ((String) -> Result[Unit, String])?
  diagnostic_sink : &@diagnostics.DiagnosticSink?
  diagnostic_configuration_fingerprint : String?
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
  extensions? : Array[&DesktopExtension] = [],
  close_request_handler? : ((String, DesktopController) -> DesktopCloseAction)? = None,
  runtime_suspend_handler? : ((String) -> Result[Unit, String])? = None,
  diagnostic_sink? : &@diagnostics.DiagnosticSink? = None,
  diagnostic_configuration_fingerprint? : String? = None,
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
    extensions,
    close_request_handler,
    runtime_suspend_handler,
    diagnostic_sink,
    diagnostic_configuration_fingerprint,
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
    AlreadyActive => "another Orby event loop is already active"
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
  started_extensions : Array[&DesktopExtension]
  mut active : @orby.ActiveApp?
  async_exit : AsyncExit?
  async_ipc : AsyncIpcDispatcher?
  mut pending_runtime_failure : String?
  mut teardown_failure : String?
  mut shutting_down : Bool
}

///|
priv struct MountedWindow {
  label : String
  options : DesktopWindowOptions
  window : @orby.Window
  runtime : Ref[&@runtime.WebViewRuntime?]
  page_event_subscription : Ref[@event.EventSubscription?]
  extension_window_destroyed : Ref[Bool]
}

///|
priv struct MountedRuntime {
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
  match (self.options.event_router, mounted.page_event_subscription.val) {
    (Some(router), Some(subscription)) => {
      router.unsubscribe_additional(subscription)
      mounted.page_event_subscription.val = None
    }
    _ => ()
  }
}

///|
fn DesktopApp::teardown(self : DesktopApp) -> Unit {
  if self.shutting_down {
    return
  }
  self.record_diagnostic(@diagnostics.DesktopStopping, @diagnostics.Info, None)
  self.shutting_down = true
  match self.async_ipc {
    Some(dispatcher) => dispatcher.cancel_all()
    None => ()
  }
  match self.plugins.shutdown() {
    Err(_) => self.teardown_failure = Some("plugin shutdown failed")
    Ok(_) => ()
  }
  for mounted in self.windows {
    self.notify_window_destroyed(mounted)
  }
  self.shutdown_extensions()
  for mounted in self.windows {
    self.unsubscribe_page_events(mounted)
  }
  for mounted in self.windows {
    match mounted.runtime.val {
      Some(runtime) => {
        runtime.set_message_handler(None) catch {
          _ => ()
        }
        runtime.destroy() catch {
          _ => ()
        }
        mounted.runtime.val = None
      }
      None => ()
    }
  }
  for mounted in self.windows {
    mounted.window.destroy()
  }
  self.windows.clear()
}

///|
fn DesktopApp::record_diagnostic(
  self : DesktopApp,
  kind : @diagnostics.DiagnosticKind,
  level : @diagnostics.DiagnosticLevel,
  window_label : String?,
) -> Unit {
  match self.options.diagnostic_sink {
    Some(sink) =>
      sink.record(
        @diagnostics.DiagnosticEvent::new(
          kind,
          level~,
          window_label~,
          configuration_fingerprint=self.options.diagnostic_configuration_fingerprint,
        ),
      )
    None => ()
  }
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
              if is_window_print_command(request.command()) ||
                self.is_ui_synchronous_extension_command(request.command()) {
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
fn DesktopApp::controller(self : DesktopApp) -> DesktopController {
  {
    show_window: label => {
      match self.mounted_for_label(label) {
        Some(mounted) if !mounted.window.is_destroyed() =>
          match self.resume_window_runtime(mounted) {
            Ok(_) => {
              match mounted.runtime.val {
                Some(runtime) =>
                  runtime.set_visible(true) catch {
                    error =>
                      return Err(RuntimeOperationFailed(runtime_reason(error)))
                  }
                None => ()
              }
              mounted.window.set_visible(true)
              Ok(())
            }
            Err(reason) => Err(RuntimeOperationFailed(reason))
          }
        _ => Err(WindowUnavailable(label))
      }
    },
    hide_window: label => {
      match self.mounted_for_label(label) {
        Some(mounted) if !mounted.window.is_destroyed() => {
          mounted.window.set_visible(false)
          Ok(())
        }
        _ => Err(WindowUnavailable(label))
      }
    },
    focus_window: label => {
      match self.mounted_for_label(label) {
        Some(mounted) if !mounted.window.is_destroyed() => {
          mounted.window.focus()
          Ok(())
        }
        _ => Err(WindowUnavailable(label))
      }
    },
    suspend_window: label => {
      match self.mounted_for_label(label) {
        Some(mounted) if !mounted.window.is_destroyed() =>
          match self.suspend_window_runtime(mounted) {
            Ok(_) => {
              mounted.window.set_visible(false)
              Ok(())
            }
            Err(reason) => Err(RuntimeOperationFailed(reason))
          }
        _ => Err(WindowUnavailable(label))
      }
    },
    exit_application: () => {
      match self.active {
        Some(active) => {
          active.exit()
          Ok(())
        }
        None => Err(HostUnavailable)
      }
    },
  }
}

///|
fn DesktopApp::mounted_for_label(
  self : DesktopApp,
  label : String,
) -> MountedWindow? {
  for mounted in self.windows {
    if mounted.label == label {
      return Some(mounted)
    }
  }
  None
}

///|
fn DesktopApp::runtime_for_label(
  self : DesktopApp,
  label : String,
) -> &@runtime.WebViewRuntime? {
  match self.mounted_for_label(label) {
    Some(mounted) if !mounted.window.is_destroyed() => mounted.runtime.val
    _ => None
  }
}

///|
fn DesktopApp::ui_context(
  self : DesktopApp,
  label : String,
) -> DesktopUiContext? {
  match self.mounted_for_label(label) {
    Some(mounted) if !mounted.window.is_destroyed() =>
      match mounted.runtime.val {
        Some(runtime) =>
          Some({
            label_: label,
            show_dialog: options => {
              Ok(runtime.show_file_dialog(options)) catch {
                error => Err(error)
              }
            },
          })
        None => None
      }
    _ => None
  }
}

///|
fn DesktopApp::validate_extensions(self : DesktopApp) -> Result[Unit, String] {
  let identifiers : Map[String, Bool] = Map([])
  let commands : Map[String, Bool] = Map([])
  for extension in self.options.extensions {
    let identifier = extension.identifier()
    if identifier.trim().is_empty() {
      return Err("desktop extension identifier must not be empty")
    }
    if identifiers.contains(identifier) {
      return Err("duplicate desktop extension: \{identifier}")
    }
    identifiers[identifier] = true
    for command in extension.commands() {
      let name = command.name().value()
      if name == "orbit.window.print" {
        return Err(
          "desktop extension command conflicts with built-in print command",
        )
      }
      if commands.contains(name) {
        return Err("duplicate desktop extension command: \{name}")
      }
      commands[name] = true
      match self.options.ipc_registry {
        Some(registry) if registry.contains(command.name()) =>
          return Err("desktop extension command is already registered: \{name}")
        _ => ()
      }
    }
  }
  if !commands.is_empty() {
    match (self.options.ipc_registry, self.options.ipc_policy) {
      (Some(_), Some(_)) => ()
      _ =>
        return Err(
          "desktop extension commands require an IPC registry and command policy",
        )
    }
  }
  Ok(())
}

///|
fn DesktopApp::start_extensions(self : DesktopApp) -> Result[Unit, String] {
  for extension in self.options.extensions {
    match extension.start(self.controller()) {
      Ok(_) => self.started_extensions.push(extension)
      Err(reason) => {
        self.record_diagnostic(
          @diagnostics.ExtensionStartFailed,
          @diagnostics.Error,
          None,
        )
        return Err(
          "desktop extension \{extension.identifier()} failed to start: \{reason}",
        )
      }
    }
  }
  Ok(())
}

///|
fn DesktopApp::shutdown_extensions(self : DesktopApp) -> Unit {
  for extension in self.started_extensions.rev() {
    match extension.shutdown() {
      Err(reason) if self.teardown_failure is None => {
        self.record_diagnostic(
          @diagnostics.ExtensionShutdownFailed,
          @diagnostics.Warning,
          None,
        )
        self.teardown_failure = Some(
          "desktop extension \{extension.identifier()} shutdown failed: \{reason}",
        )
      }
      _ => ()
    }
  }
  self.started_extensions.clear()
}

///|
fn DesktopApp::notify_window_destroyed(
  self : DesktopApp,
  mounted : MountedWindow,
) -> Unit {
  if mounted.extension_window_destroyed.val {
    return
  }
  mounted.extension_window_destroyed.val = true
  for extension in self.started_extensions {
    match extension.window_destroyed(mounted.label) {
      Err(reason) if self.teardown_failure is None =>
        self.teardown_failure = Some(
          "desktop extension \{extension.identifier()} window cleanup failed: \{reason}",
        )
      _ => ()
    }
  }
}

///|
fn DesktopApp::notify_window_suspended(
  self : DesktopApp,
  mounted : MountedWindow,
) -> Result[Unit, String] {
  for extension in self.started_extensions {
    match extension.window_suspended(mounted.label) {
      Err(reason) =>
        return Err(
          "desktop extension \{extension.identifier()} suspend failed: \{reason}",
        )
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
fn prepare_runtime_suspension(
  handler : ((String) -> Result[Unit, String])?,
  label : String,
) -> Result[Unit, String] {
  match handler {
    Some(handler) =>
      match handler(label) {
        Ok(_) => Ok(())
        Err(reason) => Err("runtime suspension preparation failed: \{reason}")
      }
    None => Ok(())
  }
}

///|
fn DesktopApp::suspend_window_runtime(
  self : DesktopApp,
  mounted : MountedWindow,
) -> Result[Unit, String] {
  let runtime = match mounted.runtime.val {
    Some(runtime) => runtime
    None => return Ok(())
  }
  match
    prepare_runtime_suspension(
      self.options.runtime_suspend_handler,
      mounted.label,
    ) {
    Err(reason) => {
      self.record_diagnostic(
        @diagnostics.RuntimeSuspendFailed,
        @diagnostics.Error,
        Some(mounted.label),
      )
      return Err(reason)
    }
    Ok(_) => ()
  }
  match self.notify_window_suspended(mounted) {
    Err(reason) => {
      self.record_diagnostic(
        @diagnostics.RuntimeSuspendFailed,
        @diagnostics.Error,
        Some(mounted.label),
      )
      return Err(reason)
    }
    Ok(_) => ()
  }
  self.unsubscribe_page_events(mounted)
  runtime.set_message_handler(None) catch {
    _ => ()
  }
  runtime.destroy() catch {
    error => {
      self.record_diagnostic(
        @diagnostics.RuntimeSuspendFailed,
        @diagnostics.Error,
        Some(mounted.label),
      )
      return Err(runtime_reason(error))
    }
  }
  mounted.runtime.val = None
  self.record_diagnostic(
    @diagnostics.RuntimeSuspended,
    @diagnostics.Info,
    Some(mounted.label),
  )
  Ok(())
}

///|
fn DesktopApp::register_extension_commands(
  self : DesktopApp,
) -> Result[Unit, String] {
  match self.options.ipc_registry {
    None => Ok(())
    Some(registry) => {
      for extension in self.options.extensions {
        for command in extension.commands() {
          match command.handler {
            Ui(handler) =>
              registry.register_context_json(command.name(), fn(
                context,
                payload,
              ) {
                let label = match context.principal() {
                  Window(label) => label
                  _ =>
                    return Err(
                      @ipc.CommandFailure::new(
                        code="desktop_ui_unavailable",
                        message="desktop UI commands require a local window",
                      ),
                    )
                }
                let ui = match self.ui_context(label) {
                  Some(ui) => ui
                  None =>
                    return Err(
                      @ipc.CommandFailure::new(
                        code="desktop_ui_unavailable",
                        message="the local window is unavailable",
                      ),
                    )
                }
                handler(ui, payload)
              }) catch {
                _ => return Err("desktop extension command registration failed")
              }
            Async(handler) =>
              registry.register_async_context_json(command.name(), async fn(
                context,
                payload,
              ) {
                let label = match context.principal() {
                  Window(label) => label
                  _ =>
                    return Err(
                      @ipc.CommandFailure::new(
                        code="desktop_window_unavailable",
                        message="desktop commands require a local window",
                      ),
                    )
                }
                if self.mounted_for_label(label) is None {
                  return Err(
                    @ipc.CommandFailure::new(
                      code="desktop_window_unavailable",
                      message="the local window is unavailable",
                    ),
                  )
                }
                handler(
                  { label_: label, cancellation_: context.cancellation() },
                  payload,
                )
              }) catch {
                _ => return Err("desktop extension command registration failed")
              }
          }
        }
      }
      Ok(())
    }
  }
}

///|
fn DesktopApp::is_ui_synchronous_extension_command(
  self : DesktopApp,
  name : @ipc.CommandName,
) -> Bool {
  self.options.extensions.any(extension => {
    extension
    .commands()
    .any(command => command.name() == name && command.is_ui_synchronous())
  })
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
fn DesktopApp::mount_runtime(
  self : DesktopApp,
  options : DesktopWindowOptions,
  window : @orby.Window,
) -> MountedRuntime raise CoreError {
  let host = window.webview_host() catch {
    error => raise StartupFailed(window_reason(error))
  }
  let native_handle = host.native_handle() catch {
    error => raise StartupFailed(window_reason(error))
  }
  let runtime_host = @runtime.RuntimeHost::new(native_handle) catch {
    InvalidState(message) => raise StartupFailed(message)
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
    error => raise StartupFailed(runtime_reason(error))
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
  { runtime, page_event_subscription }
}

///|
fn core_reason(error : CoreError) -> String {
  match error {
    InitializationFailed(message)
    | StartupFailed(message)
    | RuntimeFailed(message) => message
  }
}

///|
fn DesktopApp::resume_window_runtime(
  self : DesktopApp,
  mounted : MountedWindow,
) -> Result[Unit, String] {
  if mounted.runtime.val is Some(_) {
    return Ok(())
  }
  let runtime = self.mount_runtime(mounted.options, mounted.window) catch {
    error => {
      self.record_diagnostic(
        @diagnostics.RuntimeResumeFailed,
        @diagnostics.Error,
        Some(mounted.label),
      )
      return Err(core_reason(error))
    }
  }
  runtime.runtime.set_visible(true) catch {
    error => {
      runtime.runtime.destroy() catch {
        _ => ()
      }
      self.record_diagnostic(
        @diagnostics.RuntimeResumeFailed,
        @diagnostics.Error,
        Some(mounted.label),
      )
      return Err(runtime_reason(error))
    }
  }
  mounted.runtime.val = Some(runtime.runtime)
  mounted.page_event_subscription.val = runtime.page_event_subscription
  self.record_diagnostic(
    @diagnostics.RuntimeResumed,
    @diagnostics.Info,
    Some(mounted.label),
  )
  Ok(())
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
  let runtime = self.mount_runtime(options, window) catch {
    error => {
      window.destroy()
      raise error
    }
  }
  {
    label: options.runtime_options.label(),
    options,
    window,
    runtime: Ref(Some(runtime.runtime)),
    page_event_subscription: Ref(runtime.page_event_subscription),
    extension_window_destroyed: Ref(false),
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
    Ready =>
      self.record_diagnostic(
        @diagnostics.RuntimeReady,
        @diagnostics.Info,
        Some(label),
      )
    Destroyed =>
      self.record_diagnostic(
        @diagnostics.RuntimeDestroyed,
        @diagnostics.Info,
        Some(label),
      )
    Failed(error) => {
      self.record_diagnostic(
        @diagnostics.RuntimeFailed,
        @diagnostics.Error,
        Some(label),
      )
      if !self.shutting_down && self.pending_runtime_failure is None {
        self.pending_runtime_failure = Some(runtime_reason(error))
      }
    }
  }
}

///|
pub impl @orby.App for DesktopApp with fn started(self, active) {
  self.active = Some(active)
  self.record_diagnostic(@diagnostics.DesktopStarting, @diagnostics.Info, None)
  match self.validate_extensions() {
    Err(reason) => {
      self.record_diagnostic(
        @diagnostics.DesktopStartupFailed,
        @diagnostics.Error,
        None,
      )
      self.teardown()
      raise StartupFailed(reason)
    }
    Ok(_) => ()
  }
  for options in self.options.windows {
    let mounted = self.mount_window(active, options) catch {
      error => {
        self.record_diagnostic(
          @diagnostics.DesktopStartupFailed,
          @diagnostics.Error,
          None,
        )
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
  match self.start_extensions() {
    Err(reason) => {
      self.record_diagnostic(
        @diagnostics.DesktopStartupFailed,
        @diagnostics.Error,
        None,
      )
      self.teardown()
      raise StartupFailed(self.teardown_failure.unwrap_or(reason))
    }
    Ok(_) => ()
  }
  match self.register_extension_commands() {
    Err(reason) => {
      self.record_diagnostic(
        @diagnostics.DesktopStartupFailed,
        @diagnostics.Error,
        None,
      )
      self.teardown()
      raise StartupFailed(self.teardown_failure.unwrap_or(reason))
    }
    Ok(_) => ()
  }
  match self.register_window_commands() {
    Err(reason) => {
      self.record_diagnostic(
        @diagnostics.DesktopStartupFailed,
        @diagnostics.Error,
        None,
      )
      self.teardown()
      raise StartupFailed(reason)
    }
    Ok(_) => ()
  }
  if self.async_exit is None {
    match start_configured_plugins(self.plugins, self.options) {
      Err(reason) => {
        self.record_diagnostic(
          @diagnostics.PluginStartupFailed,
          @diagnostics.Error,
          None,
        )
        self.teardown()
        raise StartupFailed(self.teardown_failure.unwrap_or(reason))
      }
      Ok(_) => ()
    }
  }
  self.record_diagnostic(@diagnostics.DesktopStarted, @diagnostics.Info, None)
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
          bounds =>
            match mounted.runtime.val {
              Some(runtime) => runtime.set_bounds(bounds) catch { _ => () }
              None => ()
            }
        }
      }
    CloseRequested => {
      let action = match self.options.close_request_handler {
        Some(handler) => handler(mounted.label, self.controller())
        None => Destroy
      }
      if action == Hide {
        mounted.window.set_visible(false)
        return
      }
      if action == Suspend {
        match self.suspend_window_runtime(mounted) {
          Ok(_) => mounted.window.set_visible(false)
          Err(reason) =>
            if self.pending_runtime_failure is None {
              self.pending_runtime_failure = Some(
                "window runtime suspension failed: \{reason}",
              )
            }
        }
        return
      }
      self.notify_window_destroyed(mounted)
      self.unsubscribe_page_events(mounted)
      match mounted.runtime.val {
        Some(runtime) => {
          runtime.set_message_handler(None) catch {
            _ => ()
          }
          runtime.destroy() catch {
            _ => ()
          }
          mounted.runtime.val = None
        }
        None => ()
      }
      mounted.window.destroy()
    }
    Destroyed => {
      self.notify_window_destroyed(mounted)
      self.unsubscribe_page_events(mounted)
      match mounted.runtime.val {
        Some(runtime) => {
          runtime.set_message_handler(None) catch {
            _ => ()
          }
          runtime.destroy() catch {
            _ => ()
          }
          mounted.runtime.val = None
        }
        None => ()
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
    for extension in self.started_extensions {
      match extension.poll(self.controller()) {
        Err(reason) => {
          self.record_diagnostic(
            @diagnostics.ExtensionPollFailed,
            @diagnostics.Error,
            None,
          )
          self.pending_runtime_failure = Some(
            "desktop extension \{extension.identifier()} poll failed: \{reason}",
          )
          break
        }
        Ok(_) => ()
      }
    }
    match self.plugins.poll_events() {
      Err(error) => {
        self.record_diagnostic(
          @diagnostics.PluginPollFailed,
          @diagnostics.Error,
          None,
        )
        self.pending_runtime_failure = Some(plugin_start_reason(error))
      }
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
    started_extensions: [],
    active: None,
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
    started_extensions: [],
    active: None,
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
