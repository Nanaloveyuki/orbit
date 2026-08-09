///|
fn http_test_policy() -> @ipc.CommandPolicy raise @ipc.IpcError {
  let policy = @ipc.CommandPolicy::new()
  policy.add_grant(
    @ipc.CommandGrant::new(
      identifier="http-echo",
      effect=@ipc.CapabilityEffect::allow(),
      principals=[@ipc.PrincipalSelector::http_client("sync-client")],
      scopes=[
        @ipc.InvocationScope::transport(@ipc.InvocationTransport::http()),
        @ipc.InvocationScope::origin("https://app.example"),
      ],
      commands=[@ipc.CommandName::new("echo")],
    ),
  )
  policy
}

///|
fn http_test_adapter(
  authenticate : (HttpRequestMetadata) -> AuthenticatedHttpClient?,
) -> HttpAdapter raise {
  let registry = @ipc.CommandRegistry::new()
  registry.register_async_json(@ipc.CommandName::new("echo"), async fn(value) {
    @async.pause()
    Ok(value)
  })
  HttpAdapter::new(registry, http_test_policy(), authenticate)
}

///|
fn http_request(
  meth : @http.RequestMethod,
  path? : String = "/orbit/v1/invoke",
  origin? : String = "https://app.example",
  authorization? : String = "Bearer secret",
) -> @http.Request {
  {
    meth,
    path,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "origin": origin,
      "authorization": authorization,
    },
  }
}

///|
fn test_authenticator(
  metadata : HttpRequestMetadata,
) -> AuthenticatedHttpClient? {
  if metadata.header("Authorization") == Some("Bearer secret") {
    Some({ identifier: "sync-client" })
  } else {
    None
  }
}

///|
test "HTTP adapter validates configuration and authenticated identities" {
  assert_eq(
    AuthenticatedHttpClient::new("sync-client").identifier(),
    "sync-client",
  )
  let invalid_client = try {
    ignore(AuthenticatedHttpClient::new("not valid"))
    false
  } catch {
    InvalidAuthenticatedClient(_) => true
    _ => false
  }
  assert_true(invalid_client)
  let invalid_path = try {
    ignore(
      HttpAdapter::new(
        @ipc.CommandRegistry::new(),
        @ipc.CommandPolicy::new(),
        _ => None,
        endpoint_path="relative",
      ),
    )
    false
  } catch {
    InvalidAdapterConfiguration(_) => true
    _ => false
  }
  assert_true(invalid_path)
}

///|
test "HTTP authentication metadata excludes bodies and normalizes header lookup" {
  let observed = Ref(false)
  let adapter = http_test_adapter(metadata => {
    observed.val = metadata.path() == "/orbit/v1/invoke" &&
      metadata.remote_address() == "127.0.0.1:4123" &&
      metadata.header("AUTHORIZATION") == Some("Bearer secret")
    Some({ identifier: "sync-client" })
  })
  let prepared = adapter.prepare(http_request(Post), "127.0.0.1:4123")
  assert_true(prepared is Ok(_))
  assert_true(observed.val)
}

///|
async test "HTTP adapter reuses principal origin authorization and async deadlines" {
  let adapter = http_test_adapter(test_authenticator)
  let allowed = adapter.prepare(http_request(Post), "127.0.0.1:4123").unwrap()
  let response = adapter.dispatch_source(
    allowed, "{\"version\":1,\"type\":\"invoke\",\"id\":\"http-ok\",\"command\":\"echo\",\"payload\":7,\"timeout_ms\":1000}",
  )
  assert_eq(response.status, 200)
  assert_true(response.body.contains("\"result\":7"))
  let denied = adapter
    .prepare(
      http_request(Post, origin="https://other.example"),
      "127.0.0.1:4123",
    )
    .unwrap()
  let denied_response = adapter.dispatch_source(
    denied, "{\"version\":1,\"type\":\"invoke\",\"id\":\"http-deny\",\"command\":\"echo\",\"payload\":7,\"timeout_ms\":1000}",
  )
  assert_true(denied_response.body.contains("\"code\":\"permission_denied\""))
}

///|
test "HTTP adapter rejects unauthenticated, wrong-method and wrong-media requests" {
  let adapter = http_test_adapter(test_authenticator)
  let unauthorized = adapter.prepare(
    http_request(Post, authorization="Bearer wrong"),
    "127.0.0.1:4123",
  )
  assert_true(unauthorized is Err({ status: 401, .. }))
  let wrong_method = adapter.prepare(http_request(Get), "127.0.0.1:4123")
  assert_true(wrong_method is Err({ status: 405, .. }))
  let missing = http_request(Post)
  missing.headers.remove("content-type")
  let wrong_media = adapter.prepare(missing, "127.0.0.1:4123")
  assert_true(wrong_media is Err({ status: 415, .. }))
  let wrong_path = adapter.prepare(
    http_request(Post, path="/other"),
    "127.0.0.1:4123",
  )
  assert_true(wrong_path is Err({ status: 404, .. }))
}

///|
test "HTTP adapter rejects ambiguous and oversized body framing" {
  let ambiguous : Map[String, String] = {
    "content-length": "10",
    "transfer-encoding": "chunked",
  }
  assert_true(validate_body_headers(ambiguous, 256) is Err({ status: 400, .. }))
  assert_true(
    validate_body_headers({ "content-length": "257" }, 256)
    is Err({ status: 413, .. }),
  )
  assert_true(
    validate_body_headers({ "content-length": "invalid" }, 256)
    is Err({ status: 400, .. }),
  )
}
