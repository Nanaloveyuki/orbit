///|
fn test_runtime_options() -> @runtime.RuntimeOptions {
  @runtime.RuntimeOptions::new(
    label="main",
    bounds=@runtime.RuntimeBounds::new(width=320, height=640) catch {
      _ => abort("test bounds should be valid")
    },
    initial_content=Url("orbit://app/index.html"),
  ) catch {
    _ => abort("test runtime options should be valid")
  }
}

///|
test "Android IPC registry and policy are configured together" {
  let registry = @ipc.CommandRegistry::new()
  let result = try {
    let _ = AndroidAppOptions::new(
      runtime_options=test_runtime_options(),
      ipc_registry=Some(registry),
    )
    Ok(())
  } catch {
    error => Err(error)
  }
  assert_true(result is Err(_))
}
