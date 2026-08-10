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
  let request : FileReadRequest = { id: capability.id() }
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
  let request : FileReadRequest = { id: capability.id() }
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
async test "directory reads require a matching local directory handle" {
  let root = "_build/orbit-core-directory-native-handle-v2"
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  @fs.mkdir(root, recursive=true)
  @fs.write_file("\{root}/note.txt", "note", create_mode=CreateOrTruncate)
  @fs.mkdir("\{root}/nested", recursive=true)
  @fs.mkdir("\{root}/nested/grandchild", recursive=true)
  let files = @file.FileCapabilityRegistry::new()
  let capability = files
    .mint_directory("main", root)
    .unwrap_or_else(() => abort("could not mint test directory handle"))
  let context = @ipc.InvocationContext::window("main")
  let response = match
    read_directory_capability(files, context, { id: capability.id() }) {
    Ok(response) => response
    Err(_) => abort("expected handle-bound directory read")
  }
  assert_eq(response.entries.length(), 2)
  let mut note_id = None
  let mut nested_id = None
  for entry in response.entries {
    if entry.name == "note.txt" {
      note_id = entry.id
    }
    if entry.name == "nested" {
      nested_id = entry.id
    }
  }
  let nested = match nested_id {
    Some(id) => id
    None => abort("expected nested directory capability in response")
  }
  let note = match note_id {
    Some(id) => id
    None => abort("expected native read capability for regular file")
  }
  match read_text_capability(files, context, { id: note }) {
    Ok(response) => assert_eq(response.text, "note")
    Err(_) => abort("expected directory-derived file read")
  }
  match read_text_capability(files, context, { id: note }) {
    Ok(response) => assert_eq(response.text, "note")
    Err(_) => abort("expected repeat directory-derived file read")
  }
  let repeated = match
    read_directory_capability(files, context, { id: capability.id() }) {
    Ok(response) => response
    Err(_) => abort("expected repeated directory read")
  }
  let mut repeated_nested_id = None
  let mut repeated_note_id = None
  for entry in repeated.entries {
    if entry.name == "note.txt" {
      repeated_note_id = entry.id
    }
    if entry.name == "nested" {
      repeated_nested_id = entry.id
    }
  }
  match repeated_nested_id {
    Some(id) => assert_eq(id, nested)
    None => abort("expected cached nested directory capability")
  }
  match repeated_note_id {
    Some(id) => assert_eq(id, note)
    None => abort("expected cached native read capability")
  }
  assert_eq(files.length(), 3)
  let nested_response = match
    read_directory_capability(files, context, { id: nested }) {
    Ok(response) => response
    Err(_) => abort("expected child directory read")
  }
  assert_eq(nested_response.entries.length(), 1)
  assert_eq(nested_response.entries[0].name, "grandchild")
  match files.mint_child_directory("main", capability.id(), "..") {
    Err(@file.FileCapabilityError::DirectoryUnavailable) => ()
    _ => abort("expected parent traversal to be rejected")
  }
  assert_true(
    response.entries.any(entry => {
      entry.name == "nested" && entry.kind == "directory" && entry.id is Some(_)
    }),
  )
  match
    read_directory_capability(files, @ipc.InvocationContext::window("other"), {
      id: capability.id(),
    }) {
    Err(failure) => assert_eq(failure.code, "file_handle_denied")
    Ok(_) => abort("expected cross-window denial")
  }
  let file = files
    .mint("main", "\{root}/note.txt", Read)
    .unwrap_or_else(() => abort("could not mint test file handle"))
  match read_directory_capability(files, context, { id: file.id() }) {
    Err(failure) => assert_eq(failure.code, "file_handle_invalid")
    Ok(_) => abort("expected file-handle denial")
  }
  files.revoke_window("main")
  match read_directory_capability(files, context, { id: capability.id() }) {
    Err(failure) => assert_eq(failure.code, "file_handle_invalid")
    Ok(_) => abort("expected revoked-handle denial")
  }
  files.clear()
  @fs.rmdir(root, recursive=true)
}

///|
async test "directory handles do not follow links or Windows reparse points" {
  let root = "_build/orbit-core-directory-no-follow-root-v2"
  let target = "_build/orbit-core-directory-no-follow-target-v2"
  let escape = "\{root}/escape"
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  @fs.rmdir(target, recursive=true) catch {
    _ => ()
  }
  @fs.mkdir(root, recursive=true)
  @fs.mkdir(target, recursive=true)
  @fs.write_file(
    "\{target}/outside.txt",
    "outside",
    create_mode=CreateOrTruncate,
  )
  let target_path = @fs.realpath(target)
  @fs.symlink(target=target_path, escape)
  let files = @file.FileCapabilityRegistry::new()
  let capability = files
    .mint_directory("main", root)
    .unwrap_or_else(() => abort("could not mint root directory handle"))
  let response = match
    read_directory_capability(files, @ipc.InvocationContext::window("main"), {
      id: capability.id(),
    }) {
    Ok(response) => response
    Err(_) => abort("expected no-follow directory list")
  }
  assert_false(response.entries.any(entry => entry.name == "escape"))
  match files.mint_child_directory("main", capability.id(), "escape") {
    Err(@file.FileCapabilityError::DirectoryUnavailable) => ()
    _ => abort("expected link child to be rejected")
  }
  match files.mint_directory("main", escape) {
    Err(@file.FileCapabilityError::DirectoryUnavailable) => ()
    _ => abort("expected link root to be rejected")
  }
  files.clear()
  @fs.remove(escape)
  @fs.rmdir(root, recursive=true)
  @fs.rmdir(target, recursive=true)
}

///|
async test "directory reads reject cancellation overflow and native failures" {
  let files = @file.FileCapabilityRegistry::new()
  let root = "_build/orbit-core-directory-native-cancelled"
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  @fs.mkdir(root, recursive=true)
  let cancelled = files
    .mint_directory("main", root)
    .unwrap_or_else(() => abort("could not mint cancelled directory handle"))
  let context = @ipc.InvocationContext::window("main")
  context.cancellation().cancel()
  match read_directory_capability(files, context, { id: cancelled.id() }) {
    Err(failure) => assert_eq(failure.code, "cancelled")
    Ok(_) => abort("expected cancelled directory read")
  }
  files.revoke_window("main")
  @fs.rmdir(root, recursive=true)
  let oversized_root = "_build/orbit-core-directory-native-oversized-v2"
  @fs.rmdir(oversized_root, recursive=true) catch {
    _ => ()
  }
  @fs.mkdir(oversized_root, recursive=true)
  for index in 0..<=max_directory_entries {
    @fs.write_file(
      "\{oversized_root}/entry-\{index}.txt",
      "x",
      create_mode=CreateOrTruncate,
    )
  }
  let oversized = files
    .mint_directory("main", oversized_root)
    .unwrap_or_else(() => abort("could not mint oversized directory handle"))
  match
    read_directory_capability(files, @ipc.InvocationContext::window("main"), {
      id: oversized.id(),
    }) {
    Err(failure) => assert_eq(failure.code, "directory_too_large")
    Ok(_) => abort("expected directory entry limit")
  }
  files.clear()
  @fs.rmdir(oversized_root, recursive=true)
  match
    files.mint_directory("main", "_build/orbit-core-missing-native-directory") {
    Err(@file.FileCapabilityError::DirectoryUnavailable) => ()
    _ => abort("expected missing directory to fail during handle creation")
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
