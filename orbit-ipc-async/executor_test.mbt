///|
fn execution_policy(command : String) -> @ipc.CommandPolicy raise @ipc.IpcError {
  let policy = @ipc.CommandPolicy::new()
  policy.add_grant(
    @ipc.CommandGrant::new(
      identifier="executor-test",
      effect=@ipc.CapabilityEffect::allow(),
      principals=[@ipc.PrincipalSelector::background_task("test")],
      commands=[@ipc.CommandName::new(command)],
    ),
  )
  policy
}

///|
priv suberror ExecutorHandlerError

///|
async test "shared executor returns completed async responses" {
  let registry = @ipc.CommandRegistry::new()
  registry.register_async_json(@ipc.CommandName::new("async.echo"), async fn(
    payload,
  ) {
    @async.pause()
    Ok(payload)
  })
  let response = dispatch_source_with_deadline(
    registry,
    execution_policy("async.echo"),
    @ipc.InvocationContext::background_task("test"),
    "{\"version\":1,\"type\":\"invoke\",\"id\":\"complete\",\"command\":\"async.echo\",\"payload\":7,\"timeout_ms\":1000}",
  )
  assert_true(response.contains("\"result\":7"))
}

///|
async test "shared executor enforces deadlines and marks cancellation" {
  let registry = @ipc.CommandRegistry::new()
  registry.register_async_json(@ipc.CommandName::new("async.timeout"), async fn(
    payload,
  ) {
    @async.sleep(1000)
    Ok(payload)
  })
  let context = @ipc.InvocationContext::background_task("test")
  let response = dispatch_source_with_deadline(
    registry,
    execution_policy("async.timeout"),
    context,
    "{\"version\":1,\"type\":\"invoke\",\"id\":\"timeout\",\"command\":\"async.timeout\",\"payload\":null,\"timeout_ms\":10}",
  )
  assert_true(context.cancellation().is_cancelled())
  assert_true(response.contains("\"code\":\"timeout\""))
}

///|
async test "shared executor contains handler failures" {
  let registry = @ipc.CommandRegistry::new()
  registry.register_async_json(@ipc.CommandName::new("async.fail"), async fn(
    _,
  ) -> Result[Json, @ipc.CommandFailure] {
    @async.pause()
    raise ExecutorHandlerError
  })
  let response = dispatch_source_with_deadline(
    registry,
    execution_policy("async.fail"),
    @ipc.InvocationContext::background_task("test"),
    "{\"version\":1,\"type\":\"invoke\",\"id\":\"failure\",\"command\":\"async.fail\",\"payload\":null,\"timeout_ms\":1000}",
  )
  assert_true(response.contains("\"code\":\"handler_failed\""))
}

///|
async test "shared executor preserves protocol parse failures" {
  let registry = @ipc.CommandRegistry::new()
  let response = dispatch_source_with_deadline(
    registry,
    @ipc.CommandPolicy::new(),
    @ipc.InvocationContext::background_task("test"),
    "{\"version\":1,\"id\":\"bad\",\"command\":\"missing\"}",
  )
  assert_true(response.contains("\"code\":\"invalid_request\""))
}
