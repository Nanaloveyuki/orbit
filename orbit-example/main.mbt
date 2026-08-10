///|
fn[T] fail(message : String) -> T {
  abort("orbit-example: \{message}")
}

///|
fn example_registry() -> @ipc.CommandRegistry raise @ipc.IpcError {
  let registry = @ipc.CommandRegistry::new()
  registry.register_json(@ipc.CommandName::new("example.ping"), _payload => {
    Ok({ "message": "IPC round trip completed." })
  })
  registry
}

///|
fn main {
  let ipc_registry = example_registry() catch {
    _ => fail("could not register example IPC commands")
  }
  let ipc_policy = configured_ipc_policy() catch {
    _ => fail("could not configure example IPC permissions")
  }
  let desktop_options = @core.DesktopOptions::new(
    windows=configured_windows(),
    ipc_registry=Some(ipc_registry),
    ipc_policy=Some(ipc_policy),
    plugin_declarations=configured_plugins(),
  ).with_builtin_file_capabilities() catch {
    _ => fail("could not create desktop options")
  }
  let factory = @moonview_runtime.MoonViewRuntimeFactory::new()
    as &@runtime.RuntimeFactory
  @core.run_async(factory, desktop_options, async fn() { @async.pause() }) catch {
    _ => fail("desktop application terminated with an error")
  }
}
