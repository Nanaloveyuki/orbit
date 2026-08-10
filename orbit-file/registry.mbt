///|
pub(all) enum FileCapabilityKind {
  Read
  Write
  Directory
} derive(Eq, Debug)

///|
pub(all) suberror FileCapabilityError {
  RandomUnavailable
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
struct FileCapabilityRecord {
  path : String
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
/// Mints a new opaque host capability for a picker-selected native path.
/// The path is intentionally never exposed by `FileCapability`.
pub fn FileCapabilityRegistry::mint(
  self : FileCapabilityRegistry,
  window_label : String,
  path : String,
  kind : FileCapabilityKind,
) -> Result[FileCapability, FileCapabilityError] {
  for _ in 0..<8 {
    let id = match random_handle_id() {
      Some(id) => id
      None => return Err(RandomUnavailable)
    }
    if !self.records.contains(id) {
      self.records[id] = { path, window_label, kind }
      return Ok({ id, name: file_display_name(path), kind })
    }
  }
  Err(RandomUnavailable)
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
    Some(record) => Ok(record.path)
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
      ids.push(id)
    }
  }
  for id in ids {
    self.records.remove(id)
  }
}

///|
pub fn FileCapabilityRegistry::clear(self : FileCapabilityRegistry) -> Unit {
  self.records.clear()
}

///|
pub fn FileCapabilityRegistry::length(self : FileCapabilityRegistry) -> Int {
  self.records.length()
}
