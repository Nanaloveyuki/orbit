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
test "builtin file capabilities require explicit opt-in" {
  let runtime_options = @runtime.RuntimeOptions::new(
    label="main",
    bounds=@runtime.RuntimeBounds::new(width=800, height=600),
    initial_content=Html("<main></main>"),
  )
  let options = DesktopOptions::new(windows=[
    DesktopWindowOptions::new("Orbit", runtime_options),
  ])
  assert_false(options.builtin_file_capabilities_enabled())
  assert_true(
    options.with_builtin_file_capabilities().builtin_file_capabilities_enabled(),
  )
  assert_false(
    options
    .with_builtin_file_capabilities(enabled=false)
    .builtin_file_capabilities_enabled(),
  )
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
