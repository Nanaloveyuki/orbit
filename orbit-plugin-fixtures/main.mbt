///|
fn fail(message : String) -> Unit {
  abort("orbit-plugin-fixtures: \{message}")
}

///|
fn declaration(
  path : String,
  permissions : Array[String],
) -> @plugin.PluginDeclaration {
  let sidecar = match
    @plugin.parse_sidecar_manifest(
      "{\"schema_version\":2,\"abi_version\":1,\"id\":\"fixture.echo\",\"name\":\"Orbit fixture\",\"version\":\"1\",\"platforms\":[\"windows\"],\"requested_permissions\":[\"test.invoke\"],\"commands\":[{\"name\":\"echo\",\"request_schema\":{},\"response_schema\":{}},{\"name\":\"fail\",\"request_schema\":{},\"response_schema\":{}},{\"name\":\"malformed\",\"request_schema\":{},\"response_schema\":{}}]}",
    ) {
    Ok(sidecar) => sidecar
    Err(_) => abort("fixture sidecar is invalid")
  }
  @plugin.PluginDeclaration::new(
    id="fixture.echo",
    library=path,
    sidecar~,
    permissions~,
  )
}

///|
fn mismatched_declaration(path : String) -> @plugin.PluginDeclaration {
  let sidecar = match
    @plugin.parse_sidecar_manifest(
      "{\"schema_version\":2,\"abi_version\":1,\"id\":\"fixture.echo\",\"name\":\"Unexpected\",\"version\":\"1\",\"platforms\":[\"windows\"],\"requested_permissions\":[\"test.invoke\"],\"commands\":[{\"name\":\"echo\",\"request_schema\":{},\"response_schema\":{}},{\"name\":\"fail\",\"request_schema\":{},\"response_schema\":{}},{\"name\":\"malformed\",\"request_schema\":{},\"response_schema\":{}}]}",
    ) {
    Ok(sidecar) => sidecar
    Err(_) => abort("fixture sidecar is invalid")
  }
  @plugin.PluginDeclaration::new(id="fixture.echo", library=path, sidecar~, permissions=[
    "test.invoke",
  ])
}

///|
fn v2_declaration(path : String) -> @plugin.PluginDeclaration {
  let sidecar = match
    @plugin.parse_sidecar_manifest(
      "{\"schema_version\":2,\"abi_version\":2,\"id\":\"fixture.v2\",\"name\":\"Orbit v2 fixture\",\"version\":\"1\",\"platforms\":[\"windows\",\"linux\"],\"requested_permissions\":[\"test.invoke\"],\"commands\":[{\"name\":\"host_success\",\"request_schema\":{},\"response_schema\":{}},{\"name\":\"host_denied\",\"request_schema\":{},\"response_schema\":{}},{\"name\":\"host_cancel\",\"request_schema\":{},\"response_schema\":{}},{\"name\":\"host_reentrant\",\"request_schema\":{},\"response_schema\":{}}]}",
    ) {
    Ok(sidecar) => sidecar
    Err(_) => abort("v2 fixture sidecar is invalid")
  }
  @plugin.PluginDeclaration::new(id="fixture.v2", library=path, sidecar~, permissions=[
    "test.invoke",
  ])
}

///|
struct V2Driver {
  runtime : @plugin.PluginRuntime
  finished : Ref[Bool]
  failure : Ref[String?]
}

///|
pub impl @orby.App for V2Driver with fn about_to_wait(self, active) {
  match self.runtime.poll_events() {
    Ok(_) => ()
    Err(_) => {
      self.failure.val = Some("v2 executor event polling failed")
      self.finished.val = true
    }
  }
  if self.finished.val {
    active.exit()
  }
}

///|
pub impl @orby.App for V2Driver with fn exiting(self, _active) {
  ignore(self.runtime.shutdown())
}

///|
priv struct V2ExternalLoop {
  app_loop : @orby.ExternalAppLoop[V2Driver]
}

///|
using @external_loop {trait ExternalEventLoop}

///|
impl ExternalEventLoop for V2ExternalLoop with fn poll(self, timeout?) {
  self.app_loop.poll(timeout?)
}

///|
impl ExternalEventLoop for V2ExternalLoop with fn get_wakeup_callback_for_foreign_thread(
  self,
) {
  self.app_loop.wakeup_callback_for_foreign_thread()
}

///|
impl ExternalEventLoop for V2ExternalLoop with fn terminate(self) {
  ignore(self.app_loop.terminate())
}

///|
fn run_v2_fixture(path : String) -> Unit {
  let runtime = @plugin.PluginRuntime::new()
  let registry = @ipc.CommandRegistry::new()
  let policy = @ipc.CommandPolicy::new()
  try {
    registry.register_json(@ipc.CommandName::new("app:echo"), payload => {
      Ok(payload)
    })
    registry.register_async_json(@ipc.CommandName::new("app:wait"), async fn(
      payload,
    ) {
      @async.sleep(5000)
      Ok(payload)
    })
    registry.register_async_json(@ipc.CommandName::new("app:alias"), async fn(
      _,
    ) {
      let response = @ipc_async.dispatch_source_with_deadline(
        registry,
        policy,
        @ipc.InvocationContext::background_task("fixture"),
        "{\"version\":1,\"id\":\"indirect-reentry\",\"command\":\"plugin:fixture.v2/host_success\",\"payload\":null,\"timeout_ms\":1000}",
      )
      if response.contains("\"code\":\"plugin_reentrant_invocation\"") {
        Err(
          @ipc.CommandFailure::new(
            code="alias_reentry_blocked",
            message="indirect plugin reentry was blocked",
          ),
        )
      } else {
        Err(
          @ipc.CommandFailure::new(
            code="alias_reentry_failed",
            message="indirect plugin reentry was not blocked",
          ),
        )
      }
    })
    policy.add_grant(
      @ipc.CommandGrant::new(
        identifier="fixture-plugin-host",
        effect=@ipc.CapabilityEffect::allow(),
        principals=[@ipc.PrincipalSelector::plugin("fixture.v2")],
        commands=[
          @ipc.CommandName::new("app:echo"),
          @ipc.CommandName::new("app:wait"),
          @ipc.CommandName::new("app:alias"),
        ],
      ),
    )
    policy.add_grant(
      @ipc.CommandGrant::new(
        identifier="fixture-caller",
        effect=@ipc.CapabilityEffect::allow(),
        principals=[@ipc.PrincipalSelector::background_task("fixture")],
        commands=[
          @plugin.plugin_command_name("fixture.v2", "host_success"),
          @plugin.plugin_command_name("fixture.v2", "host_denied"),
          @plugin.plugin_command_name("fixture.v2", "host_cancel"),
          @plugin.plugin_command_name("fixture.v2", "host_reentrant"),
        ],
      ),
    )
  } catch {
    _ => fail("could not configure v2 fixture IPC")
  }
  let finished = Ref(false)
  let failure : Ref[String?] = Ref(None)
  let event_loop = @orby.EventLoop::new() catch {
    _ => abort("could not create v2 fixture event loop")
  }
  let app_loop = event_loop.start_external_app({ runtime, finished, failure }) catch {
    _ => abort("could not start v2 fixture event loop")
  }
  let wakeup_callback = app_loop.wakeup_callback_for_foreign_thread()
  let external_loop : V2ExternalLoop = { app_loop, }
  @async.set_external_event_loop(external_loop)
  @async.run_async_main(() => {
    @async.with_task_group() <| group => {
      runtime.bind_async(group, wakeup_callback, registry, policy)
      match runtime.start([v2_declaration(path)]) {
        Err(_) => failure.val = Some("v2 fixture plugin did not activate")
        Ok(_) =>
          match runtime.register_ipc(registry) {
            Err(_) => failure.val = Some("v2 fixture IPC registration failed")
            Ok(_) => {
              let context = @ipc.InvocationContext::background_task("fixture")
              let success = @ipc_async.dispatch_source_with_deadline(
                registry, policy, context, "{\"version\":1,\"id\":\"v2-success\",\"command\":\"plugin:fixture.v2/host_success\",\"payload\":{\"value\":9}}",
              )
              if !success.contains("\"ok\":true") ||
                !success.contains("\"id\":\"v2-success\"") ||
                !success.contains("\"id\":\"plugin-host-1\"") ||
                !success.contains("\"value\":9") {
                failure.val = Some(
                  "v2 host request did not return its response",
                )
              }
              let denied = @ipc_async.dispatch_source_with_deadline(
                registry,
                policy,
                @ipc.InvocationContext::background_task("fixture"),
                "{\"version\":1,\"id\":\"v2-denied\",\"command\":\"plugin:fixture.v2/host_denied\",\"payload\":null}",
              )
              if !denied.contains("\"id\":\"v2-denied\"") ||
                !denied.contains("\"ok\":true") ||
                !denied.contains("\"id\":\"plugin-host-2\"") ||
                !denied.contains("\"ok\":false") ||
                !denied.contains("\"code\":\"permission_denied\"") {
                failure.val = Some(
                  "v2 denied host request was not rejected: \{denied}",
                )
              }
              let cancelled = @ipc_async.dispatch_source_with_deadline(
                registry,
                policy,
                @ipc.InvocationContext::background_task("fixture"),
                "{\"version\":1,\"id\":\"v2-cancel\",\"command\":\"plugin:fixture.v2/host_cancel\",\"payload\":null,\"timeout_ms\":50}",
              )
              if !cancelled.contains("\"code\":\"timeout\"") {
                failure.val = Some(
                  "v2 host request cancellation did not reach its deadline: \{cancelled}",
                )
              }
              let reentrant = @ipc_async.dispatch_source_with_deadline(
                registry,
                policy,
                @ipc.InvocationContext::background_task("fixture"),
                "{\"version\":1,\"id\":\"v2-reentrant\",\"command\":\"plugin:fixture.v2/host_reentrant\",\"payload\":null,\"timeout_ms\":1000}",
              )
              if !reentrant.contains("\"code\":\"alias_reentry_blocked\"") {
                failure.val = Some(
                  "v2 indirect reentry was not rejected: \{reentrant}",
                )
              }
            }
          }
      }
      finished.val = true
      wakeup_callback()
    }
  })
  match failure.val {
    Some(message) => fail(message)
    None => ()
  }
}

///|
struct CoreFixtureRuntime {
  lifecycle : Ref[((@runtime.RuntimeLifecycleEvent) -> Unit)?]
}

///|
impl @runtime.WebViewRuntime for CoreFixtureRuntime with fn capabilities(_self) {
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
impl @runtime.WebViewRuntime for CoreFixtureRuntime with fn show_file_dialog(
  _self,
  _options,
) {
  raise Unsupported("file dialogs are unavailable in CoreFixtureRuntime")
}

///|
impl @runtime.WebViewRuntime for CoreFixtureRuntime with fn navigate(
  _self,
  _url,
) {

}

///|
impl @runtime.WebViewRuntime for CoreFixtureRuntime with fn evaluate_script(
  _self,
  _script,
  _request_id,
) {

}

///|
impl @runtime.WebViewRuntime for CoreFixtureRuntime with fn post_message(
  _self,
  _message,
) {

}

///|
impl @runtime.WebViewRuntime for CoreFixtureRuntime with fn set_message_handler(
  _self,
  _handler,
) {

}

///|
impl @runtime.WebViewRuntime for CoreFixtureRuntime with fn set_bounds(
  _self,
  _bounds,
) {

}

///|
impl @runtime.WebViewRuntime for CoreFixtureRuntime with fn destroy(_self) {

}

///|
struct CoreFixtureFactory {
  runtime : CoreFixtureRuntime
}

///|
impl @runtime.RuntimeFactory for CoreFixtureFactory with fn create(
  self,
  _host,
  options,
) {
  self.runtime.lifecycle.val = Some(options.lifecycle_handler())
  self.runtime as &@runtime.WebViewRuntime
}

///|
fn run_core_v2_fixture(path : String) -> Unit {
  let registry = @ipc.CommandRegistry::new()
  let policy = @ipc.CommandPolicy::new()
  try {
    registry.register_json(@ipc.CommandName::new("app:echo"), payload => {
      Ok(payload)
    })
    policy.add_grant(
      @ipc.CommandGrant::new(
        identifier="core-fixture-plugin-host",
        effect=@ipc.CapabilityEffect::allow(),
        principals=[@ipc.PrincipalSelector::plugin("fixture.v2")],
        commands=[@ipc.CommandName::new("app:echo")],
      ),
    )
    policy.add_grant(
      @ipc.CommandGrant::new(
        identifier="core-fixture-caller",
        effect=@ipc.CapabilityEffect::allow(),
        principals=[@ipc.PrincipalSelector::background_task("core-fixture")],
        commands=[@plugin.plugin_command_name("fixture.v2", "host_success")],
      ),
    )
  } catch {
    _ => fail("could not configure core v2 fixture IPC")
  }
  let lifecycle : Ref[((@runtime.RuntimeLifecycleEvent) -> Unit)?] = Ref(None)
  let factory = { runtime: { lifecycle, } }
  let runtime_options = @runtime.RuntimeOptions::new(
    label="main",
    bounds=@runtime.RuntimeBounds::new(width=320, height=240),
    initial_content=@runtime.InitialContent::Html("<main></main>"),
    visible=false,
  ) catch {
    _ => abort("could not configure core fixture runtime")
  }
  let options = @core.DesktopOptions::new(
    windows=[
      @core.DesktopWindowOptions::new("Orbit core v2 fixture", runtime_options),
    ],
    ipc_registry=Some(registry),
    ipc_policy=Some(policy),
    plugin_declarations=[v2_declaration(path)],
  ) catch {
    _ => abort("could not configure core fixture application")
  }
  let response_ok = Ref(false)
  let exited = try {
    @core.run_async(factory as &@runtime.RuntimeFactory, options, async fn() {
      let response = @ipc_async.dispatch_source_with_deadline(
        registry,
        policy,
        @ipc.InvocationContext::background_task("core-fixture"),
        "{\"version\":1,\"id\":\"core-v2\",\"command\":\"plugin:fixture.v2/host_success\",\"payload\":{\"value\":11},\"timeout_ms\":1000}",
      )
      response_ok.val = response.contains("\"ok\":true") &&
        response.contains("\"value\":11")
      match lifecycle.val {
        Some(handler) =>
          handler(
            @runtime.RuntimeLifecycleEvent::Failed(
              @runtime.RuntimeError::OperationFailed("fixture", "complete"),
            ),
          )
        None => ()
      }
    })
    false
  } catch {
    @core.RuntimeFailed(message) => message == "fixture: complete"
    _ => false
  }
  if !response_ok.val || !exited {
    fail("orbit-core.run_async did not execute and tear down the v2 plugin")
  }
}

///|
fn assert_failure(response : String, code : String) -> Unit {
  if !response.contains("\"code\":\"\{code}\"") {
    fail("expected IPC failure code \{code}, got \{response}")
  }
}

///|
fn main {
  let args = @env.args()
  if args.length() != 2 && args.length() != 3 {
    fail("usage: moon run orbit-plugin-fixtures <fixture-dll> [create-failure]")
  }
  let fixture = args[1]
  if args.length() == 3 && args[2] == "v2" {
    run_v2_fixture(fixture)
    return
  }
  if args.length() == 3 && args[2] == "core-v2" {
    run_core_v2_fixture(fixture)
    return
  }
  let runtime = @plugin.PluginRuntime::new()

  if args.length() == 3 {
    match runtime.start([declaration(fixture, ["test.invoke"])]) {
      Err(LoadFailure("fixture.echo", ActivationFailed)) => ()
      _ => fail("plugin create failure was not reported as activation failure")
    }
    return
  }

  match runtime.start([mismatched_declaration(fixture)]) {
    Err(SidecarMismatch("fixture.echo")) => ()
    _ => fail("mismatched sidecar was accepted")
  }

  match runtime.start([declaration(fixture, [])]) {
    Err(MissingPermission("fixture.echo", "test.invoke")) => ()
    _ => fail("missing permission did not deny plugin activation")
  }
  match
    runtime.start([
      declaration(fixture, ["test.invoke"]),
      declaration(fixture, ["test.invoke"]),
    ]) {
    Err(DuplicatePlugin("fixture.echo")) => ()
    _ => fail("duplicate plugin identifier was accepted")
  }
  match runtime.start([declaration(fixture, ["test.invoke"])]) {
    Ok(_) => ()
    Err(_) => fail("fixture plugin did not activate")
  }
  let registry = @ipc.CommandRegistry::new()
  match runtime.register_ipc(registry) {
    Ok(_) => ()
    Err(_) => fail("fixture plugin commands were not registered")
  }
  let success = registry.dispatch(
    "{\"version\":1,\"id\":\"fixture-success\",\"command\":\"plugin:fixture.echo/echo\",\"payload\":{\"value\":7}}",
  )
  if !success.contains("\"ok\":true") || !success.contains("\"value\":7") {
    fail("fixture plugin did not return its JSON response")
  }
  let failure = registry.dispatch(
    "{\"version\":1,\"id\":\"fixture-failure\",\"command\":\"plugin:fixture.echo/fail\",\"payload\":null}",
  )
  assert_failure(failure, "plugin_command_failed")
  let malformed = registry.dispatch(
    "{\"version\":1,\"id\":\"fixture-malformed\",\"command\":\"plugin:fixture.echo/malformed\",\"payload\":null}",
  )
  assert_failure(malformed, "plugin_invalid_response")
  ignore(runtime.shutdown())
}
