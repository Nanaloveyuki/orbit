///|
pub(all) suberror IpcError {
  MalformedEnvelope(String)
  UnsupportedVersion(Int)
  InvalidInvocationId(String)
  InvalidCommandName(String)
  InvalidCapability(String)
  DuplicateCommand(String)
  DuplicateCapability(String)
} derive(Debug)

///|
pub struct InvocationId {
  priv value : String
} derive(Eq, Debug)

///|
pub fn InvocationId::new(value : String) -> InvocationId raise IpcError {
  if value.is_empty() || value.length() > 128 {
    raise InvalidInvocationId(value)
  }
  for char in value {
    let code = char.to_int()
    if code <= 31 || code == 127 {
      raise InvalidInvocationId(value)
    }
  }
  { value, }
}

///|
pub fn InvocationId::value(self : InvocationId) -> String {
  self.value
}

///|
pub struct CommandName {
  priv value : String
} derive(Eq, Debug)

///|
fn valid_command_char(char : Char) -> Bool {
  let code = char.to_int()
  (code >= 48 && code <= 57) ||
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122) ||
  char == '-' ||
  char == '_' ||
  char == '.' ||
  char == ':' ||
  char == '/'
}

///|
pub fn CommandName::new(value : String) -> CommandName raise IpcError {
  if value.is_empty() || value.length() > 128 {
    raise InvalidCommandName(value)
  }
  for char in value {
    if !valid_command_char(char) {
      raise InvalidCommandName(value)
    }
  }
  { value, }
}

///|
pub fn CommandName::value(self : CommandName) -> String {
  self.value
}

///|
pub struct InvocationRequest {
  priv id : InvocationId
  priv command : CommandName
  priv payload : Json
}

///|
pub fn InvocationRequest::id(self : InvocationRequest) -> InvocationId {
  self.id
}

///|
pub fn InvocationRequest::command(self : InvocationRequest) -> CommandName {
  self.command
}

///|
pub fn InvocationRequest::payload(self : InvocationRequest) -> Json {
  self.payload
}

///|
pub(all) struct CommandFailure {
  code : String
  message : String
  data : Json?
} derive(Eq, Debug)

///|
pub fn CommandFailure::new(
  code~ : String,
  message~ : String,
  data? : Json,
) -> CommandFailure {
  { code, message, data }
}

///|
pub(all) enum InvocationResponse {
  Success(InvocationId, Json)
  Failure(InvocationId?, CommandFailure)
}

///|
fn malformed(message : String) -> IpcError {
  MalformedEnvelope(message)
}

///|
fn required_field(
  object : Map[String, Json],
  name : String,
) -> Json raise IpcError {
  match object.get(name) {
    Some(value) => value
    None => raise malformed("missing field: \{name}")
  }
}

///|
fn decode_exact_int(value : Json, name : String) -> Int raise IpcError {
  match value {
    Number(number, ..) => {
      if number > 2147483647.0 || number < -2147483648.0 {
        raise malformed("field \{name} is outside the supported integer range")
      }
      let integer = number.to_int()
      if integer.to_double() != number {
        raise malformed("field \{name} must be an integer")
      }
      integer
    }
    _ => raise malformed("field \{name} must be a number")
  }
}

///|
fn decode_string(value : Json, name : String) -> String raise IpcError {
  match value {
    String(value) => value
    _ => raise malformed("field \{name} must be a string")
  }
}

///|
fn ipc_json_limits() -> @strict_json.JsonLimits {
  @strict_json.JsonLimits::new(
    max_input_chars=262_144,
    max_depth=32,
    max_string_chars=131_072,
    max_array_items=4_096,
    max_object_members=4_096,
  )
}

///|
fn strict_json_message(error : @strict_json.JsonError) -> String {
  match error {
    Syntax(error~) => "invalid JSON at character \{error.offset()}"
    DuplicateKey(key~, duplicate_offset~, ..) =>
      "duplicate JSON key \{key} at character \{duplicate_offset}"
    Limit(kind~, offset~, limit~) => {
      let kind = match kind {
        InputChars => "input size"
        NestingDepth => "nesting depth"
        StringChars => "string size"
        ArrayItems => "array item count"
        ObjectMembers => "object member count"
      }
      "JSON \{kind} limit \{limit} exceeded at character \{offset}"
    }
  }
}

///|
pub fn decode_request(source : StringView) -> InvocationRequest raise IpcError {
  let source = source.to_owned()
  match @strict_json.parse_with_limits(source, ipc_json_limits()) {
    Ok(_) => ()
    Err(error) => raise malformed(strict_json_message(error))
  }
  let value = @json.parse(source) catch {
    error => raise malformed("invalid JSON: \{error}")
  }
  let object = match value {
    Object(object) => object
    _ => raise malformed("request must be a JSON object")
  }
  for name, _ in object {
    match name {
      "version" | "id" | "command" | "payload" => ()
      _ => raise malformed("unknown field: \{name}")
    }
  }
  let version = decode_exact_int(required_field(object, "version"), "version")
  if version != 1 {
    raise UnsupportedVersion(version)
  }
  let id = InvocationId::new(decode_string(required_field(object, "id"), "id"))
  let command = CommandName::new(
    decode_string(required_field(object, "command"), "command"),
  )
  let payload = required_field(object, "payload")
  { id, command, payload }
}

///|
fn extract_request_id(source : StringView) -> InvocationId? {
  let value = @json.parse(source) catch { _ => return None }
  match value {
    Object(object) =>
      match object.get("id") {
        Some(String(value)) => {
          let id = InvocationId::new(value) catch { _ => return None }
          Some(id)
        }
        _ => None
      }
    _ => None
  }
}

///|
fn quoted(value : String) -> String {
  Json::string(value).stringify()
}

///|
pub fn encode_response(response : InvocationResponse) -> String {
  match response {
    Success(id, result) =>
      "{\"version\":1,\"id\":\{quoted(id.value())},\"ok\":true,\"result\":\{result.stringify()}}"
    Failure(id, failure) => {
      let id = match id {
        Some(id) => quoted(id.value())
        None => "null"
      }
      let data = match failure.data {
        Some(data) => data.stringify()
        None => "null"
      }
      "{\"version\":1,\"id\":\{id},\"ok\":false,\"error\":{\"code\":\{quoted(failure.code)},\"message\":\{quoted(failure.message)},\"data\":\{data}}}"
    }
  }
}

///|
fn IpcError::failure(self : IpcError) -> CommandFailure {
  match self {
    MalformedEnvelope(message) =>
      CommandFailure::new(code="invalid_request", message~)
    UnsupportedVersion(version) =>
      CommandFailure::new(
        code="unsupported_version",
        message="unsupported IPC version: \{version}",
      )
    InvalidInvocationId(_) =>
      CommandFailure::new(
        code="invalid_request",
        message="invalid invocation id",
      )
    InvalidCommandName(_) =>
      CommandFailure::new(
        code="invalid_request",
        message="invalid command name",
      )
    InvalidCapability(_) =>
      CommandFailure::new(
        code="invalid_capability",
        message="invalid command capability",
      )
    DuplicateCommand(name) =>
      CommandFailure::new(
        code="duplicate_command",
        message="command is already registered: \{name}",
      )
    DuplicateCapability(identifier) =>
      CommandFailure::new(
        code="duplicate_capability",
        message="capability is already registered: \{identifier}",
      )
  }
}
