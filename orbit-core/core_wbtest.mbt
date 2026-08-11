///|
test "runtime suspension preparation returns the state persistence error" {
  let labels : Array[String] = []
  let result = prepare_runtime_suspension(
    Some(label => {
      labels.push(label)
      Err("state persistence failed")
    }),
    "main",
  )
  assert_eq(labels, ["main"])
  match result {
    Err(reason) => assert_true(reason.contains("state persistence failed"))
    Ok(_) => abort("expected state preparation to reject suspension")
  }
}
