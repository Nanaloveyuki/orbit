///|
let max_file_read_bytes : Int = 64 * 1024

///|
let max_directory_entries : Int = 128

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
priv struct FileWriteRequest {
  id : String
  text : String
} derive(FromJson)

///|
priv struct FileWriteResponse {
  size : Int
} derive(ToJson)

///|
priv struct FileDirectoryReadRequest {
  id : String
} derive(FromJson)

///|
priv struct FileDirectoryEntryResponse {
  id : String?
  name : String
  kind : String
} derive(ToJson)

///|
priv struct FileDirectoryReadResponse {
  entries : Array[FileDirectoryEntryResponse]
} derive(ToJson)

///|
fn file_read_failure(code : String, message : String) -> @ipc.CommandFailure {
  @ipc.CommandFailure::new(code~, message~)
}

///|
fn resolve_file_window_label(
  context : @ipc.InvocationContext,
) -> Result[String, @ipc.CommandFailure] {
  match context.principal() {
    Window(label) => Ok(label)
    _ =>
      Err(
        file_read_failure(
          "file_unavailable", "file access requires a local window",
        ),
      )
  }
}

///|
fn resolve_file_path(
  files : @file.FileCapabilityRegistry,
  context : @ipc.InvocationContext,
  id : String,
  kind : @file.FileCapabilityKind,
) -> Result[String, @ipc.CommandFailure] {
  if id.is_empty() {
    return Err(
      file_read_failure("invalid_handle", "file handle must not be empty"),
    )
  }
  let label = match resolve_file_window_label(context) {
    Ok(label) => label
    Err(failure) => return Err(failure)
  }
  match files.resolve(label, id, kind) {
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
          "file_handle_invalid", "file handle does not allow this operation",
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
  if request.id.is_empty() {
    return Err(
      file_read_failure("invalid_handle", "file handle must not be empty"),
    )
  }
  let label = match resolve_file_window_label(context) {
    Ok(label) => label
    Err(failure) => return Err(failure)
  }
  let native = match
    files.read_native_file(label, request.id, max_file_read_bytes) {
    Ok(bytes) => bytes
    Err(WrongPrincipal(_)) =>
      return Err(
        file_read_failure(
          "file_handle_denied", "file handle belongs to another window",
        ),
      )
    Err(WrongKind(_)) =>
      return Err(
        file_read_failure(
          "file_handle_invalid", "file handle does not allow this operation",
        ),
      )
    Err(FileTooLarge) =>
      return Err(
        file_read_failure(
          "file_too_large", "file exceeds the 64 KiB read limit",
        ),
      )
    Err(FileReadFailed) =>
      return Err(file_read_failure("file_read_failed", "could not read file"))
    Err(_) =>
      return Err(
        file_read_failure("file_handle_invalid", "file handle is unavailable"),
      )
  }
  if context.cancellation().is_cancelled() {
    return Err(file_read_failure("cancelled", "file read was cancelled"))
  }
  match native {
    Some(bytes) => return Ok(bytes)
    None => ()
  }
  link_async_fs()
  let path = match files.resolve(label, request.id, Read) {
    Ok(path) => path
    Err(_) =>
      return Err(
        file_read_failure("file_handle_invalid", "file handle is unavailable"),
      )
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
fn temporary_write_path(target : String, handle : String) -> String {
  let token = handle
    .replace_all(old="/", new="_")
    .replace_all(old="+", new="-")
    .replace_all(old="=", new="")
  "\{target}.orbit-tmp-\{token}"
}

///|
async fn remove_temporary_write(path : String) -> Unit {
  @fs.remove(path) catch {
    _ => ()
  }
}

///|
async fn write_text_capability(
  files : @file.FileCapabilityRegistry,
  context : @ipc.InvocationContext,
  request : FileWriteRequest,
) -> Result[FileWriteResponse, @ipc.CommandFailure] {
  link_async_fs()
  let path = match resolve_file_path(files, context, request.id, Write) {
    Ok(path) => path
    Err(failure) => return Err(failure)
  }
  let bytes = @utf8.encode(request.text, bom=false)
  if bytes.length() > max_file_read_bytes {
    return Err(
      file_read_failure("file_too_large", "text exceeds the 64 KiB write limit"),
    )
  }
  if context.cancellation().is_cancelled() {
    return Err(file_read_failure("cancelled", "file write was cancelled"))
  }
  let temporary = temporary_write_path(path, request.id)
  @fs.write_file(temporary, bytes, create_mode=CreateNew, sync=Full) catch {
    _ => {
      remove_temporary_write(temporary)
      return Err(file_read_failure("file_write_failed", "could not write file"))
    }
  }
  if context.cancellation().is_cancelled() {
    remove_temporary_write(temporary)
    return Err(file_read_failure("cancelled", "file write was cancelled"))
  }
  @fs.rename(temporary, path, replace=true) catch {
    _ => {
      remove_temporary_write(temporary)
      return Err(
        file_read_failure("file_write_failed", "could not replace file"),
      )
    }
  }
  Ok({ size: bytes.length() })
}

///|
async fn read_directory_capability(
  files : @file.FileCapabilityRegistry,
  context : @ipc.InvocationContext,
  request : FileDirectoryReadRequest,
) -> Result[FileDirectoryReadResponse, @ipc.CommandFailure] {
  if context.cancellation().is_cancelled() {
    return Err(file_read_failure("cancelled", "directory read was cancelled"))
  }
  @async.sleep(0) catch {
    _ =>
      return Err(file_read_failure("cancelled", "directory read was cancelled"))
  }
  if request.id.is_empty() {
    return Err(
      file_read_failure("invalid_handle", "file handle must not be empty"),
    )
  }
  let label = match context.principal() {
    Window(label) => label
    _ =>
      return Err(
        file_read_failure(
          "file_unavailable", "file access requires a local window",
        ),
      )
  }
  let listed = match
    files.list_directory(label, request.id, max_directory_entries) {
    Ok(entries) => entries
    Err(WrongPrincipal(_)) =>
      return Err(
        file_read_failure(
          "file_handle_denied", "file handle belongs to another window",
        ),
      )
    Err(WrongKind(_)) =>
      return Err(
        file_read_failure(
          "file_handle_invalid", "file handle does not allow this operation",
        ),
      )
    Err(DirectoryTooLarge) =>
      return Err(
        file_read_failure(
          "directory_too_large", "directory exceeds the 128 entry limit",
        ),
      )
    Err(DirectoryReadFailed) =>
      return Err(
        file_read_failure("directory_read_failed", "could not read directory"),
      )
    Err(_) =>
      return Err(
        file_read_failure("file_handle_invalid", "file handle is unavailable"),
      )
  }
  let entries : Array[FileDirectoryEntryResponse] = []
  for entry in listed {
    let id = match entry.kind {
      @file.DirectoryEntryKind::Directory =>
        match files.mint_child_directory(label, request.id, entry.name) {
          Ok(capability) => Some(capability.id())
          Err(_) => None
        }
      @file.DirectoryEntryKind::File =>
        match files.mint_child_read_file(label, request.id, entry.name) {
          Ok(capability) => Some(capability.id())
          Err(_) => None
        }
    }
    entries.push({
      id,
      name: entry.name,
      kind: match entry.kind {
        @file.DirectoryEntryKind::Directory => "directory"
        @file.DirectoryEntryKind::File => "file"
      },
    })
  }
  if context.cancellation().is_cancelled() {
    return Err(file_read_failure("cancelled", "directory read was cancelled"))
  }
  Ok({ entries, })
}

///|
fn DesktopApp::register_file_access_commands(
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
      let write = @ipc.CommandName::new("orbit.fs.write_text") catch {
        _ => return Err("invalid built-in file write command")
      }
      registry.register_async_context(write, async fn(context, request) {
        write_text_capability(self.files, context, request)
      }) catch {
        _ => return Err("file write command is already registered")
      }
      let directory = @ipc.CommandName::new("orbit.fs.read_directory") catch {
        _ => return Err("invalid built-in directory read command")
      }
      registry.register_async_context(directory, async fn(context, request) {
        read_directory_capability(self.files, context, request)
      }) catch {
        _ => return Err("directory read command is already registered")
      }
      Ok(())
    }
  }
}
