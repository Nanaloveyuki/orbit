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
fn show_file_dialog(
  files : @file.FileCapabilityRegistry,
  ui : @core.DesktopUiContext,
  kind : @runtime.RuntimeFileDialogKind,
  request : FileDialogRequest,
) -> Result[FileDialogResponse, @ipc.CommandFailure] {
  let label = ui.label()
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
    match ui.show_file_dialog(options) {
      @runtime.RuntimeFileDialogResult::Cancelled =>
        Ok({ cancelled: true, files: [] })
      @runtime.RuntimeFileDialogResult::Selected(paths) => {
        let selected_files : Array[FileDialogFileResponse] = []
        let file_kind = dialog_file_kind(kind)
        for path in paths {
          let capability_result = match file_kind {
            Directory => files.mint_directory(label, path)
            Read | Write => files.mint(label, path, file_kind)
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
          selected_files.push({
            id: capability.id(),
            name: capability.name(),
            kind: dialog_file_kind_name(file_kind),
          })
        }
        Ok({ cancelled: false, files: selected_files })
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
