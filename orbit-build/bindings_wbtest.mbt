///|
test "bindings list page candidates without treating scoped denies as global" {
  let config_source =
    #|{
    #|  "schema_version": 2,
    #|  "app": {
    #|    "identifier": "dev.orbit.bindings", "name": "Bindings", "version": "1.0.0",
    #|    "windows": [
    #|      {"label":"main","title":"Main","width":800,"height":600,"entry":"assets/index.html","visible":true,"resizable":true},
    #|      {"label":"settings","title":"Settings","width":800,"height":600,"entry":"assets/index.html","visible":true,"resizable":true}
    #|    ]
    #|  },
    #|  "bundle": {"icons": []}, "web": {"embedded":{"csp":"default-src 'self'"}}, "build": {}, "plugins": [],
    #|  "capabilities": [
    #|    {"identifier":"main","effect":"allow","principals":[{"kind":"window","identifier":"main"}],"scopes":[],"commands":["shared.echo"]},
    #|    {"identifier":"settings","effect":"deny","principals":[{"kind":"window","identifier":"settings"}],"scopes":[],"commands":["shared.echo"]},
    #|    {"identifier":"origin","effect":"allow","principals":[{"kind":"window","identifier":"main"}],"scopes":[{"kind":"origin","value":"https://app.example"}],"commands":["origin.echo"]},
    #|    {"identifier":"http","effect":"allow","principals":[{"kind":"http_client","identifier":"client"}],"scopes":[],"commands":["http.echo"]}
    #|  ]
    #|}
  let config = @utils.parse_config(config_source)
  debug_inspect(
    page_command_names(config),
    content="[\"origin.echo\", \"shared.echo\"]",
  )
  let source = bindings_source(config, "fingerprint")
  assert_true(
    source.contains("export const configurationFingerprint = \"fingerprint\""),
  )
  assert_true(
    source.contains("const commandNames = [\"origin.echo\",\"shared.echo\"]"),
  )
  assert_false(source.contains("http.echo"))
  let declarations = bindings_declarations(config)
  assert_true(declarations.contains("\"origin.echo\": CommandDefinition"))
  assert_true(declarations.contains("signal?: AbortSignal"))
  assert_false(declarations.contains("http.echo"))
}
