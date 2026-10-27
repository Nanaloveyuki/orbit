///|
pub(all) enum FileCapabilityKind {
  Read
  Write
  Directory
} derive(Eq, Debug)

///|
pub extend FileCapabilityKind with Eq::{not_equal, equal}

///|
pub extend FileCapabilityKind with Debug::{to_repr}

///|
pub(all) suberror FileCapabilityError {
  RandomUnavailable
  DirectoryUnavailable
  DirectoryReadFailed
  DirectoryTooLarge
  DirectoryCapabilityLimit
  FileReadFailed
  FileTooLarge
  UnknownHandle(String)
  WrongPrincipal(String)
  WrongKind(String)
} derive(Debug)

///|
pub extend FileCapabilityError with Debug::{to_repr}

///|
pub struct FileCapability {
  priv id : String
  priv name : String
  priv kind : FileCapabilityKind
} derive(Eq, Debug)

///|
pub extend FileCapability with Eq::{not_equal, equal}

///|
pub extend FileCapability with Debug::{to_repr}

///|
priv enum FileCapabilityLocation {
  Path(String)
  Directory(NativeDirectory)
  NativeReadFile(NativeReadFile)
}

///|
struct FileCapabilityRecord {
  location : FileCapabilityLocation
  name : String
  window_label : String
  kind : FileCapabilityKind
  parent_id : String?
}

///|
pub struct FileCapabilityRegistry {
  priv records : Map[String, FileCapabilityRecord]
}

///|
let max_native_capabilities_per_window = 256

///|
pub fn FileCapabilityRegistry::new() -> FileCapabilityRegistry {
  { records: Map([]), }
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
) -> String raise FileCapabilityError {
  for _ in 0..<8 {
    let id = match random_handle_id() {
      Some(id) => id
      None => raise RandomUnavailable
    }
    if !records.contains(id) {
      return id
    }
  }
  raise RandomUnavailable
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
fn native_capability_count(
  records : Map[String, FileCapabilityRecord],
  window_label : String,
) -> Int32 {
  let mut count = 0
  for _, record in records {
    if record.window_label == window_label {
      match record.location {
        Directory(_) | NativeReadFile(_) => count += 1
        Path(_) => ()
      }
    }
  }
  count
}

///|
/// Mints a new opaque host capability for a picker-selected native path.
/// The path is intentionally never exposed by `FileCapability`.
pub fn FileCapabilityRegistry::mint(
  self : FileCapabilityRegistry,
  window_label : String,
  path : String,
  kind : FileCapabilityKind,
) -> FileCapability raise FileCapabilityError {
  if kind == Directory {
    raise DirectoryUnavailable
  }
  let id = mint_handle_id(self.records)
  let name = file_display_name(path)
  self.records[id] = {
    location: Path(path),
    name,
    window_label,
    kind,
    parent_id: None,
  }
  { id, name, kind, }
}

///|
/// Mints a directory capability that owns a no-follow native root handle.
/// The selected path is converted to a handle immediately and is never kept as
/// a follow-up path string.
pub fn FileCapabilityRegistry::mint_directory(
  self : FileCapabilityRegistry,
  window_label : String,
  path : String,
) -> FileCapability raise FileCapabilityError {
  if native_capability_count(self.records, window_label) >=
    max_native_capabilities_per_window {
    raise DirectoryCapabilityLimit
  }
  let id = mint_handle_id(self.records)
  let directory = native_directory_open_path(path) catch {
    error => raise file_capability_directory_error(error)
  }
  let name = file_display_name(path)
  self.records[id] = {
    location: Directory(directory),
    name,
    window_label,
    kind: Directory,
    parent_id: None,
  }
  { id, name, kind: Directory, }
}

///|
/// Resolves a capability for a host-owned follow-up operation. This method is
/// not an IPC boundary: callers must never return the resulting path to pages.
pub fn FileCapabilityRegistry::resolve(
  self : FileCapabilityRegistry,
  window_label : String,
  id : String,
  kind : FileCapabilityKind,
) -> String raise FileCapabilityError {
  match self.records.get(id) {
    None => raise UnknownHandle(id)
    Some(record) if record.window_label != window_label =>
      raise WrongPrincipal(id)
    Some(record) if record.kind != kind => raise WrongKind(id)
    Some(record) =>
      match record.location {
        Path(path) => path
        Directory(_) | NativeReadFile(_) => raise WrongKind(id)
      }
  }
}

///|
fn FileCapabilityRegistry::resolve_directory(
  self : FileCapabilityRegistry,
  window_label : String,
  id : String,
) -> NativeDirectory raise FileCapabilityError {
  match self.records.get(id) {
    None => raise UnknownHandle(id)
    Some(record) if record.window_label != window_label =>
      raise WrongPrincipal(id)
    Some(record) if record.kind != Directory => raise WrongKind(id)
    Some(record) =>
      match record.location {
        Directory(directory) => directory
        Path(_) | NativeReadFile(_) => raise DirectoryUnavailable
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
  max_entries : Int32,
) -> Array[DirectoryEntry] raise FileCapabilityError {
  let directory = self.resolve_directory(window_label, id)
  native_directory_list(directory, max_entries) catch {
    TooLarge => raise DirectoryTooLarge
    _ => raise DirectoryReadFailed
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
) -> FileCapability raise FileCapabilityError {
  for id, record in self.records {
    if record.window_label == window_label &&
      record.kind == Directory &&
      record.name == name {
      match record.parent_id {
        Some(existing_parent) if existing_parent == parent_id =>
          return { id, name, kind: Directory, }
        _ => ()
      }
    }
  }
  if native_capability_count(self.records, window_label) >=
    max_native_capabilities_per_window {
    raise DirectoryCapabilityLimit
  }
  let id = mint_handle_id(self.records)
  let parent = self.resolve_directory(window_label, parent_id)
  let directory = native_directory_open_relative(parent, name) catch {
    error => raise file_capability_directory_error(error)
  }
  self.records[id] = {
    location: Directory(directory),
    name,
    window_label,
    kind: Directory,
    parent_id: Some(parent_id),
  }
  { id, name, kind: Directory, }
}

///|
/// Mints a read capability for a regular file relative to a held directory
/// handle. The native boundary rejects links, directories, and traversal.
pub fn FileCapabilityRegistry::mint_child_read_file(
  self : FileCapabilityRegistry,
  window_label : String,
  parent_id : String,
  name : String,
) -> FileCapability raise FileCapabilityError {
  for id, record in self.records {
    if record.window_label == window_label &&
      record.kind == Read &&
      record.name == name {
      match record.parent_id {
        Some(existing_parent) if existing_parent == parent_id =>
          return { id, name, kind: Read, }
        _ => ()
      }
    }
  }
  if native_capability_count(self.records, window_label) >=
    max_native_capabilities_per_window {
    raise DirectoryCapabilityLimit
  }
  let id = mint_handle_id(self.records)
  let parent = self.resolve_directory(window_label, parent_id)
  let file = native_directory_open_read_relative(parent, name) catch {
    error => raise file_capability_directory_error(error)
  }
  self.records[id] = {
    location: NativeReadFile(file),
    name,
    window_label,
    kind: Read,
    parent_id: Some(parent_id),
  }
  { id, name, kind: Read, }
}

///|
/// Reads an opaque directory-derived file capability. `None` means the
/// capability is a picker path handle and should use the existing async path
/// reader; `Some` is read only through the held native handle.
pub fn FileCapabilityRegistry::read_native_file(
  self : FileCapabilityRegistry,
  window_label : String,
  id : String,
  max_bytes : Int32,
) -> Bytes? raise FileCapabilityError {
  match self.records.get(id) {
    None => raise UnknownHandle(id)
    Some(record) if record.window_label != window_label =>
      raise WrongPrincipal(id)
    Some(record) if record.kind != Read => raise WrongKind(id)
    Some(record) =>
      match record.location {
        Path(_) => None
        NativeReadFile(file) => {
          let bytes = native_read_file_read(file, max_bytes) catch {
            TooLarge => raise FileTooLarge
            _ => raise FileReadFailed
          }
          Some(bytes)
        }
        Directory(_) => raise WrongKind(id)
      }
  }
}

///|
fn close_capability_record(record : FileCapabilityRecord) -> Unit {
  match record.location {
    Directory(directory) => native_directory_close(directory)
    NativeReadFile(file) => native_read_file_close(file)
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
pub fn FileCapabilityRegistry::length(self : FileCapabilityRegistry) -> Int32 {
  self.records.length()
}
