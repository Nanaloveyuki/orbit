///|
pub(all) enum DirectoryEntryKind {
  File
  Directory
} derive(Eq, Debug)

///|
pub(all) struct DirectoryEntry {
  name : String
  kind : DirectoryEntryKind
} derive(Eq, Debug)

///|
pub(all) suberror DirectoryHandleError {
  OpenFailed
  InvalidChildName
  ReadFailed
  TooLarge
} derive(Eq, Debug)

///|
priv type NativeDirectory

///|
priv type NativeReadFile

///|
#borrow(path, status)
extern "C" fn native_directory_open(
  path : Bytes,
  status : Ref[Int],
) -> NativeDirectory = "orbit_file_directory_open"

///|
#borrow(directory)
extern "C" fn native_directory_close(directory : NativeDirectory) -> Unit = "orbit_file_directory_close"

///|
#borrow(directory, status)
extern "C" fn native_directory_entries(
  directory : NativeDirectory,
  max_entries : Int,
  status : Ref[Int],
) -> Bytes = "orbit_file_directory_entries"

///|
#borrow(directory, name, status)
extern "C" fn native_directory_open_child(
  directory : NativeDirectory,
  name : Bytes,
  status : Ref[Int],
) -> NativeDirectory = "orbit_file_directory_open_child"

///|
#borrow(directory, name, status)
extern "C" fn native_directory_open_read_file(
  directory : NativeDirectory,
  name : Bytes,
  status : Ref[Int],
) -> NativeReadFile = "orbit_file_directory_open_read_file"

///|
#borrow(file)
extern "C" fn native_read_file_close(file : NativeReadFile) -> Unit = "orbit_file_read_file_close"

///|
#borrow(file, status)
extern "C" fn native_read_file_bytes(
  file : NativeReadFile,
  max_bytes : Int,
  status : Ref[Int],
) -> Bytes = "orbit_file_read_file_bytes"

///|
fn directory_error_from_status(status : Int) -> DirectoryHandleError {
  match status {
    2 => InvalidChildName
    4 => TooLarge
    1 => OpenFailed
    _ => ReadFailed
  }
}

///|
fn decode_u32_le(bytes : Bytes, offset : Int) -> Int? {
  if offset < 0 || offset + 4 > bytes.length() {
    return None
  }
  Some(
    bytes[offset].to_int() |
    (bytes[offset + 1].to_int() << 8) |
    (bytes[offset + 2].to_int() << 16) |
    (bytes[offset + 3].to_int() << 24),
  )
}

///|
fn decode_directory_entries(
  bytes : Bytes,
) -> Result[Array[DirectoryEntry], DirectoryHandleError] {
  let count = match decode_u32_le(bytes, 0) {
    Some(count) if count >= 0 && count <= 128 => count
    _ => return Err(ReadFailed)
  }
  let mut offset = 4
  let entries : Array[DirectoryEntry] = []
  for _ in 0..<count {
    if offset + 5 > bytes.length() {
      return Err(ReadFailed)
    }
    let kind = match bytes[offset].to_int() {
      1 => File
      2 => Directory
      _ => return Err(ReadFailed)
    }
    let name_length = match decode_u32_le(bytes, offset + 1) {
      Some(length) if length > 0 && length <= 4096 => length
      _ => return Err(ReadFailed)
    }
    offset += 5
    if offset + name_length > bytes.length() {
      return Err(ReadFailed)
    }
    let name = @utf8.decode(bytes[offset:offset + name_length]) catch {
      _ => return Err(ReadFailed)
    }
    if name.is_empty() {
      return Err(ReadFailed)
    }
    entries.push({ name, kind })
    offset += name_length
  }
  if offset != bytes.length() {
    return Err(ReadFailed)
  }
  Ok(entries)
}

///|
fn native_directory_open_path(
  path : String,
) -> Result[NativeDirectory, DirectoryHandleError] {
  let status = Ref(0)
  let directory = native_directory_open(@utf8.encode(path, bom=false), status)
  if status.val != 0 {
    return Err(directory_error_from_status(status.val))
  }
  Ok(directory)
}

///|
fn native_directory_open_relative(
  directory : NativeDirectory,
  name : String,
) -> Result[NativeDirectory, DirectoryHandleError] {
  let status = Ref(0)
  let child = native_directory_open_child(
    directory,
    @utf8.encode(name, bom=false),
    status,
  )
  if status.val != 0 {
    return Err(directory_error_from_status(status.val))
  }
  Ok(child)
}

///|
fn native_directory_list(
  directory : NativeDirectory,
  max_entries : Int,
) -> Result[Array[DirectoryEntry], DirectoryHandleError] {
  let status = Ref(0)
  let bytes = native_directory_entries(directory, max_entries, status)
  if status.val != 0 {
    return Err(directory_error_from_status(status.val))
  }
  decode_directory_entries(bytes)
}

///|
fn native_directory_open_read_relative(
  directory : NativeDirectory,
  name : String,
) -> Result[NativeReadFile, DirectoryHandleError] {
  let status = Ref(0)
  let file = native_directory_open_read_file(
    directory,
    @utf8.encode(name, bom=false),
    status,
  )
  if status.val != 0 {
    return Err(directory_error_from_status(status.val))
  }
  Ok(file)
}

///|
fn native_read_file_read(
  file : NativeReadFile,
  max_bytes : Int,
) -> Result[Bytes, DirectoryHandleError] {
  let status = Ref(0)
  let bytes = native_read_file_bytes(file, max_bytes, status)
  if status.val != 0 {
    return Err(directory_error_from_status(status.val))
  }
  Ok(bytes)
}
