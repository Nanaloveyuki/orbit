///|
test "desktop options require a title" {
  let options = @runtime.RuntimeOptions::new(
    label="main",
    bounds=@runtime.RuntimeBounds::new(width=800, height=600),
    initial_content=Html("<main></main>"),
  )
  let rejected = try {
    ignore(DesktopOptions::new("", options))
    false
  } catch {
    InitializationFailed(_) => true
    _ => false
  }
  assert_true(rejected)
}
