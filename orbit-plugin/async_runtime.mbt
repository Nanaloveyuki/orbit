///|
priv struct PendingPluginInvocation {
  condition : @cond_var.Cond
  mut result : Result[Bytes, PluginError]?
}

///|
fn PendingPluginInvocation::new() -> PendingPluginInvocation {
  { condition: @cond_var.Cond(), result: None }
}

///|
async fn PendingPluginInvocation::wait(
  self : PendingPluginInvocation,
) -> Result[Bytes, PluginError] {
  while self.result is None {
    self.condition.wait()
  }
  self.result.unwrap()
}

///|
priv struct PendingHostRequest {
  cancellation : @ipc.InvocationCancellation
  mut task : @async.Task[Unit]?
  mut completed : Bool
}

///|
priv struct PluginAsyncState {
  group : @async.TaskGroup[Unit]
  wakeup_callback : FuncRef[() -> Unit]
  registry : @ipc.CommandRegistry
  policy : @ipc.CommandPolicy
  host_requests : Map[String, PendingHostRequest]
  mut next_host_invocation_id : UInt64
}

///|
pub fn PluginRuntime::bind_async(
  self : PluginRuntime,
  group : @async.TaskGroup[Unit],
  wakeup_callback : FuncRef[() -> Unit],
  registry : @ipc.CommandRegistry,
  policy : @ipc.CommandPolicy,
) -> Unit {
  self.async_state = Some({
    group,
    wakeup_callback,
    registry,
    policy,
    host_requests: Map([]),
    next_host_invocation_id: 1UL,
  })
}

///|
fn PluginAsyncState::cancel_all_host_requests(self : PluginAsyncState) -> Unit {
  for _, pending in self.host_requests {
    pending.completed = true
    pending.cancellation.cancel()
    match pending.task {
      Some(task) => task.cancel()
      None => ()
    }
  }
  self.host_requests.clear()
}

///|
fn PluginLibrary::next_executor_invocation_id(self : PluginLibrary) -> UInt64 {
  let id = self.next_invocation_id
  self.next_invocation_id = self.next_invocation_id + 1
  if self.next_invocation_id == 0UL {
    self.next_invocation_id = 1UL
  }
  id
}

///|
async fn PluginLibrary::invoke_async(
  self : PluginLibrary,
  command : String,
  request : Bytes,
) -> Result[Bytes, PluginError] {
  if !self.manifest.commands.contains(command) {
    return Err(CommandDenied(command))
  }
  let executor = match self.executor {
    Some(executor) => executor
    None => return Err(AsyncRuntimeRequired)
  }
  while !self.executor_ready && !self.executor_stopped {
    self.executor_condition.wait()
  }
  if self.executor_stopped {
    return Err(ExecutorFailed)
  }
  let invocation_id = self.next_executor_invocation_id()
  let pending = PendingPluginInvocation::new()
  self.pending_invocations[invocation_id] = pending
  match executor.submit(invocation_id, command, request) {
    Err(_) => {
      self.pending_invocations.remove(invocation_id)
      return Err(ExecutorFailed)
    }
    Ok(_) => ()
  }
  pending.wait() catch {
    error => {
      self.pending_invocations.remove(invocation_id)
      ignore(executor.cancel(invocation_id))
      raise error
    }
  }
}

///|
fn PluginLibrary::complete_executor_invocation(
  self : PluginLibrary,
  invocation_id : UInt64,
  status : Int,
  response : Bytes,
) -> Unit {
  match self.pending_invocations.get(invocation_id) {
    None => ()
    Some(pending) => {
      self.pending_invocations.remove(invocation_id)
      pending.result = Some(
        if status == 0 {
          Ok(response)
        } else {
          Err(InvocationFailed)
        },
      )
      pending.condition.signal()
    }
  }
}

///|
fn PluginLibrary::complete_host_request(
  self : PluginLibrary,
  request_id : UInt64,
  response : String,
) -> Result[Unit, @abi.AbiError] {
  match self.executor {
    Some(executor) =>
      executor.complete_host_request(
        request_id,
        @utf8.encode(response, bom=false),
      )
    None => Err(@abi.ExecutorClosed)
  }
}

///|
fn PluginLibrary::cancel_host_request(
  self : PluginLibrary,
  request_id : UInt64,
  status : Int,
) -> Result[Unit, @abi.AbiError] {
  match self.executor {
    Some(executor) => executor.cancel_host_request(request_id, status)
    None => Err(@abi.ExecutorClosed)
  }
}

///|
fn PluginLibrary::settle_host_request(
  self : PluginLibrary,
  request_id : UInt64,
  response : String,
) -> Result[Unit, PluginError] {
  match self.complete_host_request(request_id, response) {
    Ok(_) => Ok(())
    Err(@abi.InvocationUnavailable) | Err(@abi.ExecutorClosed) => Ok(())
    Err(_) =>
      match self.cancel_host_request(request_id, -1) {
        Ok(_) => Ok(())
        Err(@abi.InvocationUnavailable) | Err(@abi.ExecutorClosed) => Ok(())
        Err(_) => Err(ExecutorFailed)
      }
  }
}

///|
fn host_request_key(plugin_id : String, request_id : UInt64) -> String {
  "\{plugin_id}\u{0}\{request_id}"
}

///|
fn PluginAsyncState::next_host_id(self : PluginAsyncState) -> @ipc.InvocationId {
  let value = self.next_host_invocation_id
  self.next_host_invocation_id = self.next_host_invocation_id + 1
  if self.next_host_invocation_id == 0UL {
    self.next_host_invocation_id = 1UL
  }
  @ipc.InvocationId::new("plugin-host-\{value}") catch {
    _ => abort("generated plugin host invocation id is invalid")
  }
}

///|
fn host_failure(
  id : @ipc.InvocationId,
  code : String,
  message : String,
) -> String {
  @ipc.encode_command_failure(
    Some(id),
    @ipc.CommandFailure::new(code~, message~),
  )
}

///|
fn prepare_host_source(
  request : @abi.HostRequest,
  id : @ipc.InvocationId,
) -> Result[String, String] {
  let command = @ipc.CommandName::new(request.command) catch {
    _ =>
      return Err(
        host_failure(id, "invalid_command", "plugin host command is invalid"),
      )
  }
  if command.value().has_prefix("plugin:") {
    return Err(
      host_failure(
        id, "reentrant_plugin_invocation", "plugin host requests cannot invoke plugin commands",
      ),
    )
  }
  let payload_text = @utf8.decode(request.request) catch {
    _ =>
      return Err(
        host_failure(id, "invalid_payload", "plugin host request is not UTF-8"),
      )
  }
  match @strict_json.parse(payload_text) {
    Err(_) =>
      return Err(
        host_failure(
          id, "invalid_payload", "plugin host request is not strict JSON",
        ),
      )
    Ok(_) => ()
  }
  let payload = @json.parse(payload_text) catch {
    _ =>
      return Err(
        host_failure(
          id, "invalid_payload", "plugin host request could not be decoded",
        ),
      )
  }
  let timeout_ms = if request.timeout_ms == 0U || request.timeout_ms > 300_000U {
    300_000
  } else {
    request.timeout_ms.reinterpret_as_int()
  }
  Ok(
    "{\"version\":1,\"type\":\"invoke\",\"id\":\{@json.to_json(id.value()).stringify()},\"command\":\{@json.to_json(command.value()).stringify()},\"payload\":\{payload.stringify()},\"timeout_ms\":\{timeout_ms}}",
  )
}

///|
fn PluginAsyncState::finish_host_request(
  self : PluginAsyncState,
  key : String,
  library : PluginLibrary,
  request_id : UInt64,
  response : String,
) -> Result[Unit, PluginError] {
  match self.host_requests.get(key) {
    None => Ok(())
    Some(pending) => {
      if pending.completed {
        return Ok(())
      }
      pending.completed = true
      self.host_requests.remove(key)
      library.host_request_active = false
      library.settle_host_request(request_id, response)
    }
  }
}

///|
fn PluginAsyncState::schedule_host_request(
  self : PluginAsyncState,
  library : PluginLibrary,
  request : @abi.HostRequest,
) -> Unit {
  library.host_request_active = true
  let invocation_id = self.next_host_id()
  let source = match prepare_host_source(request, invocation_id) {
    Ok(source) => source
    Err(response) => {
      library.host_request_active = false
      if library.settle_host_request(request.request_id, response) is Err(_) {
        library.executor_failed = true
      }
      return
    }
  }
  let context = @ipc.InvocationContext::plugin(library.manifest.id) catch {
    _ => {
      library.host_request_active = false
      if library.settle_host_request(
          request.request_id,
          host_failure(
            invocation_id, "invalid_principal", "plugin host principal is invalid",
          ),
        )
        is Err(_) {
        library.executor_failed = true
      }
      return
    }
  }
  let key = host_request_key(library.manifest.id, request.request_id)
  let pending = {
    cancellation: context.cancellation(),
    task: None,
    completed: false,
  }
  self.host_requests[key] = pending
  let task = self.group.spawn(no_wait=true, allow_failure=true) <| async fn() {
    let response = @ipc_async.dispatch_source_with_deadline(
      self.registry,
      self.policy,
      context,
      source,
    ) catch {
      _ => {
        if @async.is_being_cancelled() || context.cancellation().is_cancelled() {
          return
        }
        host_failure(
          invocation_id, "handler_failed", "plugin host command handler failed",
        )
      }
    }
    match self.finish_host_request(key, library, request.request_id, response) {
      Ok(_) => ()
      Err(_) => {
        library.executor_failed = true
        (self.wakeup_callback)()
      }
    }
  }
  pending.task = Some(task)
  if pending.completed {
    task.cancel()
  }
}

///|
fn PluginAsyncState::cancel_host_request(
  self : PluginAsyncState,
  plugin_id : String,
  request_id : UInt64,
) -> Unit {
  let key = host_request_key(plugin_id, request_id)
  match self.host_requests.get(key) {
    None => ()
    Some(pending) => {
      pending.completed = true
      pending.cancellation.cancel()
      self.host_requests.remove(key)
      match pending.task {
        Some(task) => task.cancel()
        None => ()
      }
    }
  }
}

///|
pub fn PluginRuntime::poll_events(
  self : PluginRuntime,
) -> Result[Unit, PluginRuntimeError] {
  let mut handled_event = false
  for library in self.libraries {
    if library.executor_failed {
      return Err(LoadFailure(library.manifest.id, ExecutorFailed))
    }
    let executor = match library.executor {
      Some(executor) => executor
      None => continue
    }
    while true {
      let event = match executor.poll_event() {
        Ok(Some(event)) => event
        Ok(None) => break
        Err(_) => return Err(LoadFailure(library.manifest.id, ExecutorFailed))
      }
      handled_event = true
      match event {
        @abi.ExecutorEvent::Ready(status) =>
          if status == 0 {
            library.executor_ready = true
            library.executor_condition.broadcast()
          } else {
            library.executor_stopped = true
            library.executor_condition.broadcast()
            return Err(LoadFailure(library.manifest.id, ActivationFailed))
          }
        @abi.ExecutorEvent::InvocationFinished(id, status, response) =>
          library.complete_executor_invocation(id, status, response)
        @abi.ExecutorEvent::HostRequest(request) =>
          match self.async_state {
            Some(state) => state.schedule_host_request(library, request)
            None => {
              library.host_request_active = false
              match library.cancel_host_request(request.request_id, -1) {
                Ok(_)
                | Err(@abi.InvocationUnavailable)
                | Err(@abi.ExecutorClosed) => ()
                Err(_) => library.executor_failed = true
              }
            }
          }
        @abi.ExecutorEvent::HostRequestCancelled(request_id, _, _) => {
          library.host_request_active = false
          match self.async_state {
            Some(state) =>
              state.cancel_host_request(library.manifest.id, request_id)
            None => ()
          }
        }
        @abi.ExecutorEvent::Stopped => {
          library.executor_ready = false
          library.executor_stopped = true
          library.executor_condition.broadcast()
        }
      }
    }
  }
  if handled_event {
    match self.async_state {
      Some(state) => (state.wakeup_callback)()
      None => ()
    }
  }
  Ok(())
}

///|
fn decode_plugin_json_response(
  plugin_id : String,
  response : Bytes,
) -> Result[Json, @ipc.CommandFailure] {
  let text = @utf8.decode(response) catch {
    _ =>
      return Err(
        @ipc.CommandFailure::new(
          code="plugin_invalid_response",
          message="plugin returned non-UTF-8 response: \{plugin_id}",
        ),
      )
  }
  match @strict_json.parse(text) {
    Err(_) =>
      return Err(
        @ipc.CommandFailure::new(
          code="plugin_invalid_response",
          message="plugin returned malformed JSON: \{plugin_id}",
        ),
      )
    Ok(_) => ()
  }
  let response = @json.parse(text) catch {
    _ =>
      return Err(
        @ipc.CommandFailure::new(
          code="plugin_invalid_response",
          message="plugin response could not be decoded: \{plugin_id}",
        ),
      )
  }
  Ok(response)
}

///|
async fn PluginRuntime::invoke_json_async(
  self : PluginRuntime,
  plugin_id : String,
  command : String,
  payload : Json,
) -> Result[Json, @ipc.CommandFailure] {
  for library in self.libraries {
    if library.manifest.id == plugin_id {
      if library.host_request_active {
        return Err(
          @ipc.CommandFailure::new(
            code="plugin_reentrant_invocation",
            message="plugin cannot be invoked while it is awaiting a host request: \{plugin_id}",
          ),
        )
      }
      let request = @utf8.encode(payload.stringify(), bom=false)
      return match library.invoke_async(command, request) {
        Ok(response) => decode_plugin_json_response(plugin_id, response)
        Err(_) =>
          Err(
            @ipc.CommandFailure::new(
              code="plugin_command_failed",
              message="plugin command failed: \{plugin_id}/\{command}",
            ),
          )
      }
    }
  }
  Err(
    @ipc.CommandFailure::new(
      code="plugin_unavailable",
      message="plugin is not active: \{plugin_id}",
    ),
  )
}
