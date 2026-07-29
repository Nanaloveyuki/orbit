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
