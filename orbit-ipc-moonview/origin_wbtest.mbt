///|
test "embedded origin grants keep the local window principal" {
  let registry = @ipc.CommandRegistry::new()
  let policy = @ipc.CommandPolicy::new()
  let command = @ipc.CommandName::new("fixture.local")
  let origin = "orbit://app"
  registry.register_json(command, _ => Ok(Json::null()))
  policy.add_grant(
    @ipc.CommandGrant::new(
      identifier="trusted-app",
      effect=@ipc.CapabilityEffect::allow(),
      principals=[@ipc.PrincipalSelector::window("main")],
      scopes=[
        @ipc.InvocationScope::transport(@ipc.InvocationTransport::moonview()),
        @ipc.InvocationScope::origin(origin),
      ],
      commands=[command],
    ),
  )
  let body =
    #|{"version":1,"id":"local","command":"fixture.local","payload":null}
  let matching = @runtime.RuntimePageMessage::new(body~, origin=Some(origin))
  guard invocation_context("main", Window, matching) is Some(context) else {
    fail("expected a local window context")
  }
  assert_true(context.principal() is Window("main"))
  assert_eq(context.origin(), Some(origin))
  assert_true(
    dispatch(registry, policy, "main", Window, matching)
    .unwrap()
    .contains("\"ok\":true"),
  )
  for source in [None, Some("orbit://other")] {
    let message = @runtime.RuntimePageMessage::new(body~, origin=source)
    assert_true(
      dispatch(registry, policy, "main", Window, message)
      .unwrap()
      .contains("\"code\":\"permission_denied\""),
    )
  }
  assert_true(
    dispatch(registry, policy, "main", RemotePage, matching)
    .unwrap()
    .contains("\"code\":\"permission_denied\""),
  )
}

///|
test "origin-free local callers retain their context" {
  let message = @runtime.RuntimePageMessage::new(body="fixture")
  guard invocation_context("main", Window, message) is Some(context) else {
    fail("expected a local window context")
  }
  assert_true(context.principal() is Window("main"))
  assert_true(context.origin() is None)
  assert_true(@ipc.InvocationContext::window("main").origin() is None)
  let malformed = @runtime.RuntimePageMessage::new(
    body="fixture",
    origin=Some(""),
  )
  assert_true(invocation_context("main", Window, malformed) is None)
}
