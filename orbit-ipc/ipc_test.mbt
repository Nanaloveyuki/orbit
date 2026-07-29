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
test "strict IPC parsing rejects duplicate envelope fields" {
  let response = CommandRegistry::new().dispatch(
    "{\"version\":1,\"version\":1,\"id\":\"req-duplicate\",\"command\":\"echo\",\"payload\":null}",
  )
  assert_true(response.contains("\"code\":\"invalid_request\""))
  assert_true(response.contains("duplicate JSON key"))
}

///|
test "strict IPC parsing rejects duplicate payload fields" {
  let response = CommandRegistry::new().dispatch(
    "{\"version\":1,\"id\":\"req-payload-duplicate\",\"command\":\"echo\",\"payload\":{\"value\":1,\"value\":2}}",
  )
  assert_true(response.contains("\"code\":\"invalid_request\""))
  assert_true(response.contains("duplicate JSON key"))
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

///|
test "capabilities grant only listed commands to the matching window" {
  let registry = CommandRegistry::new()
  registry.register_json(CommandName::new("allowed"), value => Ok(value))
  registry.register_json(CommandName::new("denied"), value => Ok(value))
  let policy = CommandPolicy::new()
  policy.add(
    CommandCapability::new(identifier="main-commands", windows=["main"], commands=[
      CommandName::new("allowed"),
    ]),
  )
  let allowed = registry.dispatch_for_window(
    "{\"version\":1,\"id\":\"req-6\",\"command\":\"allowed\",\"payload\":null}",
    policy, "main",
  )
  let denied = registry.dispatch_for_window(
    "{\"version\":1,\"id\":\"req-7\",\"command\":\"denied\",\"payload\":null}", policy,
    "main",
  )
  assert_true(allowed.contains("\"ok\":true"))
  assert_true(denied.contains("\"code\":\"permission_denied\""))
}

///|
test "capabilities do not cross window boundaries" {
  let registry = CommandRegistry::new()
  registry.register_json(CommandName::new("echo"), value => Ok(value))
  let policy = CommandPolicy::new()
  policy.add(
    CommandCapability::new(identifier="main-commands", windows=["main"], commands=[
      CommandName::new("echo"),
    ]),
  )
  let response = registry.dispatch_for_window(
    "{\"version\":1,\"id\":\"req-8\",\"command\":\"echo\",\"payload\":null}", policy,
    "settings",
  )
  assert_true(response.contains("\"code\":\"permission_denied\""))
}

///|
test "capability identifiers are unique within a policy" {
  let policy = CommandPolicy::new()
  let capability = CommandCapability::new(
    identifier="main-commands",
    windows=["main"],
    commands=[CommandName::new("echo")],
  )
  policy.add(capability)
  let duplicate = try {
    policy.add(capability)
    false
  } catch {
    DuplicateCapability(_) => true
    _ => false
  }
  assert_true(duplicate)
}
