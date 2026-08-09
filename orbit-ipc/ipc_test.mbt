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
  inspect(
    response,
    content=(
      #|{"version":1,"id":"req-8","ok":false,"error":{"code":"permission_denied","message":"command is not permitted for window: settings","data":null}}
    ),
  )
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

///|
test "context grants require the matching authenticated principal and origin" {
  let registry = CommandRegistry::new()
  registry.register_context_json(CommandName::new("context.echo"), fn(
    context,
    value,
  ) {
    match context.principal() {
      HttpClient("remote-app") => Ok(value)
      _ =>
        Err(CommandFailure::new(code="wrong_principal", message="unexpected"))
    }
  })
  let policy = CommandPolicy::new()
  policy.add_grant(
    CommandGrant::new(
      identifier="remote-app-echo",
      effect=CapabilityEffect::allow(),
      principals=[PrincipalSelector::http_client("remote-app")],
      scopes=[
        InvocationScope::transport(InvocationTransport::http()),
        InvocationScope::origin("https://app.example"),
      ],
      commands=[CommandName::new("context.echo")],
    ),
  )
  let allowed = registry.dispatch_with_context(
    "{\"version\":1,\"id\":\"req-remote\",\"command\":\"context.echo\",\"payload\":null}",
    policy,
    InvocationContext::http_client("remote-app", origin="https://app.example"),
  )
  let denied = registry.dispatch_with_context(
    "{\"version\":1,\"id\":\"req-other\",\"command\":\"context.echo\",\"payload\":null}",
    policy,
    InvocationContext::http_client("remote-app", origin="https://other.example"),
  )
  assert_true(allowed.contains("\"ok\":true"))
  assert_true(denied.contains("\"code\":\"permission_denied\""))
}

///|
test "deny grants override matching legacy window capabilities" {
  let registry = CommandRegistry::new()
  registry.register_json(CommandName::new("settings.read"), value => Ok(value))
  let policy = CommandPolicy::new()
  policy.add(
    CommandCapability::new(identifier="main-commands", windows=["main"], commands=[
      CommandName::new("settings.read"),
    ]),
  )
  policy.add_grant(
    CommandGrant::new(
      identifier="main-deny",
      effect=CapabilityEffect::deny(),
      principals=[PrincipalSelector::window("main")],
      commands=[CommandName::new("settings.read")],
    ),
  )
  let response = registry.dispatch_for_window(
    "{\"version\":1,\"id\":\"req-deny\",\"command\":\"settings.read\",\"payload\":null}",
    policy, "main",
  )
  assert_true(response.contains("\"code\":\"permission_denied\""))
}

///|
test "context response limits reject oversized serialized responses" {
  let registry = CommandRegistry::new()
  registry.register_json(CommandName::new("large"), fn(_) {
    Ok(Json::string("x".repeat(512)))
  })
  let policy = CommandPolicy::new()
  policy.add_grant(
    CommandGrant::new(
      identifier="background-large",
      effect=CapabilityEffect::allow(),
      principals=[PrincipalSelector::background_task("worker")],
      commands=[CommandName::new("large")],
    ),
  )
  let context = InvocationContext::background_task("worker").with_response_limit(
    256,
  )
  let response = registry.dispatch_with_context(
    "{\"version\":1,\"id\":\"req-large\",\"command\":\"large\",\"payload\":null}",
    policy, context,
  )
  assert_true(response.contains("\"code\":\"response_too_large\""))
}

///|
test "remote pages are distinct MoonView principals with origin scopes" {
  let registry = CommandRegistry::new()
  registry.register_json(CommandName::new("remote.echo"), payload => Ok(payload))
  let policy = CommandPolicy::new()
  policy.add_grant(
    CommandGrant::new(
      identifier="remote-page",
      effect=CapabilityEffect::allow(),
      principals=[PrincipalSelector::remote_page("main")],
      scopes=[
        InvocationScope::transport(InvocationTransport::moonview()),
        InvocationScope::origin("https://app.example"),
      ],
      commands=[CommandName::new("remote.echo")],
    ),
  )
  let request = "{\"version\":1,\"id\":\"req-remote-page\",\"command\":\"remote.echo\",\"payload\":null}"
  let allowed = registry.dispatch_with_context(
    request,
    policy,
    InvocationContext::remote_page("main", origin=Some("https://app.example")),
  )
  let window = registry.dispatch_with_context(
    request,
    policy,
    InvocationContext::window("main"),
  )
  let other_origin = registry.dispatch_with_context(
    request,
    policy,
    InvocationContext::remote_page("main", origin=Some("https://other.example")),
  )
  assert_true(allowed.contains("\"ok\":true"))
  assert_true(window.contains("\"code\":\"permission_denied\""))
  assert_true(other_origin.contains("\"code\":\"permission_denied\""))
}

///|
test "invocation requests carry bounded host deadlines" {
  let legacy = decode_request(
    "{\"version\":1,\"id\":\"legacy\",\"command\":\"echo\",\"payload\":null}",
  )
  assert_eq(legacy.timeout_ms(), 30_000)
  let explicit = decode_request(
    "{\"version\":1,\"type\":\"invoke\",\"id\":\"explicit\",\"command\":\"echo\",\"payload\":null,\"timeout_ms\":1250}",
  )
  assert_eq(explicit.timeout_ms(), 1_250)
  let rejected = CommandRegistry::new().dispatch(
    "{\"version\":1,\"type\":\"invoke\",\"id\":\"invalid-timeout\",\"command\":\"echo\",\"payload\":null,\"timeout_ms\":0}",
  )
  assert_true(rejected.contains("\"code\":\"invalid_request\""))
  assert_true(rejected.contains("timeout_ms"))
}

///|
test "cancellation messages contain only an invocation id" {
  match
    decode_client_message(
      "{\"version\":1,\"type\":\"cancel\",\"id\":\"cancel-me\"}",
    ) {
    Cancel(id) => assert_eq(id.value(), "cancel-me")
    Invoke(_) => abort("expected a cancellation message")
  }
  let rejected = try {
    ignore(
      decode_client_message(
        "{\"version\":1,\"type\":\"cancel\",\"id\":\"cancel-me\",\"payload\":null}",
      ),
    )
    false
  } catch {
    MalformedEnvelope(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
async test "async dispatch supports synchronous and asynchronous handlers" {
  let registry = CommandRegistry::new()
  registry.register_json(CommandName::new("sync.echo"), payload => Ok(payload))
  registry.register_async_json(CommandName::new("async.echo"), async fn(
    payload,
  ) {
    @async.pause()
    Ok(payload)
  })
  let sync_response = registry.dispatch_async(
    "{\"version\":1,\"id\":\"sync\",\"command\":\"sync.echo\",\"payload\":7}",
  )
  let async_response = registry.dispatch_async(
    "{\"version\":1,\"id\":\"async\",\"command\":\"async.echo\",\"payload\":8}",
  )
  assert_true(sync_response.contains("\"result\":7"))
  assert_true(async_response.contains("\"result\":8"))
  let unavailable = registry.dispatch(
    "{\"version\":1,\"id\":\"blocked\",\"command\":\"async.echo\",\"payload\":null}",
  )
  assert_true(unavailable.contains("\"code\":\"async_unavailable\""))
}

///|
async test "async handlers observe transport cancellation tokens" {
  let registry = CommandRegistry::new()
  registry.register_async_context_json(CommandName::new("cancel.check"), async fn(
    context,
    _,
  ) {
    @async.pause()
    if context.cancellation().is_cancelled() {
      Err(CommandFailure::new(code="cancelled", message="cancelled"))
    } else {
      Ok(Json::null())
    }
  })
  let policy = CommandPolicy::new()
  policy.add_grant(
    CommandGrant::new(
      identifier="background-cancel",
      effect=CapabilityEffect::allow(),
      principals=[PrincipalSelector::background_task("worker")],
      commands=[CommandName::new("cancel.check")],
    ),
  )
  let context = InvocationContext::background_task("worker")
  context.cancellation().cancel()
  let response = registry.dispatch_with_context_async(
    "{\"version\":1,\"id\":\"cancelled\",\"command\":\"cancel.check\",\"payload\":null}",
    policy, context,
  )
  assert_true(response.contains("\"code\":\"cancelled\""))
}
