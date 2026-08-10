///|
pub(all) enum FileCapabilityKind {
  Read
  Write
  Directory
} derive(Eq, Debug)

///|
pub(all) suberror FileCapabilityError {
  RandomUnavailable
  DirectoryUnavailable
  DirectoryReadFailed
  DirectoryTooLarge
  UnknownHandle(String)
  WrongPrincipal(String)
  WrongKind(String)
} derive(Debug)

///|
pub struct FileCapability {
  priv id : String
  priv name : String
  priv kind : FileCapabilityKind
} derive(Eq, Debug)

///|
priv enum FileCapabilityLocation {
  Path(String)
  Directory(NativeDirectory)
}

///|
struct FileCapabilityRecord {
  location : FileCapabilityLocation
  window_label : String
  kind : FileCapabilityKind
}

///|
pub struct FileCapabilityRegistry {
  priv records : Map[String, FileCapabilityRecord]
}

///|
pub fn FileCapabilityRegistry::new() -> FileCapabilityRegistry {
  { records: Map([]) }
}

///|
pub fn FileCapability::id(self : FileCapability) -> String {
  self.id
}

///|
pub fn FileCapability::name(self : FileCapability) -> String {
  self.name
}

///|
pub fn FileCapability::kind(self : FileCapability) -> FileCapabilityKind {
  self.kind
}

///|
fn file_display_name(path : String) -> String {
  let normalized = path.replace_all(old="\\", new="/")
  match normalized.split("/").to_array() {
    [] => "selected item"
    segments => segments[segments.length() - 1].to_owned()
  }
}

///|
fn random_handle_id() -> String? {
  let bytes = FixedArray::make(16, b'\x00')
  if secure_random_fill(bytes) == 1 {
    Some(@base64.encode(bytes.unsafe_reinterpret_as_bytes()))
  } else {
    None
  }
}

///|
fn mint_handle_id(
  records : Map[String, FileCapabilityRecord],
) -> Result[String, FileCapabilityError] {
  for _ in 0..<8 {
    let id = match random_handle_id() {
      Some(id) => id
      None => return Err(RandomUnavailable)
    }
    if !records.contains(id) {
      return Ok(id)
    }
  }
  Err(RandomUnavailable)
}

///|
fn file_capability_directory_error(
  error : DirectoryHandleError,
) -> FileCapabilityError {
  match error {
    TooLarge => DirectoryTooLarge
    _ => DirectoryUnavailable
  }
}

///|
/// Mints a new opaque host capability for a picker-selected native path.
/// The path is intentionally never exposed by `FileCapability`.
pub fn FileCapabilityRegistry::mint(
  self : FileCapabilityRegistry,
  window_label : String,
  path : String,
  kind : FileCapabilityKind,
) -> Result[FileCapability, FileCapabilityError] {
  if kind == Directory {
    return Err(DirectoryUnavailable)
  }
  let id = match mint_handle_id(self.records) {
    Ok(id) => id
    Err(error) => return Err(error)
  }
  self.records[id] = { location: Path(path), window_label, kind }
  Ok({ id, name: file_display_name(path), kind })
}

///|
/// Mints a directory capability that owns a no-follow native root handle.
/// The selected path is converted to a handle immediately and is never kept as
/// a follow-up path string.
pub fn FileCapabilityRegistry::mint_directory(
  self : FileCapabilityRegistry,
  window_label : String,
  path : String,
) -> Result[FileCapability, FileCapabilityError] {
  let id = match mint_handle_id(self.records) {
    Ok(id) => id
    Err(error) => return Err(error)
  }
  let directory = match native_directory_open_path(path) {
    Ok(directory) => directory
    Err(error) => return Err(file_capability_directory_error(error))
  }
  self.records[id] = {
    location: Directory(directory),
    window_label,
    kind: Directory,
  }
  Ok({ id, name: file_display_name(path), kind: Directory })
}

///|
/// Resolves a capability for a host-owned follow-up operation. This method is
/// not an IPC boundary: callers must never return the resulting path to pages.
pub fn FileCapabilityRegistry::resolve(
  self : FileCapabilityRegistry,
  window_label : String,
  id : String,
  kind : FileCapabilityKind,
) -> Result[String, FileCapabilityError] {
  match self.records.get(id) {
    None => Err(UnknownHandle(id))
    Some(record) if record.window_label != window_label =>
      Err(WrongPrincipal(id))
    Some(record) if record.kind != kind => Err(WrongKind(id))
    Some(record) =>
      match record.location {
        Path(path) => Ok(path)
        Directory(_) => Err(WrongKind(id))
      }
  }
}

///|
fn FileCapabilityRegistry::resolve_directory(
  self : FileCapabilityRegistry,
  window_label : String,
  id : String,
) -> Result[NativeDirectory, FileCapabilityError] {
  match self.records.get(id) {
    None => Err(UnknownHandle(id))
    Some(record) if record.window_label != window_label =>
      Err(WrongPrincipal(id))
    Some(record) if record.kind != Directory => Err(WrongKind(id))
    Some(record) =>
      match record.location {
        Directory(directory) => Ok(directory)
        Path(_) => Err(DirectoryUnavailable)
      }
  }
}

///|
/// Lists a picker-authorized directory through its held native handle. The
/// returned entries intentionally carry names and kinds only.
pub fn FileCapabilityRegistry::list_directory(
  self : FileCapabilityRegistry,
  window_label : String,
  id : String,
  max_entries : Int,
) -> Result[Array[DirectoryEntry], FileCapabilityError] {
  let directory = match self.resolve_directory(window_label, id) {
    Ok(directory) => directory
    Err(error) => return Err(error)
  }
  match native_directory_list(directory, max_entries) {
    Ok(entries) => Ok(entries)
    Err(TooLarge) => Err(DirectoryTooLarge)
    Err(_) => Err(DirectoryReadFailed)
  }
}

///|
/// Mints a child directory capability relative to a held parent handle. The
/// component is validated by the native boundary and cannot escape the root.
pub fn FileCapabilityRegistry::mint_child_directory(
  self : FileCapabilityRegistry,
  window_label : String,
  parent_id : String,
  name : String,
) -> Result[FileCapability, FileCapabilityError] {
  let id = match mint_handle_id(self.records) {
    Ok(id) => id
    Err(error) => return Err(error)
  }
  let parent = match self.resolve_directory(window_label, parent_id) {
    Ok(parent) => parent
    Err(error) => return Err(error)
  }
  let directory = match native_directory_open_relative(parent, name) {
    Ok(directory) => directory
    Err(error) => return Err(file_capability_directory_error(error))
  }
  self.records[id] = {
    location: Directory(directory),
    window_label,
    kind: Directory,
  }
  Ok({ id, name, kind: Directory })
}

///|
fn close_capability_record(record : FileCapabilityRecord) -> Unit {
  match record.location {
    Directory(directory) => native_directory_close(directory)
    Path(_) => ()
  }
}

///|
pub fn FileCapabilityRegistry::revoke_window(
  self : FileCapabilityRegistry,
  window_label : String,
) -> Unit {
  let ids : Array[String] = []
  for id, record in self.records {
    if record.window_label == window_label {
      close_capability_record(record)
      ids.push(id)
    }
  }
  for id in ids {
    self.records.remove(id)
  }
}

///|
pub fn FileCapabilityRegistry::clear(self : FileCapabilityRegistry) -> Unit {
  for _, record in self.records {
    close_capability_record(record)
  }
  self.records.clear()
}

///|
pub fn FileCapabilityRegistry::length(self : FileCapabilityRegistry) -> Int {
  self.records.length()
}
