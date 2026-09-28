///|
test "desktop extensions declare explicit command sets" {
  let hotkey = @orbit-desktop.DesktopHotkeyExtension::new()
  let clipboard = @orbit-desktop.DesktopClipboardExtension::new()
  let shell = @orbit-desktop.DesktopShellExtension::new()
  let session = @orbit-desktop.DesktopSessionExtension::new()
  let hotkey_commands = hotkey.as_extension().commands()
  let clipboard_commands = clipboard.as_extension().commands()
  let shell_commands = shell.as_extension().commands()
  let session_commands = session.as_extension().commands()
  assert_eq(hotkey.as_extension().identifier(), "orbit.desktop.hotkey")
  assert_eq(clipboard.as_extension().identifier(), "orbit.desktop.clipboard")
  assert_eq(shell.as_extension().identifier(), "orbit.desktop.shell")
  assert_eq(session.as_extension().identifier(), "orbit.desktop.session")
  assert_eq(hotkey_commands.length(), 3)
  assert_eq(clipboard_commands.length(), 3)
  assert_eq(shell_commands.length(), 5)
  assert_eq(session_commands.length(), 7)
  assert_eq(hotkey_commands[0].name().value(), "orbit.hotkey.supported")
  assert_eq(hotkey_commands[1].name().value(), "orbit.hotkey.register")
  assert_eq(hotkey_commands[2].name().value(), "orbit.hotkey.list")
  assert_eq(clipboard_commands[1].name().value(), "orbit.clipboard.read_text")
  assert_eq(clipboard_commands[2].name().value(), "orbit.clipboard.write_text")
  assert_eq(shell_commands[1].name().value(), "orbit.shell.open")
  assert_eq(shell_commands[2].name().value(), "orbit.paths.base")
  assert_eq(shell_commands[4].name().value(), "orbit.paths.project")
  assert_eq(session_commands[1].name().value(), "orbit.safe_storage.encrypt")
  assert_eq(session_commands[5].name().value(), "orbit.keepawake.acquire")
  assert_eq(session_commands[6].name().value(), "orbit.keepawake.release")
  match hotkey.as_extension().shutdown() {
    Ok(_) => ()
    Err(_) => abort("hotkey shutdown should succeed before start")
  }
}

///|
test "desktop hotkey reports support without registering a shortcut" {
  let supported = @proton_global_hotkey.is_supported()
  match @proton_global_hotkey.ensure_supported() {
    Ok(_) => assert_true(supported)
    Err(_) => assert_false(supported)
  }
}

///|
test "desktop directories resolve a home-backed config path or absence" {
  match @directories.BaseDirs::new() {
    None => ()
    Some(base) => {
      assert_false(base.home_dir().is_empty())
      assert_false(base.config_dir().is_empty())
      assert_false(base.cache_dir().is_empty())
      assert_false(base.data_dir().is_empty())
    }
  }
  match @directories.UserDirs::new() {
    None => ()
    Some(user) => assert_false(user.home_dir().is_empty())
  }
}

///|
test "desktop session and shell support probes do not mutate host state" {
  ignore(@proton_safe_storage.is_available())
  ignore(@proton_auto_launch.is_supported())
  ignore(@proton_shell.is_supported())
  ignore(@proton_clipboard.is_supported())
  let session = @orbit-desktop.DesktopSessionExtension::new()
  match session.as_extension().shutdown() {
    Ok(_) => ()
    Err(_) => abort("session shutdown should release nothing before acquire")
  }
}
