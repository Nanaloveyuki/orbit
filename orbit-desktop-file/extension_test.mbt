///|
test "file extension declares the complete capability bridge" {
  let extension = DesktopFileExtension::new()
  let commands = extension.as_extension().commands()
  assert_eq(commands.length(), 8)
  assert_eq(commands[0].name().value(), "orbit.dialog.open")
  assert_eq(commands[1].name().value(), "orbit.dialog.open_multiple")
  assert_eq(commands[2].name().value(), "orbit.dialog.save")
  assert_eq(commands[3].name().value(), "orbit.dialog.pick_directory")
  assert_eq(commands[4].name().value(), "orbit.fs.read_binary")
  assert_eq(commands[5].name().value(), "orbit.fs.read_text")
  assert_eq(commands[6].name().value(), "orbit.fs.write_text")
  assert_eq(commands[7].name().value(), "orbit.fs.read_directory")
}
