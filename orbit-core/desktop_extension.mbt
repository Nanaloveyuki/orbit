///|
pub(all) suberror DesktopControllerError {
  WindowUnavailable(String)
  HostUnavailable
  RuntimeOperationFailed(String)
} derive(Debug)

///|
pub enum DesktopCloseAction {
  Destroy
  Hide
  /// Hides the top-level window and releases its embedded WebView runtime.
  /// Showing the window creates a fresh runtime using its original options.
  Suspend
} derive(Eq, Debug)

///|
pub fn DesktopCloseAction::destroy() -> DesktopCloseAction {
  Destroy
}

///|
pub fn DesktopCloseAction::hide() -> DesktopCloseAction {
  Hide
}

///|
pub fn DesktopCloseAction::suspend() -> DesktopCloseAction {
  Suspend
}

///|
pub struct DesktopController {
  priv show_window : (String) -> Result[Unit, DesktopControllerError]
  priv hide_window : (String) -> Result[Unit, DesktopControllerError]
  priv focus_window : (String) -> Result[Unit, DesktopControllerError]
  priv suspend_window : (String) -> Result[Unit, DesktopControllerError]
  priv exit_application : () -> Result[Unit, DesktopControllerError]
}

///|
pub fn DesktopController::show_window(
  self : DesktopController,
  label : String,
) -> Unit raise DesktopControllerError {
  match (self.show_window)(label) {
    Ok(_) => ()
    Err(error) => raise error
  }
}

///|
pub fn DesktopController::hide_window(
  self : DesktopController,
  label : String,
) -> Unit raise DesktopControllerError {
  match (self.hide_window)(label) {
    Ok(_) => ()
    Err(error) => raise error
  }
}

///|
pub fn DesktopController::focus_window(
  self : DesktopController,
  label : String,
) -> Unit raise DesktopControllerError {
  match (self.focus_window)(label) {
    Ok(_) => ()
    Err(error) => raise error
  }
}

///|
/// Hides `label` and releases its embedded runtime. The window and application
/// remain alive, and a later `show_window` recreates the runtime.
pub fn DesktopController::suspend_window(
  self : DesktopController,
  label : String,
) -> Unit raise DesktopControllerError {
  match (self.suspend_window)(label) {
    Ok(_) => ()
    Err(error) => raise error
  }
}

///|
pub fn DesktopController::exit(
  self : DesktopController,
) -> Unit raise DesktopControllerError {
  match (self.exit_application)() {
    Ok(_) => ()
    Err(error) => raise error
  }
}

///|
pub struct DesktopUiContext {
  priv label_ : String
  priv show_dialog : (@runtime.RuntimeFileDialogOptions) -> Result[
    @runtime.RuntimeFileDialogResult,
    @runtime.RuntimeError,
  ]
}

///|
pub fn DesktopUiContext::label(self : DesktopUiContext) -> String {
  self.label_
}

///|
pub fn DesktopUiContext::show_file_dialog(
  self : DesktopUiContext,
  options : @runtime.RuntimeFileDialogOptions,
) -> @runtime.RuntimeFileDialogResult raise @runtime.RuntimeError {
  match (self.show_dialog)(options) {
    Ok(result) => result
    Err(error) => raise error
  }
}

///|
pub struct DesktopAsyncContext {
  priv label_ : String
  priv cancellation_ : @ipc.InvocationCancellation
}

///|
pub fn DesktopAsyncContext::label(self : DesktopAsyncContext) -> String {
  self.label_
}

///|
pub fn DesktopAsyncContext::is_cancelled(self : DesktopAsyncContext) -> Bool {
  self.cancellation_.is_cancelled()
}

///|
priv enum DesktopCommandHandler {
  Ui((DesktopUiContext, Json) -> Result[Json, @ipc.CommandFailure])
  Async(async (DesktopAsyncContext, Json) -> Result[Json, @ipc.CommandFailure])
}

///|
pub struct DesktopCommand {
  priv name_ : @ipc.CommandName
  priv handler : DesktopCommandHandler
}

///|
pub fn DesktopCommand::ui(
  name : String,
  handler : (DesktopUiContext, Json) -> Result[Json, @ipc.CommandFailure],
) -> DesktopCommand raise CoreError {
  let name = @ipc.CommandName::new(name) catch {
    _ => raise InitializationFailed("desktop extension command name is invalid")
  }
  { name_: name, handler: Ui(handler) }
}

///|
pub fn DesktopCommand::async_command(
  name : String,
  handler : async (DesktopAsyncContext, Json) -> Result[
    Json,
    @ipc.CommandFailure,
  ],
) -> DesktopCommand raise CoreError {
  let name = @ipc.CommandName::new(name) catch {
    _ => raise InitializationFailed("desktop extension command name is invalid")
  }
  { name_: name, handler: Async(handler) }
}

///|
pub fn DesktopCommand::name(self : DesktopCommand) -> @ipc.CommandName {
  self.name_
}

///|
fn DesktopCommand::is_ui_synchronous(self : DesktopCommand) -> Bool {
  match self.handler {
    Ui(_) => true
    Async(_) => false
  }
}

///|
pub(open) trait DesktopExtension {
  fn identifier(Self) -> String
  fn commands(Self) -> Array[DesktopCommand]
  fn start(Self, DesktopController) -> Result[Unit, String]
  fn poll(Self, DesktopController) -> Result[Unit, String]
  /// Called before a live window's embedded runtime is released. The native
  /// window remains alive and may later receive a fresh runtime.
  fn window_suspended(Self, String) -> Result[Unit, String]
  fn window_destroyed(Self, String) -> Result[Unit, String]
  fn shutdown(Self) -> Result[Unit, String]
}
