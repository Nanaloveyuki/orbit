///|
async test "authenticated HTTP and window adapters share command policy behavior" {
  let registry = @ipc.CommandRegistry::new()
  registry.register_json(@ipc.CommandName::new("shared.echo"), value => {
    Ok(value)
  })
  registry.register_json(@ipc.CommandName::new("private.read"), value => {
    Ok(value)
  })
  let policy = @ipc.CommandPolicy::new()
  policy.add(
    @ipc.CommandCapability::new(identifier="window-shared", windows=["main"], commands=[
      @ipc.CommandName::new("shared.echo"),
    ]),
  )
  policy.add_grant(
    @ipc.CommandGrant::new(
      identifier="http-shared",
      effect=@ipc.CapabilityEffect::allow(),
      principals=[@ipc.PrincipalSelector::http_client("sync-client")],
      scopes=[
        @ipc.InvocationScope::transport(@ipc.InvocationTransport::http()),
        @ipc.InvocationScope::origin("https://app.example"),
      ],
      commands=[@ipc.CommandName::new("shared.echo")],
    ),
  )
  let authenticated = AuthenticatedHttpClient::new("sync-client")
  let adapter = HttpAdapter::new(registry, policy, metadata => {
    if metadata.header("authorization") == Some("Bearer integration-secret") {
      Some(authenticated)
    } else {
      None
    }
  })
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      adapter.serve(server, max_connections=4)
    }
    let invoke = "{\"version\":1,\"type\":\"invoke\",\"id\":\"same\",\"command\":\"shared.echo\",\"payload\":{\"value\":7},\"timeout_ms\":1000}"
    let window_response = registry.dispatch_for_window(invoke, policy, "main")
    let (http_response, http_body) = @http.post(
      "http://localhost:\{server.addr.port()}/orbit/v1/invoke",
      invoke,
      headers={
        "Authorization": "Bearer integration-secret",
        "Content-Type": "application/json",
        "Origin": "https://app.example",
      },
    )
    assert_eq(http_response.code, 200)
    assert_eq(http_body.text(), window_response)
    let denied = invoke.replace_all(old="shared.echo", new="private.read")
    let window_denied = registry.dispatch_for_window(denied, policy, "main")
    let (http_denied_response, http_denied_body) = @http.post(
      "http://localhost:\{server.addr.port()}/orbit/v1/invoke",
      denied,
      headers={
        "Authorization": "Bearer integration-secret",
        "Content-Type": "application/json",
        "Origin": "https://app.example",
      },
    )
    assert_eq(http_denied_response.code, 200)
    assert_true(window_denied.contains("\"code\":\"permission_denied\""))
    assert_true(
      http_denied_body.text().contains("\"code\":\"permission_denied\""),
    )
  }
}
