///|
using @core {trait DesktopExtension}

///|
pub struct DesktopFileExtension {
  files : @file.FileCapabilityRegistry
}

///|
pub fn DesktopFileExtension::new() -> DesktopFileExtension {
  { files: @file.FileCapabilityRegistry::new() }
}

///|
pub fn DesktopFileExtension::as_extension(
  self : DesktopFileExtension,
) -> &@core.DesktopExtension {
  self as &@core.DesktopExtension
}

///|
fn invalid_payload() -> @ipc.CommandFailure {
  @ipc.CommandFailure::new(
    code="invalid_payload",
    message="file command payload is invalid",
  )
}

///|
fn file_dialog_command(
  extension : DesktopFileExtension,
  kind : @runtime.RuntimeFileDialogKind,
) -> @core.DesktopCommand {
  @core.DesktopCommand::ui(dialog_command(kind), fn(ui, payload) {
    let request : FileDialogRequest = @json.from_json(payload) catch {
      _ => return Err(invalid_payload())
    }
    match show_file_dialog(extension.files, ui, kind, request) {
      Ok(response) => Ok(ToJson::to_json(response))
      Err(failure) => Err(failure)
    }
  }) catch {
    _ => abort("invalid built-in file dialog command")
  }
}

///|
impl DesktopExtension for DesktopFileExtension with fn identifier(self) {
  ignore(self)
  "orbit.desktop.file"
}

///|
impl DesktopExtension for DesktopFileExtension with fn commands(self) {
  [
    file_dialog_command(self, OpenFile),
    file_dialog_command(self, OpenFiles),
    file_dialog_command(self, SaveFile),
    file_dialog_command(self, PickDirectory),
    @core.DesktopCommand::async_command("orbit.fs.read_binary", async fn(
      context,
      payload,
    ) {
      let request : FileReadRequest = @json.from_json(payload) catch {
        _ => return Err(invalid_payload())
      }
      match read_binary_capability(self.files, context, request) {
        Ok(response) => Ok(ToJson::to_json(response))
        Err(failure) => Err(failure)
      }
    }) catch {
      _ => abort("invalid built-in file command")
    },
    @core.DesktopCommand::async_command("orbit.fs.read_text", async fn(
      context,
      payload,
    ) {
      let request : FileReadRequest = @json.from_json(payload) catch {
        _ => return Err(invalid_payload())
      }
      match read_text_capability(self.files, context, request) {
        Ok(response) => Ok(ToJson::to_json(response))
        Err(failure) => Err(failure)
      }
    }) catch {
      _ => abort("invalid built-in file command")
    },
    @core.DesktopCommand::async_command("orbit.fs.write_text", async fn(
      context,
      payload,
    ) {
      let request : FileWriteRequest = @json.from_json(payload) catch {
        _ => return Err(invalid_payload())
      }
      match write_text_capability(self.files, context, request) {
        Ok(response) => Ok(ToJson::to_json(response))
        Err(failure) => Err(failure)
      }
    }) catch {
      _ => abort("invalid built-in file command")
    },
    @core.DesktopCommand::async_command("orbit.fs.read_directory", async fn(
      context,
      payload,
    ) {
      let request : FileDirectoryReadRequest = @json.from_json(payload) catch {
        _ => return Err(invalid_payload())
      }
      match read_directory_capability(self.files, context, request) {
        Ok(response) => Ok(ToJson::to_json(response))
        Err(failure) => Err(failure)
      }
    }) catch {
      _ => abort("invalid built-in file command")
    },
  ]
}

///|
impl DesktopExtension for DesktopFileExtension with fn start(_self, _controller) {
  Ok(())
}

///|
impl DesktopExtension for DesktopFileExtension with fn poll(_self, _controller) {
  Ok(())
}

///|
impl DesktopExtension for DesktopFileExtension with fn window_destroyed(
  self,
  label,
) {
  self.files.revoke_window(label)
  Ok(())
}

///|
impl DesktopExtension for DesktopFileExtension with fn shutdown(self) {
  self.files.clear()
  Ok(())
}
