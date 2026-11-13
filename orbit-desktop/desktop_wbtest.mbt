///|
async test "unknown shell actions fail without invoking the host" {
  assert_eq(
    shell_action("unsupported", "/unused"),
    Err("unsupported shell action"),
  )
}

///|
async test "keep awake shutdown rejects acquisition and empty release is idempotent" {
  let extension = DesktopSessionExtension::new()
  assert_eq(release_keep_awake(extension), Ok(false))
  assert_eq(release_keep_awake(extension), Ok(false))
  assert_eq(extension.as_extension().shutdown(), Ok(()))
  @async.with_task_group(group => {
    match
      acquire_keep_awake(
        extension,
        group,
        @proton_keepawake.PreventSystemSleep,
        None,
      ) {
      Ok(_) => abort("shutdown session must not acquire a host guard")
      Err(failure) => assert_eq(failure.code, "desktop_unavailable")
    }
  })
}

///|
async test "keep awake validates reason before acquiring a host guard" {
  let extension = DesktopSessionExtension::new()
  let reason = String::make(TEXT_LIMIT + 1, 'x')
  @async.with_task_group(group => {
    match
      acquire_keep_awake(
        extension,
        group,
        @proton_keepawake.PreventSystemSleep,
        Some(reason),
      ) {
      Ok(_) => abort("oversized reason must not acquire a host guard")
      Err(failure) => assert_eq(failure.code, "invalid_payload")
    }
  })
  assert_eq(release_keep_awake(extension), Ok(false))
}
