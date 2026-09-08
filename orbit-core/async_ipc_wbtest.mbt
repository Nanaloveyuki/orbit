///|
test "IPC rejects requests above scope and global in-flight limits" {
  let dispatcher = AsyncIpcDispatcher::new()
  let registry = @ipc.CommandRegistry::new()
  let policy = @ipc.CommandPolicy::new()
  let responses : Array[String] = []
  for i in 0..<256 {
    let scope = "scope-\{i / 64}"
    let id = @ipc.InvocationId::new("pending-\{i}")
    dispatcher.pending[invocation_key(scope, id)] = {
      scope,
      cancellation: @ipc.InvocationContext::window("main").cancellation(),
      task: None,
      completed: false,
    }
  }
  let request = @ipc.decode_request(
    "{\"version\":1,\"id\":\"new\",\"command\":\"echo\",\"payload\":null}",
  )
  let context = @ipc.InvocationContext::window("main")
  dispatcher.schedule("scope-4", registry, policy, context, request, value => {
    responses.push(value)
  })
  assert_true(responses[0].contains("ipc_busy"))
  dispatcher.cancel("scope-3", @ipc.InvocationId::new("pending-255"))
  dispatcher.schedule("scope-0", registry, policy, context, request, value => {
    responses.push(value)
  })
  assert_true(responses[1].contains("ipc_busy"))
  dispatcher.cancel("scope-0", @ipc.InvocationId::new("pending-0"))
  dispatcher.schedule("scope-0", registry, policy, context, request, value => {
    responses.push(value)
  })
  // Capacity was released; an unbound dispatcher now reports its lifecycle error.
  assert_true(responses[2].contains("async_unavailable"))
  dispatcher.cancel_all()
  assert_eq(dispatcher.pending.length(), 0)
}
