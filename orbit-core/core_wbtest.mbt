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
    file_dialogs: false,
  }
}

///|
impl @runtime.WebViewRuntime for RecordingRuntime with fn show_file_dialog(
  _self,
  _options,
) {
  raise Unsupported("file dialogs are unavailable in RecordingRuntime")
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
test "file dialog command names are reserved by the UI runtime" {
  assert_true(is_dialog_command(@ipc.CommandName::new("orbit.dialog.open")))
  assert_true(
    is_dialog_command(@ipc.CommandName::new("orbit.dialog.pick_directory")),
  )
  assert_false(is_dialog_command(@ipc.CommandName::new("example.ping")))
}

///|
async test "file reads require a matching local read handle" {
  let path = "_build/orbit-core-file-read.txt"
  @fs.write_file(path, "hello", create_mode=CreateOrTruncate)
  let files = @file.FileCapabilityRegistry::new()
  let capability = files
    .mint("main", path, Read)
    .unwrap_or_else(() => abort("could not mint test file handle"))
  let request = { id: capability.id() }
  let context = @ipc.InvocationContext::window("main")
  match read_binary_capability(files, context, request) {
    Ok(response) => {
      assert_eq(response.data, "aGVsbG8=")
      assert_eq(response.size, 5)
    }
    Err(_) => abort("expected binary file read")
  }
  match read_text_capability(files, context, request) {
    Ok(response) => {
      assert_eq(response.text, "hello")
      assert_eq(response.size, 5)
    }
    Err(_) => abort("expected text file read")
  }
  match
    read_binary_capability(
      files,
      @ipc.InvocationContext::window("other"),
      request,
    ) {
    Err(failure) => assert_eq(failure.code, "file_handle_denied")
    Ok(_) => abort("expected cross-window denial")
  }
  files.revoke_window("main")
  match read_text_capability(files, context, request) {
    Err(failure) => assert_eq(failure.code, "file_handle_invalid")
    Ok(_) => abort("expected revoked-handle denial")
  }
  @fs.remove(path)
}

///|
async test "file reads reject write handles and invalid UTF-8" {
  let path = "_build/orbit-core-file-invalid-utf8.bin"
  @fs.write_file(path, b"\xFF", create_mode=CreateOrTruncate)
  let files = @file.FileCapabilityRegistry::new()
  let write = files
    .mint("main", path, Write)
    .unwrap_or_else(() => abort("could not mint test file handle"))
  let context = @ipc.InvocationContext::window("main")
  match read_binary_capability(files, context, { id: write.id() }) {
    Err(failure) => assert_eq(failure.code, "file_handle_invalid")
    Ok(_) => abort("expected write-handle denial")
  }
  let read = files
    .mint("main", path, Read)
    .unwrap_or_else(() => abort("could not mint test file handle"))
  match read_text_capability(files, context, { id: read.id() }) {
    Err(failure) => assert_eq(failure.code, "invalid_utf8")
    Ok(_) => abort("expected UTF-8 validation failure")
  }
  @fs.remove(path)
}

///|
async test "file reads reject oversized content and non-window callers" {
  let path = "_build/orbit-core-file-large.bin"
  @fs.write_file(
    path,
    Bytes::make(max_file_read_bytes + 1, 0),
    create_mode=CreateOrTruncate,
  )
  let files = @file.FileCapabilityRegistry::new()
  let capability = files
    .mint("main", path, Read)
    .unwrap_or_else(() => abort("could not mint test file handle"))
  let request = { id: capability.id() }
  match
    read_binary_capability(
      files,
      @ipc.InvocationContext::window("main"),
      request,
    ) {
    Err(failure) => assert_eq(failure.code, "file_too_large")
    Ok(_) => abort("expected read-size limit")
  }
  match
    read_binary_capability(
      files,
      @ipc.InvocationContext::background_task("worker"),
      request,
    ) {
    Err(failure) => assert_eq(failure.code, "file_unavailable")
    Ok(_) => abort("expected non-window denial")
  }
  @fs.remove(path)
  let missing = files
    .mint("main", "_build/orbit-core-file-missing.txt", Read)
    .unwrap_or_else(() => abort("could not mint missing-file handle"))
  match
    read_binary_capability(files, @ipc.InvocationContext::window("main"), {
      id: missing.id(),
    }) {
    Err(failure) => assert_eq(failure.code, "file_read_failed")
    Ok(_) => abort("expected native file-read failure")
  }
}

///|
async test "file writes atomically replace only matching write handles" {
  let path = "_build/orbit-core-file-write.txt"
  @fs.write_file(path, "old", create_mode=CreateOrTruncate)
  let files = @file.FileCapabilityRegistry::new()
  let write = files
    .mint("main", path, Write)
    .unwrap_or_else(() => abort("could not mint test write handle"))
  let context = @ipc.InvocationContext::window("main")
  match write_text_capability(files, context, { id: write.id(), text: "new" }) {
    Ok(response) => assert_eq(response.size, 3)
    Err(_) => abort("expected handle-bound write")
  }
  assert_eq(@fs.read_file(path).text(), "new")
  assert_false(@fs.can_read(temporary_write_path(path, write.id())))
  let read = files
    .mint("main", path, Read)
    .unwrap_or_else(() => abort("could not mint test read handle"))
  match
    write_text_capability(files, context, { id: read.id(), text: "denied" }) {
    Err(failure) => assert_eq(failure.code, "file_handle_invalid")
    Ok(_) => abort("expected read-handle denial")
  }
  files.revoke_window("main")
  match
    write_text_capability(files, context, { id: write.id(), text: "denied" }) {
    Err(failure) => assert_eq(failure.code, "file_handle_invalid")
    Ok(_) => abort("expected revoked-handle denial")
  }
  @fs.remove(path)
}

///|
async test "file writes reject oversized input and native failures" {
  let files = @file.FileCapabilityRegistry::new()
  let cancelled_path = "_build/orbit-core-cancelled-write.txt"
  @fs.write_file(cancelled_path, "original", create_mode=CreateOrTruncate)
  let cancelled_capability = files
    .mint("main", cancelled_path, Write)
    .unwrap_or_else(() => abort("could not mint cancelled write handle"))
  let cancelled_context = @ipc.InvocationContext::window("main")
  cancelled_context.cancellation().cancel()
  match
    write_text_capability(files, cancelled_context, {
      id: cancelled_capability.id(),
      text: "replacement",
    }) {
    Err(failure) => assert_eq(failure.code, "cancelled")
    Ok(_) => abort("expected cancelled write")
  }
  assert_eq(@fs.read_file(cancelled_path).text(), "original")
  assert_false(
    @fs.can_read(
      temporary_write_path(cancelled_path, cancelled_capability.id()),
    ),
  )
  @fs.remove(cancelled_path)
  let target = "_build/orbit-core-missing-parent/file.txt"
  let capability = files
    .mint("main", target, Write)
    .unwrap_or_else(() => abort("could not mint test write handle"))
  let context = @ipc.InvocationContext::window("main")
  match
    write_text_capability(files, context, { id: capability.id(), text: "x" }) {
    Err(failure) => assert_eq(failure.code, "file_write_failed")
    Ok(_) => abort("expected native file-write failure")
  }
  let fragments = []
  for _ in 0..<=max_file_read_bytes {
    fragments.push("x")
  }
  match
    write_text_capability(files, context, {
      id: capability.id(),
      text: fragments.join(""),
    }) {
    Err(failure) => assert_eq(failure.code, "file_too_large")
    Ok(_) => abort("expected write-size limit")
  }
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
