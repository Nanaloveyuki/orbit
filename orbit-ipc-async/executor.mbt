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
/// Dispatches one authorized invocation under its declared host deadline.
///
/// This is the shared execution boundary for asynchronous transports. Handler
/// failures and deadline expiry become protocol responses. Cancellation of the
/// calling task is propagated after marking the transport cancellation token.
pub async fn dispatch_with_deadline(
  registry : @ipc.CommandRegistry,
  policy : @ipc.CommandPolicy,
  context : @ipc.InvocationContext,
  request : @ipc.InvocationRequest,
) -> String {
  let id = request.id()
  let result = run_before_deadline(request, context, () => {
    registry.dispatch_invocation_async(request, policy, context)
  }) catch {
    error => {
      if @async.is_being_cancelled() {
        context.cancellation().cancel()
        raise error
      }
      return invocation_failure(
        id, "handler_failed", "async command handler failed",
      )
    }
  }
  match result {
    Some(response) => response
    None =>
      invocation_failure(
        id, "timeout", "IPC command exceeded its host deadline",
      )
  }
}

///|
/// Parses and dispatches one wire request under the same deadline contract.
/// Parse failures are encoded by the transport-neutral registry and do not
/// start handler work.
pub async fn dispatch_source_with_deadline(
  registry : @ipc.CommandRegistry,
  policy : @ipc.CommandPolicy,
  context : @ipc.InvocationContext,
  source : StringView,
) -> String {
  let request = @ipc.decode_request(source) catch {
    _ => return registry.dispatch_with_context_async(source, policy, context)
  }
  dispatch_with_deadline(registry, policy, context, request)
}
