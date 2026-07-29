///|
type ContextJsonHandler = (InvocationContext, Json) -> Result[
  Json,
  CommandFailure,
]

///|
pub struct CommandRegistry {
  priv handlers : Map[String, ContextJsonHandler]
}

///|
pub fn CommandRegistry::new() -> CommandRegistry {
  { handlers: Map([]) }
}

///|
pub fn CommandRegistry::register_json(
  self : CommandRegistry,
  name : CommandName,
  handler : (Json) -> Result[Json, CommandFailure],
) -> Unit raise IpcError {
  self.register_context_json(name, fn(_, payload) { handler(payload) })
}

///|
pub fn CommandRegistry::register_context_json(
  self : CommandRegistry,
  name : CommandName,
  handler : ContextJsonHandler,
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
  let erased : ContextJsonHandler = fn(_, payload) {
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
  self.register_context_json(name, erased)
}

///|
pub fn[Request : @json.FromJson, Response : ToJson] CommandRegistry::register_context(
  self : CommandRegistry,
  name : CommandName,
  handler : (InvocationContext, Request) -> Result[Response, CommandFailure],
) -> Unit raise IpcError {
  let erased : ContextJsonHandler = fn(context, payload) {
    let request : Request = @json.from_json(payload) catch {
      error =>
        return Err(
          CommandFailure::new(code="invalid_payload", message=error.to_string()),
        )
    }
    match handler(context, request) {
      Ok(response) => Ok(ToJson::to_json(response))
      Err(failure) => Err(failure)
    }
  }
  self.register_context_json(name, erased)
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
  self.dispatch_limited(
    context(Background, BackgroundTask("local"), None),
    request,
  )
}

///|
pub fn CommandRegistry::dispatch_with_context(
  self : CommandRegistry,
  source : StringView,
  policy : CommandPolicy,
  context : InvocationContext,
) -> String {
  self.dispatch_authorized(
    source,
    policy,
    context,
    context.principal().description(),
  )
}

///|
pub fn CommandRegistry::dispatch_for_window(
  self : CommandRegistry,
  source : StringView,
  policy : CommandPolicy,
  window_label : String,
) -> String {
  let context = context(MoonView, Window(window_label), None)
  self.dispatch_authorized(source, policy, context, "window: \{window_label}")
}

///|
fn CommandRegistry::dispatch_authorized(
  self : CommandRegistry,
  source : StringView,
  policy : CommandPolicy,
  context : InvocationContext,
  principal_description : String,
) -> String {
  let request = decode_request(source) catch {
    error =>
      return encode_response(
        Failure(extract_request_id(source), error.failure()),
      )
  }
  let id = request.id()
  let command = request.command()
  if !policy.allows_context(context, command) {
    return encode_response(
      Failure(
        Some(id),
        CommandFailure::new(
          code="permission_denied",
          message="command is not permitted for \{principal_description}",
        ),
      ),
    )
  }
  self.dispatch_limited(context, request)
}

///|
fn CommandRegistry::dispatch_limited(
  self : CommandRegistry,
  context : InvocationContext,
  request : InvocationRequest,
) -> String {
  let id = request.id()
  let response = self.dispatch_request(context, request)
  if response.length() > context.max_response_chars() {
    return encode_response(
      Failure(
        Some(id),
        CommandFailure::new(
          code="response_too_large",
          message="IPC response exceeds the configured limit",
        ),
      ),
    )
  }
  response
}

///|
fn CommandRegistry::dispatch_request(
  self : CommandRegistry,
  context : InvocationContext,
  request : InvocationRequest,
) -> String {
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
      match handler(context, request.payload()) {
        Ok(result) => encode_response(Success(id, result))
        Err(failure) => encode_response(Failure(Some(id), failure))
      }
  }
}
