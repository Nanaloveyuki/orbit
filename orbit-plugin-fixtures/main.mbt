///|
fn fail(message : String) -> Unit {
  abort("orbit-plugin-fixtures: \{message}")
}

///|
fn declaration(
  path : String,
  permissions : Array[String],
) -> @plugin.PluginDeclaration {
  @plugin.PluginDeclaration::new(id="fixture.echo", library=path, permissions~)
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
  if args.length() != 2 {
    fail("usage: moon run orbit-plugin-fixtures <fixture-dll>")
  }
  let fixture = args[1]
  let runtime = @plugin.PluginRuntime::new()

  match runtime.start([declaration(fixture, [])]) {
    Err(LoadFailure("fixture.echo", PermissionDenied("test.invoke"))) => ()
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
  runtime.shutdown()
}
