///|
let valid_config_source =
  #|{
  #|  "schema_version": 2,
  #|  "app": {
  #|    "identifier": "dev.orbit.example",
  #|    "name": "Orbit Example",
  #|    "version": "0.1.0",
  #|    "product_name": "Orbit Example",
  #|    "windows": [
  #|      {
  #|        "label": "main",
  #|        "title": "Orbit Example",
  #|        "width": 1024,
  #|        "height": 720,
  #|        "entry": "assets/index.html",
  #|        "visible": true,
  #|        "resizable": true
  #|      }
  #|    ]
  #|  },
  #|  "bundle": { "icons": [] },
  #|  "web": {
  #|    "embedded": { "csp": "default-src 'self'; script-src 'self'" }
  #|  },
  #|  "build": {},
  #|  "capabilities": [
  #|    {
  #|      "identifier": "main-commands",
  #|      "effect": "allow",
  #|      "principals": [{ "kind": "window", "identifier": "main" }],
  #|      "scopes": [],
  #|      "commands": ["example.ping"]
  #|    }
  #|  ],
  #|  "plugins": []
  #|}

///|
let valid_v1_config_source =
  #|{
  #|  "schema_version": 1,
  #|  "app": {
  #|    "identifier": "dev.orbit.example",
  #|    "name": "Orbit Example",
  #|    "version": "0.1.0"
  #|  },
  #|  "windows": [
  #|    {
  #|      "label": "main",
  #|      "title": "Orbit Example",
  #|      "width": 1024,
  #|      "height": 720,
  #|      "entry": "assets/index.html",
  #|      "visible": true,
  #|      "resizable": true
  #|    }
  #|  ],
  #|  "security": {
  #|    "csp": "default-src 'self'; script-src 'self'"
  #|  },
  #|  "capabilities": [
  #|    {
  #|      "identifier": "main-commands",
  #|      "windows": ["main"],
  #|      "commands": ["example.ping"]
  #|    }
  #|  ],
  #|  "plugins": []
  #|}

///|
fn failure_code(source : StringView) -> String {
  try {
    ignore(parse_config(source))
    "accepted"
  } catch {
    Invalid(diagnostics) => diagnostics[0].code
  }
}

///|
test "configuration compiles to stable v2 embedded data" {
  let embedded = compile_config(valid_config_source)
  inspect(embedded.fingerprint().length(), content="64")
  assert_true(embedded.canonical_json().contains("\"schema_version\":2"))
  inspect(
    compile_config(embedded.canonical_json()).fingerprint(),
    content=embedded.fingerprint(),
  )
}

///|
test "v2 configuration rejects v1 input without a silent compatibility path" {
  inspect(failure_code(valid_v1_config_source), content="unsupported_schema")
}

///|
test "migration produces a parseable v2 configuration with window principals" {
  let migrated = migrate_config_v1(valid_v1_config_source)
  let config = parse_config(migrated)
  inspect(config.schema_version, content="2")
  assert_true(migrated.contains("\"effect\":\"allow\""))
  assert_true(migrated.contains("\"kind\":\"window\""))
  assert_true(migrated.contains("\"build\":{}"))
}

///|
test "migration rejects configuration versions other than v1" {
  let rejected = try {
    ignore(migrate_config_v1(valid_config_source))
    "accepted"
  } catch {
    Invalid(diagnostics) => diagnostics[0].code
  }
  inspect(rejected, content="unsupported_schema")
}

///|
test "strict JSON parsing rejects duplicate fields" {
  let invalid = valid_config_source.replace_all(
    old="\"schema_version\": 2,",
    new="\"schema_version\": 2, \"schema_version\": 2,",
  )
  inspect(failure_code(invalid), content="invalid_json")
}

///|
test "v2 configuration rejects unknown top-level fields" {
  let invalid = valid_config_source.replace_all(
    old="\"schema_version\": 2,",
    new="\"schema_version\": 2, \"windows\": [],",
  )
  inspect(failure_code(invalid), content="unknown_field")
}

///|
test "optional application metadata remains absent when not declared" {
  let without_product_name = valid_config_source.replace_all(
    old="    \"product_name\": \"Orbit Example\",\n",
    new="",
  )
  let config = parse_config(without_product_name)
  assert_true(config.app.product_name is None)
  assert_true(config.app.publisher is None)
}

///|
test "window capabilities must reference configured windows" {
  let invalid = valid_config_source.replace_all(
    old="\"identifier\": \"main\" }],",
    new="\"identifier\": \"missing\" }],",
  )
  inspect(failure_code(invalid), content="unknown_window")
}

///|
test "Vite configuration is optional but validates explicit workflows" {
  let configured = valid_config_source.replace_all(
    old="\"build\": {},",
    new="\"build\": {\"vite\": {\"dev_command\": \"npm run dev\", \"dev_url\": \"http://127.0.0.1:5173\", \"build_command\": \"npm run build\", \"dist_dir\": \"dist\"}},",
  )
  assert_true(parse_config(configured).build.vite is Some(_))
  let invalid = configured.replace_all(
    old="http://127.0.0.1:5173",
    new="file:///tmp/dev",
  )
  inspect(failure_code(invalid), content="invalid_vite_url")
  let trailing_slash = configured.replace_all(
    old="http://127.0.0.1:5173",
    new="http://127.0.0.1:5173/",
  )
  inspect(failure_code(trailing_slash), content="invalid_vite_url")
}

///|
test "capability scopes require declared transport or HTTPS origin values" {
  let configured = valid_config_source.replace_all(
    old="\"scopes\": [],",
    new="\"scopes\": [{\"kind\": \"transport\", \"value\": \"moonview\"}, {\"kind\": \"origin\", \"value\": \"https://app.example\"}],",
  )
  assert_true(parse_config(configured).capabilities[0].scopes.length() == 2)
  let invalid = configured.replace_all(
    old="https://app.example",
    new="http://app.example",
  )
  inspect(failure_code(invalid), content="invalid_scope")
}
