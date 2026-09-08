///|
test "concurrent writes of one capability use different temporary paths" {
  let first = temporary_write_path("selected.txt", "handle/+=")
  let second = temporary_write_path("selected.txt", "handle/+=")
  assert_false(first == second)
  assert_true(first.has_prefix("selected.txt.orbit-tmp-handle_--"))
}

///|
async test "failed exclusive creation leaves another operation's file intact" {
  link_async_fs()
  let directory = @fs.tmpdir(prefix="orbit-write-test")
  defer @fs.rmdir(directory)
  let path = directory + "/pending"
  defer remove_temporary_write(path)
  write_temporary_file(path, b"first")
  let rejected = try {
    write_temporary_file(path, b"second")
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  assert_eq(file.read_exactly_at(5, position=0), b"first")
}
