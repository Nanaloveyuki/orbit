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
  let registry = @orbit-ipc.CommandRegistry::new()
  registry.register(@orbit-ipc.CommandName::new("math.add"), fn(
    request : AddRequest,
  ) {
    Ok(AddResponse::{ value: request.left + request.right, })
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
  let registry = @orbit-ipc.CommandRegistry::new()
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
  let registry = @orbit-ipc.CommandRegistry::new()
  let response = registry.dispatch("{\"version\":1.5}")
  assert_true(response.contains("\"id\":null"))
  assert_true(response.contains("\"code\":\"invalid_request\""))
}

///|
test "strict IPC parsing rejects duplicate envelope fields" {
  let response = @orbit-ipc.CommandRegistry::new().dispatch(
    "{\"version\":1,\"version\":1,\"id\":\"req-duplicate\",\"command\":\"echo\",\"payload\":null}",
  )
  assert_true(response.contains("\"code\":\"invalid_request\""))
  assert_true(response.contains("duplicate JSON key"))
}

///|
test "strict IPC parsing rejects duplicate payload fields" {
  let response = @orbit-ipc.CommandRegistry::new().dispatch(
    "{\"version\":1,\"id\":\"req-payload-duplicate\",\"command\":\"echo\",\"payload\":{\"value\":1,\"value\":2}}",
  )
  assert_true(response.contains("\"code\":\"invalid_request\""))
  assert_true(response.contains("duplicate JSON key"))
}

///|
test "duplicate registrations are checked errors" {
  let registry = @orbit-ipc.CommandRegistry::new()
  let name = @orbit-ipc.CommandName::new("echo")
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
  let registry = @orbit-ipc.CommandRegistry::new()
  registry.register(@orbit-ipc.CommandName::new("math.add"), fn(
    request : AddRequest,
  ) {
    Ok(AddResponse::{ value: request.left + request.right, })
  })
  let response = registry.dispatch(
    "{\"version\":1,\"id\":\"req-2\",\"command\":\"math.add\",\"payload\":{\"left\":\"two\",\"right\":3}}",
  )
  assert_true(response.contains("\"code\":\"invalid_payload\""))
  assert_true(response.contains("\"id\":\"req-2\""))
}

///|
test "handler failures keep their explicit wire code" {
  let registry = @orbit-ipc.CommandRegistry::new()
  registry.register_json(@orbit-ipc.CommandName::new("fail"), fn(_) {
    Err(
      @orbit-ipc.CommandFailure::new(
        code="not_ready",
        message="runtime is not ready",
        data={ "retryable": true },
      ),
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
  let response = @orbit-ipc.CommandRegistry::new().dispatch(
    "{\"version\":2,\"id\":\"req-4\",\"command\":\"echo\",\"payload\":null}",
  )
  assert_true(response.contains("\"code\":\"unsupported_version\""))
}

///|
test "validation failures preserve an already valid invocation id" {
  let response = @orbit-ipc.CommandRegistry::new().dispatch(
    "{\"version\":1,\"id\":\"req-5\",\"command\":\"bad command\",\"payload\":null}",
  )
  assert_true(response.contains("\"id\":\"req-5\""))
  assert_true(response.contains("\"code\":\"invalid_request\""))
}

///|
test "capabilities grant only listed commands to the matching window" {
  let registry = @orbit-ipc.CommandRegistry::new()
  registry.register_json(@orbit-ipc.CommandName::new("allowed"), value => {
    Ok(value)
  })
  registry.register_json(@orbit-ipc.CommandName::new("denied"), value => {
    Ok(value)
  })
  let policy = @orbit-ipc.CommandPolicy::new()
  policy.add(
    @orbit-ipc.CommandCapability::new(
      identifier="main-commands",
      windows=["main"],
      commands=[@orbit-ipc.CommandName::new("allowed")],
    ),
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
  let registry = @orbit-ipc.CommandRegistry::new()
  registry.register_json(@orbit-ipc.CommandName::new("echo"), value => Ok(value))
  let policy = @orbit-ipc.CommandPolicy::new()
  policy.add(
    @orbit-ipc.CommandCapability::new(
      identifier="main-commands",
      windows=["main"],
      commands=[@orbit-ipc.CommandName::new("echo")],
    ),
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
  let policy = @orbit-ipc.CommandPolicy::new()
  let capability = @orbit-ipc.CommandCapability::new(
    identifier="main-commands",
    windows=["main"],
    commands=[@orbit-ipc.CommandName::new("echo")],
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
  let registry = @orbit-ipc.CommandRegistry::new()
  registry.register_context_json(@orbit-ipc.CommandName::new("context.echo"), fn(
    context,
    value,
  ) {
    match context.principal() {
      HttpClient("remote-app") => Ok(value)
      _ =>
        Err(
          @orbit-ipc.CommandFailure::new(
            code="wrong_principal",
            message="unexpected",
          ),
        )
    }
  })
  let policy = @orbit-ipc.CommandPolicy::new()
  policy.add_grant(
    @orbit-ipc.CommandGrant::new(
      identifier="remote-app-echo",
      effect=@orbit-ipc.CapabilityEffect::allow(),
      principals=[@orbit-ipc.PrincipalSelector::http_client("remote-app")],
      scopes=[
        @orbit-ipc.InvocationScope::transport(
          @orbit-ipc.InvocationTransport::http(),
        ),
        @orbit-ipc.InvocationScope::origin("https://app.example"),
      ],
      commands=[@orbit-ipc.CommandName::new("context.echo")],
    ),
  )
  let allowed = registry.dispatch_with_context(
    "{\"version\":1,\"id\":\"req-remote\",\"command\":\"context.echo\",\"payload\":null}",
    policy,
    @orbit-ipc.InvocationContext::http_client(
      "remote-app",
      origin="https://app.example",
    ),
  )
  let denied = registry.dispatch_with_context(
    "{\"version\":1,\"id\":\"req-other\",\"command\":\"context.echo\",\"payload\":null}",
    policy,
    @orbit-ipc.InvocationContext::http_client(
      "remote-app",
      origin="https://other.example",
    ),
  )
  assert_true(allowed.contains("\"ok\":true"))
  assert_true(denied.contains("\"code\":\"permission_denied\""))
}

///|
test "deny grants override matching legacy window capabilities" {
  let registry = @orbit-ipc.CommandRegistry::new()
  registry.register_json(@orbit-ipc.CommandName::new("settings.read"), value => {
    Ok(value)
  })
  let policy = @orbit-ipc.CommandPolicy::new()
  policy.add(
    @orbit-ipc.CommandCapability::new(
      identifier="main-commands",
      windows=["main"],
      commands=[@orbit-ipc.CommandName::new("settings.read")],
    ),
  )
  policy.add_grant(
    @orbit-ipc.CommandGrant::new(
      identifier="main-deny",
      effect=@orbit-ipc.CapabilityEffect::deny(),
      principals=[@orbit-ipc.PrincipalSelector::window("main")],
      commands=[@orbit-ipc.CommandName::new("settings.read")],
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
  let registry = @orbit-ipc.CommandRegistry::new()
  registry.register_json(@orbit-ipc.CommandName::new("large"), fn(_) {
    Ok(Json::string("x".repeat(512)))
  })
  let policy = @orbit-ipc.CommandPolicy::new()
  policy.add_grant(
    @orbit-ipc.CommandGrant::new(
      identifier="background-large",
      effect=@orbit-ipc.CapabilityEffect::allow(),
      principals=[@orbit-ipc.PrincipalSelector::background_task("worker")],
      commands=[@orbit-ipc.CommandName::new("large")],
    ),
  )
  let context = @orbit-ipc.InvocationContext::background_task("worker").with_response_limit(
    256,
  )
  let response = registry.dispatch_with_context(
    "{\"version\":1,\"id\":\"req-large\",\"command\":\"large\",\"payload\":null}",
    policy, context,
  )
  assert_true(response.contains("\"code\":\"response_too_large\""))
}

///|
async test "response limit uses UTF16 units for sync and async handlers" {
  let registry = @orbit-ipc.CommandRegistry::new()
  registry.register_json(@orbit-ipc.CommandName::new("sync.echo"), payload => {
    Ok(payload)
  })
  registry.register_async_json(@orbit-ipc.CommandName::new("async.echo"), async fn(
    payload,
  ) {
    @async.pause()
    Ok(payload)
  })
  let policy = @orbit-ipc.CommandPolicy::new()
  policy.add_grant(
    @orbit-ipc.CommandGrant::new(
      identifier="unicode",
      effect=@orbit-ipc.CapabilityEffect::allow(),
      principals=[@orbit-ipc.PrincipalSelector::window("main")],
      commands=[
        @orbit-ipc.CommandName::new("sync.echo"),
        @orbit-ipc.CommandName::new("async.echo"),
      ],
    ),
  )
  let id = @orbit-ipc.InvocationId::new("unicode")
  let overhead = @orbit-ipc.encode_response(Success(id, Json::string(""))).length()
  let payload = "\u{1F600}".repeat(110)
  let limit = overhead + payload.length()
  for command in ["sync.echo", "async.echo"] {
    let source = "{\"version\":1,\"id\":\"unicode\",\"command\":\"\{command}\",\"payload\":\"\{payload}\"}"
    let accepted = registry.dispatch_with_context_async(
      source,
      policy,
      @orbit-ipc.InvocationContext::window("main").with_response_limit(limit),
    )
    assert_true(accepted.contains("\"ok\":true"))
    assert_eq(accepted.length(), limit)
    let rejected = registry.dispatch_with_context_async(
      source,
      policy,
      @orbit-ipc.InvocationContext::window("main").with_response_limit(
        limit - 1,
      ),
    )
    assert_true(rejected.contains("response_too_large"))
    if command == "sync.echo" {
      assert_eq(
        registry.dispatch_with_context(
          source,
          policy,
          @orbit-ipc.InvocationContext::window("main").with_response_limit(
            limit,
          ),
        ),
        accepted,
      )
      assert_eq(
        registry.dispatch_with_context(
          source,
          policy,
          @orbit-ipc.InvocationContext::window("main").with_response_limit(
            limit - 1,
          ),
        ),
        rejected,
      )
    }
  }
}

///|
test "remote pages are distinct MoonView principals with origin scopes" {
  let registry = @orbit-ipc.CommandRegistry::new()
  registry.register_json(@orbit-ipc.CommandName::new("remote.echo"), payload => {
    Ok(payload)
  })
  let policy = @orbit-ipc.CommandPolicy::new()
  policy.add_grant(
    @orbit-ipc.CommandGrant::new(
      identifier="remote-page",
      effect=@orbit-ipc.CapabilityEffect::allow(),
      principals=[@orbit-ipc.PrincipalSelector::remote_page("main")],
      scopes=[
        @orbit-ipc.InvocationScope::transport(
          @orbit-ipc.InvocationTransport::moonview(),
        ),
        @orbit-ipc.InvocationScope::origin("https://app.example"),
      ],
      commands=[@orbit-ipc.CommandName::new("remote.echo")],
    ),
  )
  let request = "{\"version\":1,\"id\":\"req-remote-page\",\"command\":\"remote.echo\",\"payload\":null}"
  let allowed = registry.dispatch_with_context(
    request,
    policy,
    @orbit-ipc.InvocationContext::remote_page(
      "main",
      origin=Some("https://app.example"),
    ),
  )
  let window = registry.dispatch_with_context(
    request,
    policy,
    @orbit-ipc.InvocationContext::window("main"),
  )
  let other_origin = registry.dispatch_with_context(
    request,
    policy,
    @orbit-ipc.InvocationContext::remote_page(
      "main",
      origin=Some("https://other.example"),
    ),
  )
  assert_true(allowed.contains("\"ok\":true"))
  assert_true(window.contains("\"code\":\"permission_denied\""))
  assert_true(other_origin.contains("\"code\":\"permission_denied\""))
}

///|
test "invocation requests carry bounded host deadlines" {
  let legacy = @orbit-ipc.decode_request(
    "{\"version\":1,\"id\":\"legacy\",\"command\":\"echo\",\"payload\":null}",
  )
  assert_eq(legacy.timeout_ms(), 30_000)
  let explicit = @orbit-ipc.decode_request(
    "{\"version\":1,\"type\":\"invoke\",\"id\":\"explicit\",\"command\":\"echo\",\"payload\":null,\"timeout_ms\":1250}",
  )
  assert_eq(explicit.timeout_ms(), 1_250)
  let rejected = @orbit-ipc.CommandRegistry::new().dispatch(
    "{\"version\":1,\"type\":\"invoke\",\"id\":\"invalid-timeout\",\"command\":\"echo\",\"payload\":null,\"timeout_ms\":0}",
  )
  assert_true(rejected.contains("\"code\":\"invalid_request\""))
  assert_true(rejected.contains("timeout_ms"))
}

///|
test "cancellation messages contain only an invocation id" {
  match
    @orbit-ipc.decode_client_message(
      "{\"version\":1,\"type\":\"cancel\",\"id\":\"cancel-me\"}",
    ) {
    Cancel(id) => assert_eq(id.value(), "cancel-me")
    Invoke(_) => abort("expected a cancellation message")
  }
  let rejected = try {
    ignore(
      @orbit-ipc.decode_client_message(
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
  let registry = @orbit-ipc.CommandRegistry::new()
  registry.register_json(@orbit-ipc.CommandName::new("sync.echo"), payload => {
    Ok(payload)
  })
  registry.register_async_json(@orbit-ipc.CommandName::new("async.echo"), async fn(
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
  let registry = @orbit-ipc.CommandRegistry::new()
  registry.register_async_context_json(
    @orbit-ipc.CommandName::new("cancel.check"),
    async fn(context, _) {
      @async.pause()
      if context.cancellation().is_cancelled() {
        Err(
          @orbit-ipc.CommandFailure::new(code="cancelled", message="cancelled"),
        )
      } else {
        Ok(Json::null())
      }
    },
  )
  let policy = @orbit-ipc.CommandPolicy::new()
  policy.add_grant(
    @orbit-ipc.CommandGrant::new(
      identifier="background-cancel",
      effect=@orbit-ipc.CapabilityEffect::allow(),
      principals=[@orbit-ipc.PrincipalSelector::background_task("worker")],
      commands=[@orbit-ipc.CommandName::new("cancel.check")],
    ),
  )
  let context = @orbit-ipc.InvocationContext::background_task("worker")
  context.cancellation().cancel()
  let response = registry.dispatch_with_context_async(
    "{\"version\":1,\"id\":\"cancelled\",\"command\":\"cancel.check\",\"payload\":null}",
    policy, context,
  )
  assert_true(response.contains("\"code\":\"cancelled\""))
}
