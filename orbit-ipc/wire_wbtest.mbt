///|
test "error identifiers obey the same JSON limits as requests" {
  assert_eq(
    extract_request_id("{\"id\":\"valid\"}"),
    Some(InvocationId::new("valid")),
  )
  assert_eq(extract_request_id("{\"id\":\"first\",\"id\":\"second\"}"), None)
  let nested = "[".repeat(33) + "0" + "]".repeat(33)
  let deep = "{\"id\":\"deep\",\"payload\":\{nested}}"
  assert_eq(extract_request_id(deep), None)
  let large = "{\"id\":\"large\",\"payload\":\"" + "x".repeat(262_144) + "\"}"
  assert_eq(extract_request_id(large), None)
  let registry = CommandRegistry::new()
  assert_true(registry.dispatch(deep).contains("\"id\":null"))
  assert_true(registry.dispatch(large).contains("\"id\":null"))
}
