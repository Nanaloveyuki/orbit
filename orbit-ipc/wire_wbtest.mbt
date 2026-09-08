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

///|
test "wire input limits count Unicode scalars rather than bytes or UTF16 units" {
  let character = "\u{1F600}"
  assert_eq(character.length(), 2)
  let prefix = "{\"version\":1,\"id\":\"unicode\",\"command\":\"echo\",\"payload\":[\""
  let first = character.repeat(131_072)
  let middle = "\",\""
  let suffix = "\"]}"
  let second = character.repeat(
    262_144 - prefix.length() - 131_072 - middle.length() - suffix.length(),
  )
  let source = prefix + first + middle + second + suffix
  assert_true(source.length() > 262_144)
  assert_eq(decode_request(source).id().value(), "unicode")
  let rejected = CommandRegistry::new().dispatch(source + " ")
  assert_true(rejected.contains("invalid_request"))
  assert_true(rejected.contains("input size"))
}
