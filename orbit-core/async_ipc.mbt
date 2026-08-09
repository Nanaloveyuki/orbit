///|
priv struct PendingInvocation {
  cancellation : @ipc.InvocationCancellation
  mut task : @async.Task[Unit]?
  mut completed : Bool
}

///|
priv struct AsyncIpcDispatcher {
  mut group : @async.TaskGroup[Unit]?
  pending : Map[String, PendingInvocation]
}

///|
fn AsyncIpcDispatcher::new() -> AsyncIpcDispatcher {
  { group: None, pending: Map([]) }
}

///|
fn AsyncIpcDispatcher::bind(
  self : AsyncIpcDispatcher,
  group : @async.TaskGroup[Unit],
) -> Unit {
  self.group = Some(group)
}

///|
fn invocation_key(scope : String, id : @ipc.InvocationId) -> String {
  "\{scope}\u{0}\{id.value()}"
}

///|
fn invocation_failure(
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
async fn run_before_deadline(
  request : @ipc.InvocationRequest,
  context : @ipc.InvocationContext,
  operation : async () -> String,
) -> String? {
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => {
      @async.sleep(request.timeout_ms())
      context.cancellation().cancel()
      group.return_immediately(None)
    }
    Some(operation())
  }
}

///|
fn AsyncIpcDispatcher::complete(
  self : AsyncIpcDispatcher,
  key : String,
  pending : PendingInvocation,
  response : String,
  deliver : (String) -> Unit,
) -> Unit {
  if pending.completed {
    return
  }
  pending.completed = true
  self.pending.remove(key)
  deliver(response)
}

///|
fn AsyncIpcDispatcher::cancel(
  self : AsyncIpcDispatcher,
  scope : String,
  id : @ipc.InvocationId,
) -> Unit {
  let key = invocation_key(scope, id)
  match self.pending.get(key) {
    None => ()
    Some(pending) => {
      pending.completed = true
      pending.cancellation.cancel()
      self.pending.remove(key)
      match pending.task {
        Some(task) => task.cancel()
        None => ()
      }
    }
  }
}

///|
fn AsyncIpcDispatcher::cancel_all(self : AsyncIpcDispatcher) -> Unit {
  for _, pending in self.pending {
    pending.completed = true
    pending.cancellation.cancel()
    match pending.task {
      Some(task) => task.cancel()
      None => ()
    }
  }
  self.pending.clear()
}

///|
fn AsyncIpcDispatcher::schedule(
  self : AsyncIpcDispatcher,
  scope : String,
  registry : @ipc.CommandRegistry,
  policy : @ipc.CommandPolicy,
  context : @ipc.InvocationContext,
  request : @ipc.InvocationRequest,
  deliver : (String) -> Unit,
) -> Unit {
  let id = request.id()
  let key = invocation_key(scope, id)
  if self.pending.contains(key) {
    deliver(
      invocation_failure(
        id, "duplicate_invocation", "invocation id is already pending",
      ),
    )
    return
  }
  let group = match self.group {
    Some(group) => group
    None => {
      deliver(
        invocation_failure(
          id, "async_unavailable", "async IPC runtime is not ready",
        ),
      )
      return
    }
  }
  let pending = {
    cancellation: context.cancellation(),
    task: None,
    completed: false,
  }
  self.pending[key] = pending
  let task = group.spawn(no_wait=true, allow_failure=true) <| async fn() {
    let result = run_before_deadline(request, context, () => {
      registry.dispatch_invocation_async(request, policy, context)
    }) catch {
      error => {
        if @async.is_cancellation_error(error) {
          return
        }
        Some(
          invocation_failure(
            id, "handler_failed", "async command handler failed",
          ),
        )
      }
    }
    match result {
      Some(response) => self.complete(key, pending, response, deliver)
      None =>
        self.complete(
          key,
          pending,
          invocation_failure(
            id, "timeout", "IPC command exceeded its host deadline",
          ),
          deliver,
        )
    }
  }
  pending.task = Some(task)
  if pending.completed {
    task.cancel()
  }
}
