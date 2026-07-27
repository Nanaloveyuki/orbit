///|
priv struct AddRequest {
  left : Int
  right : Int
} derive(FromJson)

///|
priv struct AddResponse {
  value : Int
} derive(ToJson)

///|
test "typed commands preserve string invocation ids" {
  let registry = CommandRegistry::new()
  registry.register(CommandName::new("math.add"), fn(request : AddRequest) {
    Ok(AddResponse::{ value: request.left + request.right })
  })
  let response = registry.dispatch(
    "{\"version\":1,\"id\":\"9007199254740993\",\"command\":\"math.add\",\"payload\":{\"left\":2,\"right\":3}}",
  )
  inspect(
    response,
    content=(
      #|{"version":1,"id":"9007199254740993","ok":true,"result":{"value":5}}
    ),
  )
}

///|
test "unknown commands return structured failures" {
  let registry = CommandRegistry::new()
  let response = registry.dispatch(
    "{\"version\":1,\"id\":\"req-1\",\"command\":\"missing\",\"payload\":null}",
  )
  inspect(
    response,
    content=(
      #|{"version":1,"id":"req-1","ok":false,"error":{"code":"unknown_command","message":"unknown command: missing","data":null}}
    ),
  )
}

///|
test "malformed requests never escape the dispatch boundary" {
  let registry = CommandRegistry::new()
  let response = registry.dispatch("{\"version\":1.5}")
  assert_true(response.contains("\"id\":null"))
  assert_true(response.contains("\"code\":\"invalid_request\""))
}

///|
test "duplicate registrations are checked errors" {
  let registry = CommandRegistry::new()
  let name = CommandName::new("echo")
  registry.register_json(name, fn(value) { Ok(value) })
  let duplicate = try {
    registry.register_json(name, fn(value) { Ok(value) })
    false
  } catch {
    DuplicateCommand(_) => true
    _ => false
  }
  assert_true(duplicate)
}

///|
test "typed payload decoding returns protocol failures" {
  let registry = CommandRegistry::new()
  registry.register(CommandName::new("math.add"), fn(request : AddRequest) {
    Ok(AddResponse::{ value: request.left + request.right })
  })
  let response = registry.dispatch(
    "{\"version\":1,\"id\":\"req-2\",\"command\":\"math.add\",\"payload\":{\"left\":\"two\",\"right\":3}}",
  )
  assert_true(response.contains("\"code\":\"invalid_payload\""))
  assert_true(response.contains("\"id\":\"req-2\""))
}

///|
test "handler failures keep their explicit wire code" {
  let registry = CommandRegistry::new()
  registry.register_json(CommandName::new("fail"), fn(_) {
    Err(
      CommandFailure::new(code="not_ready", message="runtime is not ready", data={
        "retryable": true,
      }),
    )
  })
  let response = registry.dispatch(
    "{\"version\":1,\"id\":\"req-3\",\"command\":\"fail\",\"payload\":null}",
  )
  assert_true(response.contains("\"code\":\"not_ready\""))
  assert_true(response.contains("\"data\":{\"retryable\":true}"))
}

///|
test "unsupported protocol versions return a version error" {
  let response = CommandRegistry::new().dispatch(
    "{\"version\":2,\"id\":\"req-4\",\"command\":\"echo\",\"payload\":null}",
  )
  assert_true(response.contains("\"code\":\"unsupported_version\""))
}

///|
test "validation failures preserve an already valid invocation id" {
  let response = CommandRegistry::new().dispatch(
    "{\"version\":1,\"id\":\"req-5\",\"command\":\"bad command\",\"payload\":null}",
  )
  assert_true(response.contains("\"id\":\"req-5\""))
  assert_true(response.contains("\"code\":\"invalid_request\""))
}
