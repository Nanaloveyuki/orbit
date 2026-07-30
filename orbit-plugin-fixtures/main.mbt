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
  runtime.shutdown()
}
