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
  let runtime_options = @runtime.RuntimeOptions::new(
    label=window_label,
    bounds=@runtime.RuntimeBounds::new(width=window_width, height=window_height),
    initial_content=Url(entry_url),
    initialization_script="document.documentElement.dataset.orbit = 'ready'",
    visible=window_visible,
    resource_provider=Some(
      @runtime.RuntimeResourceProvider::new(
        scheme=resource_scheme,
        handler=handle_resource,
      ),
    ),
  ) catch {
    _ => fail("could not create runtime options")
  }
  let desktop_options = @core.DesktopOptions::new(
    window_title,
    runtime_options,
    resizable=window_resizable,
    ipc_registry=Some(ipc_registry),
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
