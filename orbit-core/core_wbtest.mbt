///|
priv struct RecordingRuntime {
  messages : Ref[Array[String]]
}

///|
impl @runtime.WebViewRuntime for RecordingRuntime with fn capabilities(_self) {
  {
    navigation: true,
    script_evaluation: true,
    message_transport: true,
    bounds_updates: true,
    devtools: false,
  }
}

///|
impl @runtime.WebViewRuntime for RecordingRuntime with fn navigate(_self, _url) {

}

///|
impl @runtime.WebViewRuntime for RecordingRuntime with fn evaluate_script(
  _self,
  _script,
  _request_id,
) {

}

///|
impl @runtime.WebViewRuntime for RecordingRuntime with fn post_message(
  self,
  message,
) {
  self.messages.val.push(message)
}

///|
impl @runtime.WebViewRuntime for RecordingRuntime with fn set_message_handler(
  _self,
  _handler,
) {

}

///|
impl @runtime.WebViewRuntime for RecordingRuntime with fn set_bounds(
  _self,
  _bounds,
) {

}

///|
impl @runtime.WebViewRuntime for RecordingRuntime with fn destroy(_self) {

}

///|
test "page events reach only local window subscriptions" {
  let router = @event.EventRouter::new()
  let messages = Ref([])
  let runtime = RecordingRuntime::{ messages, } as &@runtime.WebViewRuntime
  let local_subscription = subscribe_page_events(
    Some(router),
    "main",
    Window,
    runtime,
  )
  let remote_subscription = subscribe_page_events(
    Some(router),
    "remote",
    RemotePage,
    runtime,
  )
  assert_true(local_subscription is Some(_))
  assert_true(remote_subscription is None)
  let event = @event.EventEnvelope::new(
    name=@event.EventName::new("orbit://application/changed"),
    payload={ "revision": 4 },
    target=Window("main"),
  )
  assert_eq((router as &@event.EventSink).emit(event), Ok(()))
  assert_eq(messages.val.length(), 1)
  assert_true(messages.val[0].contains("\"type\":\"event\""))
  assert_true(messages.val[0].contains("\"revision\":4"))
  match local_subscription {
    Some(subscription) => router.unsubscribe_additional(subscription)
    None => abort("expected local page event subscription")
  }
  assert_eq((router as &@event.EventSink).emit(event), Ok(()))
  assert_eq(messages.val.length(), 1)
}

///|
fn async_ipc_policy(command : String) -> @ipc.CommandPolicy raise @ipc.IpcError {
  let policy = @ipc.CommandPolicy::new()
  policy.add_grant(
    @ipc.CommandGrant::new(
      identifier="async-test",
      effect=@ipc.CapabilityEffect::allow(),
      principals=[@ipc.PrincipalSelector::background_task("test")],
      commands=[@ipc.CommandName::new(command)],
    ),
  )
  policy
}

///|
priv suberror AsyncHandlerTestError

///|
async test "async IPC delivers a completed handler exactly once" {
  let dispatcher = AsyncIpcDispatcher::new()
  let registry = @ipc.CommandRegistry::new()
  registry.register_async_json(@ipc.CommandName::new("async.echo"), async fn(
    payload,
  ) {
    @async.pause()
    Ok(payload)
  })
  let context = @ipc.InvocationContext::background_task("test")
  let request = @ipc.decode_request(
    "{\"version\":1,\"type\":\"invoke\",\"id\":\"complete\",\"command\":\"async.echo\",\"payload\":7,\"timeout_ms\":1000}",
  )
  let responses : Ref[Array[String]] = Ref([])
  @async.with_task_group() <| group => {
    dispatcher.bind(group)
    dispatcher.schedule(
      "main",
      registry,
      async_ipc_policy("async.echo"),
      context,
      request,
      response => responses.val.push(response),
    )
    @async.sleep(20)
    assert_eq(responses.val.length(), 1)
    assert_true(responses.val[0].contains("\"result\":7"))
  }
}

///|
async test "async IPC rejects a duplicate pending invocation id" {
  let dispatcher = AsyncIpcDispatcher::new()
  let registry = @ipc.CommandRegistry::new()
  registry.register_async_json(@ipc.CommandName::new("async.slow"), async fn(
    payload,
  ) {
    @async.sleep(30)
    Ok(payload)
  })
  let request = @ipc.decode_request(
    "{\"version\":1,\"type\":\"invoke\",\"id\":\"duplicate\",\"command\":\"async.slow\",\"payload\":null,\"timeout_ms\":1000}",
  )
  let responses : Ref[Array[String]] = Ref([])
  @async.with_task_group() <| group => {
    dispatcher.bind(group)
    dispatcher.schedule(
      "main",
      registry,
      async_ipc_policy("async.slow"),
      @ipc.InvocationContext::background_task("test"),
      request,
      response => responses.val.push(response),
    )
    dispatcher.schedule(
      "main",
      registry,
      async_ipc_policy("async.slow"),
      @ipc.InvocationContext::background_task("test"),
      request,
      response => responses.val.push(response),
    )
    @async.sleep(60)
    assert_eq(responses.val.length(), 2)
    assert_true(
      responses.val.any(response => {
        response.contains("\"code\":\"duplicate_invocation\"")
      }),
    )
    assert_true(responses.val.any(response => response.contains("\"ok\":true")))
  }
}

///|
async test "async IPC cancellation suppresses late responses" {
  let dispatcher = AsyncIpcDispatcher::new()
  let registry = @ipc.CommandRegistry::new()
  registry.register_async_json(@ipc.CommandName::new("async.cancel"), async fn(
    payload,
  ) {
    @async.sleep(1000)
    Ok(payload)
  })
  let context = @ipc.InvocationContext::background_task("test")
  let request = @ipc.decode_request(
    "{\"version\":1,\"type\":\"invoke\",\"id\":\"cancel\",\"command\":\"async.cancel\",\"payload\":null,\"timeout_ms\":1000}",
  )
  let responses : Ref[Array[String]] = Ref([])
  @async.with_task_group() <| group => {
    dispatcher.bind(group)
    dispatcher.schedule(
      "main",
      registry,
      async_ipc_policy("async.cancel"),
      context,
      request,
      response => responses.val.push(response),
    )
    dispatcher.cancel("main", request.id())
    @async.sleep(20)
    assert_true(context.cancellation().is_cancelled())
    assert_eq(responses.val.length(), 0)
  }
}

///|
async test "async IPC host deadlines cancel work and return timeout" {
  let dispatcher = AsyncIpcDispatcher::new()
  let registry = @ipc.CommandRegistry::new()
  registry.register_async_json(@ipc.CommandName::new("async.timeout"), async fn(
    payload,
  ) {
    @async.sleep(1000)
    Ok(payload)
  })
  let context = @ipc.InvocationContext::background_task("test")
  let request = @ipc.decode_request(
    "{\"version\":1,\"type\":\"invoke\",\"id\":\"timeout\",\"command\":\"async.timeout\",\"payload\":null,\"timeout_ms\":10}",
  )
  let responses : Ref[Array[String]] = Ref([])
  @async.with_task_group() <| group => {
    dispatcher.bind(group)
    dispatcher.schedule(
      "main",
      registry,
      async_ipc_policy("async.timeout"),
      context,
      request,
      response => responses.val.push(response),
    )
    @async.sleep(50)
    assert_true(context.cancellation().is_cancelled())
    assert_eq(responses.val.length(), 1)
    assert_true(responses.val[0].contains("\"code\":\"timeout\""))
  }
}

///|
async test "async IPC contains handler failures" {
  let dispatcher = AsyncIpcDispatcher::new()
  let registry = @ipc.CommandRegistry::new()
  registry.register_async_json(@ipc.CommandName::new("async.fail"), async fn(
    _,
  ) -> Result[Json, @ipc.CommandFailure] {
    @async.pause()
    raise AsyncHandlerTestError
  })
  let request = @ipc.decode_request(
    "{\"version\":1,\"type\":\"invoke\",\"id\":\"failure\",\"command\":\"async.fail\",\"payload\":null,\"timeout_ms\":1000}",
  )
  let responses : Ref[Array[String]] = Ref([])
  @async.with_task_group() <| group => {
    dispatcher.bind(group)
    dispatcher.schedule(
      "main",
      registry,
      async_ipc_policy("async.fail"),
      @ipc.InvocationContext::background_task("test"),
      request,
      response => responses.val.push(response),
    )
    @async.sleep(20)
    assert_eq(responses.val.length(), 1)
    assert_true(responses.val[0].contains("\"code\":\"handler_failed\""))
  }
}
