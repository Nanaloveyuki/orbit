///|
let valid_config_source =
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
  #|      "entry": "index.html",
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
test "JSON syntax failures use structured diagnostics" {
  let diagnostic = try {
    ignore(parse_config("{\"schema_version\":"))
    ConfigDiagnostic::{ code: "accepted", path: "", message: "" }
  } catch {
    Invalid(diagnostics) => diagnostics[0]
  }
  inspect(diagnostic.code, content="invalid_json")
  inspect(diagnostic.path, content="$")
}

///|
test "configuration compiles to stable embedded data" {
  let embedded = compile_config(valid_config_source)
  inspect(embedded.fingerprint().length(), content="64")
  assert_true(embedded.canonical_json().contains("\"schema_version\":1"))
}

///|
test "configuration rejects unknown fields before decoding" {
  let invalid = valid_config_source.replace_all(
    old="\"schema_version\": 1,",
    new="\"schema_version\": 1, \"unexpected\": true,",
  )
  let code = try {
    ignore(parse_config(invalid))
    "accepted"
  } catch {
    Invalid(diagnostics) => diagnostics[0].code
  }
  inspect(code, content="unknown_field")
}

///|
test "configuration rejects fractional integer fields" {
  let invalid = valid_config_source.replace_all(
    old="\"width\": 1024",
    new="\"width\": 1024.5",
  )
  let code = try {
    ignore(parse_config(invalid))
    "accepted"
  } catch {
    Invalid(diagnostics) => diagnostics[0].code
  }
  inspect(code, content="invalid_type")
}

///|
test "configuration fingerprints ignore source formatting" {
  let compact = compile_config(
    compile_config(valid_config_source).canonical_json(),
  )
  inspect(
    compact.fingerprint(),
    content=compile_config(valid_config_source).fingerprint(),
  )
}

///|
test "configuration rejects empty application identifier segments" {
  let invalid = valid_config_source.replace_all(
    old="dev.orbit.example",
    new="dev..example",
  )
  let code = try {
    ignore(parse_config(invalid))
    "accepted"
  } catch {
    Invalid(diagnostics) => diagnostics[0].code
  }
  inspect(code, content="invalid_identifier")
}

///|
test "configuration reports structured validation diagnostics" {
  let invalid = valid_config_source.replace_all(
    old="\"schema_version\": 1",
    new="\"schema_version\": 2",
  )
  let code = try {
    ignore(parse_config(invalid))
    "accepted"
  } catch {
    Invalid(diagnostics) => diagnostics[0].code
  }
  inspect(code, content="unsupported_schema")
}

///|
test "capabilities must reference configured windows" {
  let invalid = valid_config_source.replace_all(
    old="\"windows\": [\"main\"]",
    new="\"windows\": [\"missing\"]",
  )
  let code = try {
    ignore(parse_config(invalid))
    "accepted"
  } catch {
    Invalid(diagnostics) => diagnostics[0].code
  }
  inspect(code, content="unknown_window")
}

///|
test "capability command names follow the IPC identifier grammar" {
  let invalid = valid_config_source.replace_all(
    old="\"example.ping\"",
    new="\"example ping\"",
  )
  let code = try {
    ignore(parse_config(invalid))
    "accepted"
  } catch {
    Invalid(diagnostics) => diagnostics[0].code
  }
  inspect(code, content="invalid_command_name")
}

///|
test "plugins require bundled relative native library paths" {
  let invalid = valid_config_source.replace_all(
    old="\"plugins\": []",
    new="\"plugins\": [{\"id\":\"demo.echo\",\"library\":\"F:/repo/demo.dll\",\"permissions\":[]}]",
  )
  let code = try {
    ignore(parse_config(invalid))
    "accepted"
  } catch {
    Invalid(diagnostics) => diagnostics[0].code
  }
  inspect(code, content="invalid_plugin_library")
}

///|
test "plugins contribute to canonical configuration" {
  let configured = valid_config_source.replace_all(
    old="\"plugins\": []",
    new="\"plugins\": [{\"id\":\"demo.echo\",\"library\":\"plugins/demo.dll\",\"permissions\":[\"fs.read\"]}]",
  )
  let canonical = compile_config(configured).canonical_json()
  assert_true(canonical.contains("\"plugins\""))
  assert_true(canonical.contains("plugins/demo.dll"))
}
