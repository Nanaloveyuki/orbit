///|
priv struct FileDialogFilterPayload {
  name : String
  extensions : Array[String]
} derive(FromJson)

///|
priv struct FileDialogRequest {
  title : String?
  filters : Array[FileDialogFilterPayload]?
  default_name : String?
  initial_directory : String?
} derive(FromJson)

///|
priv struct FileDialogFileResponse {
  id : String
  name : String
  kind : String
} derive(ToJson)

///|
priv struct FileDialogResponse {
  cancelled : Bool
  files : Array[FileDialogFileResponse]
} derive(ToJson)

///|
fn dialog_command(kind : @runtime.RuntimeFileDialogKind) -> String {
  match kind {
    OpenFile => "orbit.dialog.open"
    OpenFiles => "orbit.dialog.open_multiple"
    SaveFile => "orbit.dialog.save"
    PickDirectory => "orbit.dialog.pick_directory"
  }
}

///|
fn dialog_file_kind(
  kind : @runtime.RuntimeFileDialogKind,
) -> @file.FileCapabilityKind {
  match kind {
    SaveFile => Write
    PickDirectory => Directory
    OpenFile | OpenFiles => Read
  }
}

///|
fn dialog_file_kind_name(kind : @file.FileCapabilityKind) -> String {
  match kind {
    Read => "file"
    Write => "file"
    Directory => "directory"
  }
}

///|
fn is_dialog_command(command : @ipc.CommandName) -> Bool {
  command.value() == "orbit.dialog.open" ||
  command.value() == "orbit.dialog.open_multiple" ||
  command.value() == "orbit.dialog.save" ||
  command.value() == "orbit.dialog.pick_directory"
}

///|
fn DesktopApp::runtime_for_label(
  self : DesktopApp,
  label : String,
) -> &@runtime.WebViewRuntime? {
  for mounted in self.windows {
    if mounted.label == label && !mounted.window.is_destroyed() {
      return Some(mounted.runtime)
    }
  }
  None
}

///|
fn DesktopApp::show_file_dialog(
  self : DesktopApp,
  context : @ipc.InvocationContext,
  kind : @runtime.RuntimeFileDialogKind,
  request : FileDialogRequest,
) -> Result[FileDialogResponse, @ipc.CommandFailure] {
  let label = match context.principal() {
    Window(label) => label
    _ =>
      return Err(
        @ipc.CommandFailure::new(
          code="dialog_unavailable",
          message="file dialogs require a local window",
        ),
      )
  }
  let runtime = match self.runtime_for_label(label) {
    Some(runtime) => runtime
    None =>
      return Err(
        @ipc.CommandFailure::new(
          code="dialog_unavailable",
          message="window is unavailable",
        ),
      )
  }
  let options = @runtime.RuntimeFileDialogOptions::new(
    kind~,
    title=request.title,
    filters=request.filters
      .unwrap_or([])
      .map(filter => {
        @runtime.RuntimeFileDialogFilter::new(
          name=filter.name,
          extensions=filter.extensions,
        )
      }),
    default_name=request.default_name,
    initial_directory=request.initial_directory,
  )
  try {
    match runtime.show_file_dialog(options) {
      @runtime.RuntimeFileDialogResult::Cancelled =>
        Ok({ cancelled: true, files: [] })
      @runtime.RuntimeFileDialogResult::Selected(paths) => {
        let files : Array[FileDialogFileResponse] = []
        let file_kind = dialog_file_kind(kind)
        for path in paths {
          let capability_result = match file_kind {
            Directory => self.files.mint_directory(label, path)
            Read | Write => self.files.mint(label, path, file_kind)
          }
          let capability = match capability_result {
            Ok(capability) => capability
            Err(_) =>
              return Err(
                @ipc.CommandFailure::new(
                  code="handle_unavailable",
                  message="could not create a file capability",
                ),
              )
          }
          files.push({
            id: capability.id(),
            name: capability.name(),
            kind: dialog_file_kind_name(file_kind),
          })
        }
        Ok({ cancelled: false, files })
      }
    }
  } catch {
    Unsupported(_) =>
      Err(
        @ipc.CommandFailure::new(
          code="dialog_unsupported",
          message="native file dialogs are unavailable",
        ),
      )
    _ =>
      Err(
        @ipc.CommandFailure::new(
          code="dialog_failed",
          message="native file dialog failed",
        ),
      )
  }
}

///|
fn DesktopApp::register_file_dialog_commands(
  self : DesktopApp,
) -> Result[Unit, String] {
  match self.options.ipc_registry {
    None => Ok(())
    Some(registry) => {
      for
        kind in [
          @runtime.RuntimeFileDialogKind::OpenFile,
          @runtime.RuntimeFileDialogKind::OpenFiles,
          @runtime.RuntimeFileDialogKind::SaveFile,
          @runtime.RuntimeFileDialogKind::PickDirectory,
        ] {
        let name = @ipc.CommandName::new(dialog_command(kind)) catch {
          _ => return Err("invalid built-in dialog command")
        }
        registry.register_context(name, fn(context, request) {
          self.show_file_dialog(context, kind, request)
        }) catch {
          _ => return Err("file dialog command is already registered")
        }
      }
      Ok(())
    }
  }
}
