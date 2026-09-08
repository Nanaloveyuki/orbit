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
      window_label: "main",
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
  dispatcher.schedule(
    "scope-4",
    window_label="main",
    registry,
    policy,
    context,
    request,
    value => responses.push(value),
  )
  assert_true(responses[0].contains("ipc_busy"))
  dispatcher.cancel("scope-3", @ipc.InvocationId::new("pending-255"))
  dispatcher.schedule(
    "scope-0",
    window_label="main",
    registry,
    policy,
    context,
    request,
    value => responses.push(value),
  )
  assert_true(responses[1].contains("ipc_busy"))
  dispatcher.cancel("scope-0", @ipc.InvocationId::new("pending-0"))
  dispatcher.schedule(
    "scope-0",
    window_label="main",
    registry,
    policy,
    context,
    request,
    value => responses.push(value),
  )
  // Capacity was released; an unbound dispatcher now reports its lifecycle error.
  assert_true(responses[2].contains("async_unavailable"))
  dispatcher.cancel_all()
  assert_eq(dispatcher.pending.length(), 0)
}

///|
test "window cancellation covers all origins without cancelling other windows" {
  let dispatcher = AsyncIpcDispatcher::new()
  let id = @ipc.InvocationId::new("same-id")
  let responses : Array[String] = []
  let entries : Array[PendingInvocation] = []
  for scope in ["local", "remote-a", "remote-b", "other-window"] {
    let pending : PendingInvocation = {
      window_label: if scope == "other-window" {
        "other"
      } else {
        "main"
      },
      scope,
      cancellation: @ipc.InvocationContext::window("main").cancellation(),
      task: None,
      completed: false,
    }
    entries.push(pending)
    dispatcher.pending[invocation_key(scope, id)] = pending
  }
  dispatcher.cancel_window("main")
  dispatcher.cancel_window("main")
  assert_eq(dispatcher.pending.length(), 1)
  for i in 0..<3 {
    assert_true(entries[i].cancellation.is_cancelled())
    dispatcher.complete(
      invocation_key(entries[i].scope, id),
      entries[i],
      "late",
      response => responses.push(response),
    )
  }
  assert_eq(responses.length(), 0)
  assert_false(entries[3].cancellation.is_cancelled())
  let key = invocation_key("other-window", id)
  dispatcher.complete(key, entries[3], "done", response => {
    responses.push(response)
  })
  dispatcher.complete(key, entries[3], "duplicate", response => {
    responses.push(response)
  })
  assert_eq(responses, ["done"])
  assert_eq(dispatcher.pending.length(), 0)
}

///|
async test "window cancellation stops handler tasks and shutdown rejects new work" {
  let dispatcher = AsyncIpcDispatcher::new()
  let registry = @ipc.CommandRegistry::new()
  let started = Ref(false)
  let cleaned = Ref(false)
  registry.register_async_json(@ipc.CommandName::new("wait"), async fn(_) {
    started.val = true
    defer {
      cleaned.val = true
    }
    @async.sleep(60_000)
    Ok(Json::null())
  })
  let policy = @ipc.CommandPolicy::new()
  policy.add_grant(
    @ipc.CommandGrant::new(
      identifier="wait",
      effect=@ipc.CapabilityEffect::allow(),
      principals=[@ipc.PrincipalSelector::window("main")],
      commands=[@ipc.CommandName::new("wait")],
    ),
  )
  let request = @ipc.decode_request(
    "{\"version\":1,\"id\":\"wait\",\"command\":\"wait\",\"payload\":null}",
  )
  let responses : Array[String] = []
  @async.with_task_group() <| group => {
    dispatcher.bind(group)
    dispatcher.schedule(
      "local",
      window_label="main",
      registry,
      policy,
      @ipc.InvocationContext::window("main"),
      request,
      response => responses.push(response),
    )
    @async.with_timeout(5_000, () => {
      while !started.val {
        @async.pause()
      }
    })
    dispatcher.cancel_window("main")
    @async.with_timeout(5_000, () => {
      while !cleaned.val {
        @async.pause()
      }
    })
    dispatcher.cancel_all()
    dispatcher.schedule(
      "local",
      window_label="main",
      registry,
      policy,
      @ipc.InvocationContext::window("main"),
      request,
      response => responses.push(response),
    )
  }
  assert_true(cleaned.val)
  assert_eq(dispatcher.pending.length(), 0)
  assert_eq(responses.length(), 1)
  assert_true(responses[0].contains("async_unavailable"))
}

///|
test "cancelled completions cannot remove a reused invocation id" {
  let dispatcher = AsyncIpcDispatcher::new()
  let id = @ipc.InvocationId::new("reused")
  let key = invocation_key("scope", id)
  let old : PendingInvocation = {
    window_label: "main",
    scope: "scope",
    cancellation: @ipc.InvocationContext::window("main").cancellation(),
    task: None,
    completed: false,
  }
  dispatcher.pending[key] = old
  dispatcher.cancel("other-scope", id)
  assert_false(old.completed)
  dispatcher.cancel("scope", id)
  let current : PendingInvocation = {
    window_label: "main",
    scope: "scope",
    cancellation: @ipc.InvocationContext::window("main").cancellation(),
    task: None,
    completed: false,
  }
  dispatcher.pending[key] = current
  let responses : Array[String] = []
  dispatcher.complete(key, old, "stale", response => responses.push(response))
  assert_eq(dispatcher.pending.length(), 1)
  let request = @ipc.decode_request(
    "{\"version\":1,\"id\":\"reused\",\"command\":\"echo\",\"payload\":null}",
  )
  dispatcher.schedule(
    "scope",
    window_label="main",
    @ipc.CommandRegistry::new(),
    @ipc.CommandPolicy::new(),
    @ipc.InvocationContext::window("main"),
    request,
    response => responses.push(response),
  )
  assert_eq(responses.length(), 1)
  assert_true(responses[0].contains("duplicate_invocation"))
  assert_false(current.completed)
  dispatcher.complete(key, current, "current", response => {
    responses.push(response)
  })
  assert_eq(responses[1], "current")
  assert_eq(dispatcher.pending.length(), 0)
}
