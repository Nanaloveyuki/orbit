///|
priv struct WindowPrintRequest {} derive(FromJson)

///|
priv struct WindowPrintResponse {
  opened : Bool
} derive(ToJson)

///|
fn is_window_print_command(command : @ipc.CommandName) -> Bool {
  command.value() == "orbit.window.print"
}

///|
fn DesktopApp::open_window_print_dialog(
  self : DesktopApp,
  context : @ipc.InvocationContext,
  _request : WindowPrintRequest,
) -> Result[WindowPrintResponse, @ipc.CommandFailure] {
  let label = match context.principal() {
    Window(label) => label
    _ =>
      return Err(
        @ipc.CommandFailure::new(
          code="print_unavailable",
          message="printing requires a local window",
        ),
      )
  }
  let runtime = match self.runtime_for_label(label) {
    Some(runtime) => runtime
    None =>
      return Err(
        @ipc.CommandFailure::new(
          code="print_unavailable",
          message="window is unavailable",
        ),
      )
  }
  try {
    runtime.open_print_dialog()
    Ok({ opened: true })
  } catch {
    Unsupported(_) =>
      Err(
        @ipc.CommandFailure::new(
          code="print_unsupported",
          message="native print dialogs are unavailable",
        ),
      )
    _ =>
      Err(
        @ipc.CommandFailure::new(
          code="print_failed",
          message="could not open the native print dialog",
        ),
      )
  }
}

///|
fn DesktopApp::register_window_commands(
  self : DesktopApp,
) -> Result[Unit, String] {
  match self.options.ipc_registry {
    None => Ok(())
    Some(registry) => {
      let name = @ipc.CommandName::new("orbit.window.print") catch {
        _ => return Err("invalid built-in print command")
      }
      registry.register_context(name, fn(context, request) {
        self.open_window_print_dialog(context, request)
      }) catch {
        _ => return Err("print command is already registered")
      }
      Ok(())
    }
  }
}
