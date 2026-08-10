///|
let max_file_read_bytes : Int = 64 * 1024

///|
extern "C" fn link_async_fs() = "orbit_core_link_async_fs"

///|
priv struct FileReadRequest {
  id : String
} derive(FromJson)

///|
priv struct FileBinaryReadResponse {
  data : String
  size : Int
} derive(ToJson)

///|
priv struct FileTextReadResponse {
  text : String
  size : Int
} derive(ToJson)

///|
fn file_read_failure(code : String, message : String) -> @ipc.CommandFailure {
  @ipc.CommandFailure::new(code~, message~)
}

///|
fn resolve_read_path(
  files : @file.FileCapabilityRegistry,
  context : @ipc.InvocationContext,
  id : String,
) -> Result[String, @ipc.CommandFailure] {
  if id.is_empty() {
    return Err(
      file_read_failure("invalid_handle", "file handle must not be empty"),
    )
  }
  let label = match context.principal() {
    Window(label) => label
    _ =>
      return Err(
        file_read_failure(
          "file_unavailable", "file reads require a local window",
        ),
      )
  }
  match files.resolve(label, id, Read) {
    Ok(path) => Ok(path)
    Err(WrongPrincipal(_)) =>
      Err(
        file_read_failure(
          "file_handle_denied", "file handle belongs to another window",
        ),
      )
    Err(WrongKind(_)) =>
      Err(
        file_read_failure(
          "file_handle_invalid", "file handle does not allow reads",
        ),
      )
    Err(_) =>
      Err(
        file_read_failure("file_handle_invalid", "file handle is unavailable"),
      )
  }
}

///|
async fn read_capability_bytes(
  files : @file.FileCapabilityRegistry,
  context : @ipc.InvocationContext,
  request : FileReadRequest,
) -> Result[Bytes, @ipc.CommandFailure] {
  link_async_fs()
  let path = match resolve_read_path(files, context, request.id) {
    Ok(path) => path
    Err(failure) => return Err(failure)
  }
  if context.cancellation().is_cancelled() {
    return Err(file_read_failure("cancelled", "file read was cancelled"))
  }
  let file = @fs.open(path, mode=ReadOnly) catch {
    _ =>
      return Err(file_read_failure("file_read_failed", "could not open file"))
  }
  defer file.close()
  let size = file.size() catch {
    _ =>
      return Err(
        file_read_failure("file_read_failed", "could not inspect file"),
      )
  }
  if size < 0 || size > max_file_read_bytes.to_int64() {
    return Err(
      file_read_failure("file_too_large", "file exceeds the 64 KiB read limit"),
    )
  }
  if size == 0 {
    return Ok(b"")
  }
  let bytes = file.read_exactly_at(size.to_int(), position=0) catch {
    _ =>
      return Err(file_read_failure("file_read_failed", "could not read file"))
  }
  if context.cancellation().is_cancelled() {
    return Err(file_read_failure("cancelled", "file read was cancelled"))
  }
  Ok(bytes)
}

///|
async fn read_binary_capability(
  files : @file.FileCapabilityRegistry,
  context : @ipc.InvocationContext,
  request : FileReadRequest,
) -> Result[FileBinaryReadResponse, @ipc.CommandFailure] {
  let bytes = match read_capability_bytes(files, context, request) {
    Ok(bytes) => bytes
    Err(failure) => return Err(failure)
  }
  Ok({ data: @base64.encode(bytes), size: bytes.length() })
}

///|
async fn read_text_capability(
  files : @file.FileCapabilityRegistry,
  context : @ipc.InvocationContext,
  request : FileReadRequest,
) -> Result[FileTextReadResponse, @ipc.CommandFailure] {
  let bytes = match read_capability_bytes(files, context, request) {
    Ok(bytes) => bytes
    Err(failure) => return Err(failure)
  }
  let text = @utf8.decode(bytes) catch {
    _ =>
      return Err(file_read_failure("invalid_utf8", "file is not valid UTF-8"))
  }
  Ok({ text, size: bytes.length() })
}

///|
fn DesktopApp::register_file_read_commands(
  self : DesktopApp,
) -> Result[Unit, String] {
  match self.options.ipc_registry {
    None => Ok(())
    Some(registry) => {
      let binary = @ipc.CommandName::new("orbit.fs.read_binary") catch {
        _ => return Err("invalid built-in file read command")
      }
      registry.register_async_context(binary, async fn(context, request) {
        read_binary_capability(self.files, context, request)
      }) catch {
        _ => return Err("file read command is already registered")
      }
      let text = @ipc.CommandName::new("orbit.fs.read_text") catch {
        _ => return Err("invalid built-in file read command")
      }
      registry.register_async_context(text, async fn(context, request) {
        read_text_capability(self.files, context, request)
      }) catch {
        _ => return Err("file read command is already registered")
      }
      Ok(())
    }
  }
}
