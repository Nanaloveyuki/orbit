///|
type JsonHandler = (Json) -> Result[Json, CommandFailure]

///|
pub struct CommandRegistry {
  priv handlers : Map[String, JsonHandler]
}

///|
pub fn CommandRegistry::new() -> CommandRegistry {
  { handlers: Map([]) }
}

///|
pub fn CommandRegistry::register_json(
  self : CommandRegistry,
  name : CommandName,
  handler : JsonHandler,
) -> Unit raise IpcError {
  let key = name.value()
  if self.handlers.contains(key) {
    raise DuplicateCommand(key)
  }
  self.handlers[key] = handler
}

///|
pub fn[Request : @json.FromJson, Response : ToJson] CommandRegistry::register(
  self : CommandRegistry,
  name : CommandName,
  handler : (Request) -> Result[Response, CommandFailure],
) -> Unit raise IpcError {
  let erased : JsonHandler = fn(payload) {
    let request : Request = @json.from_json(payload) catch {
      error =>
        return Err(
          CommandFailure::new(code="invalid_payload", message=error.to_string()),
        )
    }
    match handler(request) {
      Ok(response) => Ok(ToJson::to_json(response))
      Err(failure) => Err(failure)
    }
  }
  self.register_json(name, erased)
}

///|
pub fn CommandRegistry::contains(
  self : CommandRegistry,
  name : CommandName,
) -> Bool {
  self.handlers.contains(name.value())
}

///|
pub fn CommandRegistry::length(self : CommandRegistry) -> Int {
  self.handlers.length()
}

///|
pub fn CommandRegistry::dispatch(
  self : CommandRegistry,
  source : StringView,
) -> String {
  let request = decode_request(source) catch {
    error =>
      return encode_response(
        Failure(extract_request_id(source), error.failure()),
      )
  }
  let id = request.id()
  match self.handlers.get(request.command().value()) {
    None =>
      encode_response(
        Failure(
          Some(id),
          CommandFailure::new(
            code="unknown_command",
            message="unknown command: \{request.command().value()}",
          ),
        ),
      )
    Some(handler) =>
      match handler(request.payload()) {
        Ok(result) => encode_response(Success(id, result))
        Err(failure) => encode_response(Failure(Some(id), failure))
      }
  }
}
