///|
pub enum InvocationTransport {
  MoonView
  Http
  Plugin
  Background
} derive(Eq, Debug)

///|
pub fn InvocationTransport::moonview() -> InvocationTransport {
  MoonView
}

///|
pub fn InvocationTransport::http() -> InvocationTransport {
  Http
}

///|
pub fn InvocationTransport::plugin() -> InvocationTransport {
  Plugin
}

///|
pub fn InvocationTransport::background() -> InvocationTransport {
  Background
}

///|
pub enum InvocationPrincipal {
  Window(String)
  HttpClient(String)
  Plugin(String)
  BackgroundTask(String)
} derive(Eq, Debug)

///|
fn valid_invocation_identity(value : String) -> Bool {
  if value.is_empty() || value.length() > 128 {
    return false
  }
  for char in value {
    if !valid_command_char(char) {
      return false
    }
  }
  true
}

///|
fn valid_origin(value : String) -> Bool {
  if value.is_empty() || value.length() > 2_048 {
    return false
  }
  for char in value {
    let code = char.to_int()
    if code <= 31 || code == 127 {
      return false
    }
  }
  true
}

///|
fn context(
  transport : InvocationTransport,
  principal : InvocationPrincipal,
  origin : String?,
) -> InvocationContext {
  { transport, principal, origin, max_response_chars: 262_144 }
}

///|
/// Identifies a transport-authenticated command caller.
///
/// The context is constructed by an adapter and passed unchanged through
/// command authorization and execution. Its response limit applies to the
/// serialized protocol response, not only to a handler's JSON value.
pub struct InvocationContext {
  priv transport : InvocationTransport
  priv principal : InvocationPrincipal
  priv origin : String?
  priv max_response_chars : Int
}

///|
pub fn InvocationContext::window(
  label : String,
) -> InvocationContext raise IpcError {
  if !valid_invocation_identity(label) {
    raise InvalidPrincipal(label)
  }
  context(MoonView, Window(label), None)
}

///|
pub fn InvocationContext::http_client(
  identifier : String,
  origin? : String,
) -> InvocationContext raise IpcError {
  if !valid_invocation_identity(identifier) {
    raise InvalidPrincipal(identifier)
  }
  let origin = match origin {
    Some(origin) => {
      if !valid_origin(origin) {
        raise InvalidContext(origin)
      }
      Some(origin)
    }
    None => None
  }
  context(Http, HttpClient(identifier), origin)
}

///|
pub fn InvocationContext::plugin(
  identifier : String,
) -> InvocationContext raise IpcError {
  if !valid_invocation_identity(identifier) {
    raise InvalidPrincipal(identifier)
  }
  context(Plugin, Plugin(identifier), None)
}

///|
pub fn InvocationContext::background_task(
  identifier : String,
) -> InvocationContext raise IpcError {
  if !valid_invocation_identity(identifier) {
    raise InvalidPrincipal(identifier)
  }
  context(Background, BackgroundTask(identifier), None)
}

///|
pub fn InvocationContext::with_response_limit(
  self : InvocationContext,
  max_response_chars : Int,
) -> InvocationContext raise IpcError {
  if max_response_chars < 256 || max_response_chars > 262_144 {
    raise InvalidContext(
      "response limit must be between 256 and 262144 characters",
    )
  }
  {
    transport: self.transport,
    principal: self.principal,
    origin: self.origin,
    max_response_chars,
  }
}

///|
pub fn InvocationContext::transport(
  self : InvocationContext,
) -> InvocationTransport {
  self.transport
}

///|
pub fn InvocationContext::principal(
  self : InvocationContext,
) -> InvocationPrincipal {
  self.principal
}

///|
pub fn InvocationContext::origin(self : InvocationContext) -> String? {
  self.origin
}

///|
pub fn InvocationContext::max_response_chars(self : InvocationContext) -> Int {
  self.max_response_chars
}

///|
fn InvocationPrincipal::description(self : InvocationPrincipal) -> String {
  match self {
    Window(label) => "window: \{label}"
    HttpClient(identifier) => "http client: \{identifier}"
    Plugin(identifier) => "plugin: \{identifier}"
    BackgroundTask(identifier) => "background task: \{identifier}"
  }
}
