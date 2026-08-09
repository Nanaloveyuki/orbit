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
test "Windows WebView installer mode is optional and rejects unsupported values" {
  let configured = valid_config_source.replace_all(
    old="\"bundle\": { \"icons\": [] },",
    new="\"bundle\": { \"icons\": [], \"windows\": { \"webview_install_mode\": \"skip\" } },",
  )
  let config = parse_config(configured)
  match config.bundle.windows {
    Some(windows) => inspect(windows.webview_install_mode, content="skip")
    None => fail("expected Windows bundle configuration")
  }
  let unsupported = configured.replace_all(
    old="\"skip\"",
    new="\"fixed_runtime\"",
  )
  inspect(failure_code(unsupported), content="invalid_webview_install_mode")
  let unknown = configured.replace_all(
    old="\"webview_install_mode\": \"skip\"",
    new="\"unknown\": \"skip\"",
  )
  inspect(failure_code(unknown), content="unknown_field")
}

///|
test "Linux bundle metadata is optional, strict and normalized" {
  assert_true(parse_config(valid_config_source).bundle.linux is None)
  let configured = valid_config_source.replace_all(
    old="\"bundle\": { \"icons\": [] },",
    new=(
      #|"bundle": {
      #|    "icons": [],
      #|    "linux": {
      #|      "package_name": " orbit-example ",
      #|      "summary": " Orbit Example ",
      #|      "description": " Example desktop application ",
      #|      "license": " Apache-2.0 ",
      #|      "homepage": " https://orbit.example ",
      #|      "maintainer": " Orbit Team <orbit@example.com> ",
      #|      "category": " Utility ",
      #|      "deb": {"depends":[" libwebkit2gtk-4.1-0 "],"section":" utils ","priority":" optional "},
      #|      "rpm": {"requires":[" webkit2gtk4.1 "]},
      #|      "arch": {"depends":[" webkit2gtk-4.1 "]}
      #|    }
      #|  },
    ),
  )
  let config = parse_config(configured)
  match config.bundle.linux {
    Some(linux) => {
      inspect(linux.package_name, content="orbit-example")
      inspect(linux.summary, content="Orbit Example")
      assert_true(linux.homepage == Some("https://orbit.example"))
      match linux.deb {
        Some(deb) => {
          inspect(deb.depends[0], content="libwebkit2gtk-4.1-0")
          inspect(deb.section, content="utils")
          inspect(deb.priority, content="optional")
        }
        None => fail("expected Debian bundle configuration")
      }
      match linux.rpm {
        Some(rpm) => inspect(rpm.requires[0], content="webkit2gtk4.1")
        None => fail("expected RPM bundle configuration")
      }
      match linux.arch {
        Some(arch) => inspect(arch.depends[0], content="webkit2gtk-4.1")
        None => fail("expected Arch bundle configuration")
      }
    }
    None => fail("expected Linux bundle configuration")
  }
  let canonical = canonicalize_config(config)
  assert_true(canonical.contains("\"package_name\":\"orbit-example\""))
  let unknown = configured.replace_all(
    old="\"requires\":[\" webkit2gtk4.1 \"]",
    new="\"requires\":[\" webkit2gtk4.1 \"],\"group\":\"Applications/System\"",
  )
  inspect(failure_code(unknown), content="unknown_field")
}

///|
test "Linux bundle metadata rejects empty and duplicate dependencies" {
  let configured = valid_config_source.replace_all(
    old="\"bundle\": { \"icons\": [] },",
    new=(
      #|"bundle": {
      #|    "icons": [],
      #|    "linux": {
      #|      "package_name": "orbit-example",
      #|      "summary": "Orbit Example",
      #|      "description": "Example desktop application",
      #|      "license": "Apache-2.0",
      #|      "category": "Utility",
      #|      "rpm": {"requires":["webkit2gtk4.1", " webkit2gtk4.1 "]}
      #|    }
      #|  },
    ),
  )
  inspect(failure_code(configured), content="duplicate_linux_dependency")
  let empty = configured.replace_all(
    old="[\"webkit2gtk4.1\", \" webkit2gtk4.1 \"]",
    new="[\"   \"]",
  )
  inspect(failure_code(empty), content="required")
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

///|
test "remote web mode requires HTTPS origins and an embedded fallback" {
  let embedded =
    #|  "web": {
    #|    "embedded": { "csp": "default-src 'self'; script-src 'self'" }
    #|  },
  let remote =
    #|  "web": {
    #|    "embedded": { "csp": "default-src 'self'; script-src 'self'" },
    #|    "remote": {
    #|      "http_url": "https://app.example/start",
    #|      "allowed_origins": ["https://app.example"],
    #|      "fallback_entry": "assets/fallback.html"
    #|    }
    #|  },
  let configured = valid_config_source.replace_all(old=embedded, new=remote)
  let config = parse_config(configured)
  assert_true(config.web.remote is Some(_))
  let invalid_scheme = configured.replace_all(
    old="https://app.example/start",
    new="http://app.example/start",
  )
  inspect(failure_code(invalid_scheme), content="invalid_remote_url")
  let missing_origin = configured.replace_all(
    old="https://app.example\"],",
    new="https://other.example\"],",
  )
  inspect(failure_code(missing_origin), content="remote_origin_not_allowed")
}

///|
test "remote page capabilities require a MoonView origin-scoped grant" {
  let embedded =
    #|  "web": {
    #|    "embedded": { "csp": "default-src 'self'; script-src 'self'" }
    #|  },
  let remote =
    #|  "web": {
    #|    "embedded": { "csp": "default-src 'self'; script-src 'self'" },
    #|    "remote": {
    #|      "http_url": "https://app.example",
    #|      "allowed_origins": ["https://app.example"],
    #|      "fallback_entry": "assets/fallback.html"
    #|    }
    #|  },
  let configured = valid_config_source
    .replace_all(old=embedded, new=remote)
    .replace_all(
      old="\"kind\": \"window\", \"identifier\": \"main\"",
      new="\"kind\": \"remote_page\", \"identifier\": \"main\"",
    )
    .replace_all(
      old="\"scopes\": [],",
      new="\"scopes\": [{\"kind\": \"transport\", \"value\": \"moonview\"}, {\"kind\": \"origin\", \"value\": \"https://app.example\"}],",
    )
  assert_true(
    parse_config(configured).capabilities[0].principals[0].kind == "remote_page",
  )
  let unscoped = configured.replace_all(
    old="{\"kind\": \"origin\", \"value\": \"https://app.example\"}",
    new="{\"kind\": \"origin\", \"value\": \"https://other.example\"}",
  )
  inspect(failure_code(unscoped), content="remote_scope_required")
}

///|
test "plugin configuration requires an explicit sidecar path" {
  let configured = valid_config_source.replace_all(
    old="\"plugins\": []",
    new="\"plugins\": [{\"id\":\"demo.echo\",\"library\":\"plugins/demo.dll\",\"manifest\":\"plugins/demo.plugin.json\",\"permissions\":[]}]",
  )
  assert_true(
    parse_config(configured).plugins[0].manifest == "plugins/demo.plugin.json",
  )
  let missing = configured.replace_all(
    old="\"manifest\":\"plugins/demo.plugin.json\",",
    new="",
  )
  inspect(failure_code(missing), content="decode_failed")
}
