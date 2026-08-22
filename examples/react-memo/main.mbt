///|
fn[T] fail(message : String) -> T {
  abort("orbit-react-memo: \{message}")
}

///|
fn memo_registry() -> @ipc.CommandRegistry raise @ipc.IpcError {
  let registry = @ipc.CommandRegistry::new()
  registry.register_json(@ipc.CommandName::new("memo.runtime"), _payload => {
    Ok({
      "application": app_name,
      "version": app_version,
      "runtime": "Orbit",
      "storage": "WebView localStorage",
    })
  })
  registry
}

///|
fn main {
  let ipc_registry = memo_registry() catch {
    _ => fail("could not register memo IPC commands")
  }
  let ipc_policy = configured_ipc_policy() catch {
    _ => fail("could not configure memo IPC permissions")
  }
  let desktop_options = @core.DesktopOptions::new(
    windows=configured_windows(),
    ipc_registry=Some(ipc_registry),
    ipc_policy=Some(ipc_policy),
    plugin_declarations=configured_plugins(),
  ) catch {
    _ => fail("could not create desktop options")
  }
  let factory = @moonview_runtime.MoonViewRuntimeFactory::new()
    as &@runtime.RuntimeFactory
  ignore(
    @core.run(factory, desktop_options) catch {
      _ => fail("desktop application terminated with an error")
    },
  )
}
