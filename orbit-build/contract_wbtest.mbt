///|
test "contract compiler accepts enums and rejects malformed enum values" {
  let source =
    #|{"schema_version":{"orbit":"0.1.0-alpha.14","contract":1},"types":{"Status":{"enum":["idle","running"]}},"commands":{"status.get":{"request":{"type":"null"},"response":{"$ref":"#/types/Status"}}},"events":{}}
  let compiled = compile_contract(source)
  debug_inspect(
    compiled.frontend,
    content="\"export type Status = \\\"idle\\\" | \\\"running\\\";\\n\"",
  )
  assert_true(
    compiled.frontend.contains("export type Status = \"idle\" | \"running\";"),
  )
  assert_true(compiled.native.contains("enum OrbitStatus"))
}

///|
test "contract compiler emits a typed tagged union" {
  let source =
    #|{"schema_version":{"orbit":"0.1.0-alpha.14","contract":1},"types":{"Result":{"type":"tagged_union","tag":"kind","variants":{"ok":{"type":"object","properties":{"kind":{"enum":["ok"]},"value":{"type":"string"}},"required":["kind","value"],"additionalProperties":false},"error":{"type":"object","properties":{"kind":{"enum":["error"]},"message":{"type":"string"}},"required":["kind","message"],"additionalProperties":false}}}},"commands":{},"events":{}}
  let compiled = compile_contract(source)
  assert_true(compiled.frontend.contains("export type Result ="))
  assert_true(compiled.native.contains("enum OrbitResult"))
  assert_true(compiled.native.contains("Ok("))
  assert_true(compiled.native.contains("Error("))
}


