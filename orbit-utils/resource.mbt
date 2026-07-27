///|
pub(all) suberror ResourceError {
  InvalidPath(String)
  DuplicatePath(String)
} derive(Debug)

///|
pub struct EmbeddedResource {
  path : String
  media_type : String
  bytes : Bytes
  fingerprint : String
}

///|
pub fn EmbeddedResource::path(self : EmbeddedResource) -> String {
  self.path
}

///|
pub fn EmbeddedResource::media_type(self : EmbeddedResource) -> String {
  self.media_type
}

///|
pub fn EmbeddedResource::bytes(self : EmbeddedResource) -> Bytes {
  self.bytes
}

///|
pub fn EmbeddedResource::fingerprint(self : EmbeddedResource) -> String {
  self.fingerprint
}

///|
pub fn normalize_resource_path(path : String) -> Result[String, ResourceError] {
  let normalized = path.trim().to_owned().replace_all(old="\\", new="/")
  if normalized.is_empty() ||
    normalized.has_prefix("/") ||
    normalized.has_suffix("/") ||
    normalized.contains(":") ||
    normalized.contains("?") ||
    normalized.contains("#") ||
    normalized.contains("%") ||
    normalized.contains_char('\u{0000}') {
    return Err(InvalidPath(path))
  }
  let segments = normalized.split("/").to_array()
  for segment in segments {
    if segment.is_empty() || segment == "." || segment == ".." {
      return Err(InvalidPath(path))
    }
  }
  Ok(normalized)
}

///|
pub fn EmbeddedResource::new(
  path~ : String,
  media_type~ : String,
  bytes~ : Bytes,
) -> EmbeddedResource raise ResourceError {
  let path = match normalize_resource_path(path) {
    Ok(value) => value
    Err(error) => raise error
  }
  {
    path,
    media_type: media_type.trim().to_owned(),
    fingerprint: fingerprint_bytes(bytes),
    bytes,
  }
}

///|
pub struct ResourceTable {
  priv resources : Map[String, EmbeddedResource]
}

///|
pub fn ResourceTable::new() -> ResourceTable {
  { resources: Map([]) }
}

///|
pub fn ResourceTable::add(
  self : ResourceTable,
  resource : EmbeddedResource,
) -> Unit raise ResourceError {
  if self.resources.contains(resource.path) {
    raise DuplicatePath(resource.path)
  }
  self.resources[resource.path] = resource
}

///|
pub fn ResourceTable::get(
  self : ResourceTable,
  path : String,
) -> EmbeddedResource? {
  match normalize_resource_path(path) {
    Ok(path) => self.resources.get(path)
    Err(_) => None
  }
}

///|
pub fn ResourceTable::length(self : ResourceTable) -> Int {
  self.resources.length()
}
