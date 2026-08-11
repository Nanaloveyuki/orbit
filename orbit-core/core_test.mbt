///|
test "desktop options require a title" {
  let options = @runtime.RuntimeOptions::new(
    label="main",
    bounds=@runtime.RuntimeBounds::new(width=800, height=600),
    initial_content=Html("<main></main>"),
  )
  let rejected = try {
    ignore(DesktopWindowOptions::new("", options))
    false
  } catch {
    InitializationFailed(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "desktop options require an IPC policy with an IPC registry" {
  let options = @runtime.RuntimeOptions::new(
    label="main",
    bounds=@runtime.RuntimeBounds::new(width=800, height=600),
    initial_content=Html("<main></main>"),
  )
  let rejected = try {
    ignore(
      DesktopOptions::new(
        windows=[DesktopWindowOptions::new("Orbit", options)],
        ipc_registry=Some(@ipc.CommandRegistry::new()),
      ),
    )
    false
  } catch {
    InitializationFailed(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "desktop options reject duplicate window labels" {
  let first = @runtime.RuntimeOptions::new(
    label="main",
    bounds=@runtime.RuntimeBounds::new(width=800, height=600),
    initial_content=Html("<main></main>"),
  )
  let second = @runtime.RuntimeOptions::new(
    label="main",
    bounds=@runtime.RuntimeBounds::new(width=640, height=480),
    initial_content=Html("<main></main>"),
  )
  let rejected = try {
    ignore(
      DesktopOptions::new(windows=[
        DesktopWindowOptions::new("First", first),
        DesktopWindowOptions::new("Second", second),
      ]),
    )
    false
  } catch {
    InitializationFailed(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "desktop options use the plugin directory from the environment" {
  @env.set_env_var("ORBIT_PLUGIN_DIRECTORY", "environment-plugins")
  let runtime_options = @runtime.RuntimeOptions::new(
    label="main",
    bounds=@runtime.RuntimeBounds::new(width=800, height=600),
    initial_content=Html("<main></main>"),
  )
  let from_environment = DesktopOptions::new(windows=[
    DesktopWindowOptions::new("Orbit", runtime_options),
  ])
  assert_eq(
    from_environment.plugin_development_directory,
    Some("environment-plugins"),
  )
  let configured = DesktopOptions::new(
    windows=[DesktopWindowOptions::new("Orbit", runtime_options)],
    plugin_development_directory=Some("configured-plugins"),
  )
  assert_eq(configured.plugin_development_directory, Some("configured-plugins"))
  @env.unset_env_var("ORBIT_PLUGIN_DIRECTORY")
}

///|
test "desktop options reject an empty plugin directory from the environment" {
  @env.set_env_var("ORBIT_PLUGIN_DIRECTORY", "   ")
  let runtime_options = @runtime.RuntimeOptions::new(
    label="main",
    bounds=@runtime.RuntimeBounds::new(width=800, height=600),
    initial_content=Html("<main></main>"),
  )
  let rejected = try {
    ignore(
      DesktopOptions::new(windows=[
        DesktopWindowOptions::new("Orbit", runtime_options),
      ]),
    )
    false
  } catch {
    InitializationFailed(_) => true
    _ => false
  }
  @env.unset_env_var("ORBIT_PLUGIN_DIRECTORY")
  assert_true(rejected)
}

///|
priv struct TestDesktopExtension {}

///|
impl DesktopExtension for TestDesktopExtension with fn identifier(_self) {
  "test.extension"
}

///|
impl DesktopExtension for TestDesktopExtension with fn commands(_self) {
  []
}

///|
impl DesktopExtension for TestDesktopExtension with fn start(_self, _controller) {
  Ok(())
}

///|
impl DesktopExtension for TestDesktopExtension with fn poll(_self, _controller) {
  Ok(())
}

///|
impl DesktopExtension for TestDesktopExtension with fn window_suspended(
  _self,
  _label,
) {
  Ok(())
}

///|
impl DesktopExtension for TestDesktopExtension with fn window_destroyed(
  _self,
  _label,
) {
  Ok(())
}

///|
impl DesktopExtension for TestDesktopExtension with fn shutdown(_self) {
  Ok(())
}

///|
fn TestDesktopExtension::as_extension(
  self : TestDesktopExtension,
) -> &DesktopExtension {
  self as &DesktopExtension
}

///|
test "desktop options retain ordered extensions and close policy" {
  let runtime_options = @runtime.RuntimeOptions::new(
    label="main",
    bounds=@runtime.RuntimeBounds::new(width=800, height=600),
    initial_content=Html("<main></main>"),
  )
  let extension = TestDesktopExtension::{  }
  let options = DesktopOptions::new(
    windows=[DesktopWindowOptions::new("Orbit", runtime_options)],
    extensions=[extension.as_extension()],
  )
  assert_eq(options.extensions.length(), 1)
  match options.close_request_handler {
    None => ()
    Some(_) => abort("expected the default close policy")
  }
}

///|
test "desktop options retain the runtime suspension handler" {
  let runtime_options = @runtime.RuntimeOptions::new(
    label="main",
    bounds=@runtime.RuntimeBounds::new(width=800, height=600),
    initial_content=Html("<main></main>"),
  )
  let options = DesktopOptions::new(
    windows=[DesktopWindowOptions::new("Orbit", runtime_options)],
    runtime_suspend_handler=Some(_label => Ok(())),
  )
  match options.runtime_suspend_handler {
    Some(_) => ()
    None => abort("expected the runtime suspension handler")
  }
  assert_eq(DesktopCloseAction::suspend(), DesktopCloseAction::suspend())
}

///|
test "desktop commands reject invalid names at construction" {
  let rejected = try {
    ignore(DesktopCommand::ui("", (_, _) => Ok(Json::null())))
    false
  } catch {
    InitializationFailed(_) => true
    _ => false
  }
  assert_true(rejected)
}
