///|
pub(all) struct AppConfig {
  identifier : String
  name : String
  version : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct WindowConfig {
  label : String
  title : String
  width : Int
  height : Int
  entry : String
  visible : Bool
  resizable : Bool
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct SecurityConfig {
  csp : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct OrbitConfig {
  schema_version : Int
  app : AppConfig
  windows : Array[WindowConfig]
  security : SecurityConfig
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct ConfigDiagnostic {
  code : String
  path : String
  message : String
} derive(Eq, Debug, ToJson)

///|
pub(all) suberror ConfigError {
  Invalid(Array[ConfigDiagnostic])
} derive(Debug)

///|
pub struct EmbeddedConfig {
  canonical_json : String
  fingerprint : String
}

///|
pub fn EmbeddedConfig::canonical_json(self : EmbeddedConfig) -> String {
  self.canonical_json
}

///|
pub fn EmbeddedConfig::fingerprint(self : EmbeddedConfig) -> String {
  self.fingerprint
}

///|
fn diagnostic(
  code : String,
  path : String,
  message : String,
) -> ConfigDiagnostic {
  { code, path, message }
}

///|
fn valid_identifier_char(char : Char) -> Bool {
  let code = char.to_int()
  (code >= 48 && code <= 57) ||
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122) ||
  char == '-' ||
  char == '_' ||
  char == '.'
}

///|
fn has_only_identifier_chars(value : String) -> Bool {
  for char in value {
    if !valid_identifier_char(char) {
      return false
    }
  }
  true
}

///|
fn valid_dotted_identifier(value : String) -> Bool {
  if !has_only_identifier_chars(value) {
    return false
  }
  for segment in value.split(".") {
    if segment.is_empty() {
      return false
    }
  }
  true
}

///|
pub fn validate_config(config : OrbitConfig) -> Array[ConfigDiagnostic] {
  let diagnostics : Array[ConfigDiagnostic] = []
  if config.schema_version != 1 {
    diagnostics.push(
      diagnostic(
        "unsupported_schema", "$.schema_version", "schema_version must be 1",
      ),
    )
  }
  let identifier = config.app.identifier.trim().to_owned()
  if identifier.is_empty() ||
    !identifier.contains(".") ||
    !valid_dotted_identifier(identifier) {
    diagnostics.push(
      diagnostic(
        "invalid_identifier", "$.app.identifier", "identifier must be a non-empty dotted ASCII identifier",
      ),
    )
  }
  if config.app.name.trim().is_empty() {
    diagnostics.push(
      diagnostic("required", "$.app.name", "application name must not be empty"),
    )
  }
  if config.app.version.trim().is_empty() {
    diagnostics.push(
      diagnostic(
        "required", "$.app.version", "application version must not be empty",
      ),
    )
  }
  if config.windows.is_empty() {
    diagnostics.push(
      diagnostic("required", "$.windows", "at least one window is required"),
    )
  }
  let labels : Map[String, Bool] = Map([])
  for index, window in config.windows {
    let path = "$.windows[\{index}]"
    let label = window.label.trim().to_owned()
    if label.is_empty() || !has_only_identifier_chars(label) {
      diagnostics.push(
        diagnostic(
          "invalid_label",
          path + ".label",
          "window label must use ASCII letters, digits, dot, dash or underscore",
        ),
      )
    } else if labels.contains(label) {
      diagnostics.push(
        diagnostic(
          "duplicate_label",
          path + ".label",
          "window label must be unique",
        ),
      )
    } else {
      labels[label] = true
    }
    if window.width <= 0 ||
      window.height <= 0 ||
      window.width > 16384 ||
      window.height > 16384 {
      diagnostics.push(
        diagnostic(
          "invalid_dimensions", path, "window dimensions must be between 1 and 16384",
        ),
      )
    }
    match normalize_resource_path(window.entry) {
      Ok(_) => ()
      Err(_) =>
        diagnostics.push(
          diagnostic(
            "invalid_entry",
            path + ".entry",
            "window entry must be a normalized relative resource path",
          ),
        )
    }
  }
  if config.security.csp.trim().is_empty() {
    diagnostics.push(
      diagnostic("required", "$.security.csp", "CSP policy must not be empty"),
    )
  }
  diagnostics
}

///|
pub fn normalize_config(config : OrbitConfig) -> OrbitConfig {
  let windows = config.windows.map(window => WindowConfig::{
    label: window.label.trim().to_owned(),
    title: window.title.trim().to_owned(),
    width: window.width,
    height: window.height,
    entry: normalize_resource_path(window.entry).unwrap_or(window.entry),
    visible: window.visible,
    resizable: window.resizable,
  })
  {
    schema_version: config.schema_version,
    app: {
      identifier: config.app.identifier.trim().to_owned(),
      name: config.app.name.trim().to_owned(),
      version: config.app.version.trim().to_owned(),
    },
    windows,
    security: { csp: config.security.csp.trim().to_owned() },
  }
}

///|
pub fn parse_config(source : StringView) -> OrbitConfig raise ConfigError {
  let value = @json.parse(source) catch {
    error => raise Invalid([diagnostic("invalid_json", "$", error.to_string())])
  }
  let shape_diagnostics = validate_config_shape(value)
  if !shape_diagnostics.is_empty() {
    raise Invalid(shape_diagnostics)
  }
  let config : OrbitConfig = @json.from_json(value) catch {
    error =>
      raise Invalid([diagnostic("decode_failed", "$", error.to_string())])
  }
  let diagnostics = validate_config(config)
  if !diagnostics.is_empty() {
    raise Invalid(diagnostics)
  }
  normalize_config(config)
}

///|
fn quote_json(value : String) -> String {
  Json::string(value).stringify()
}

///|
pub fn canonicalize_config(config : OrbitConfig) -> String {
  let builder = StringBuilder()
  builder.write_string("{\"schema_version\":")
  builder.write_string(config.schema_version.to_string())
  builder.write_string(",\"app\":{\"identifier\":")
  builder.write_string(quote_json(config.app.identifier))
  builder.write_string(",\"name\":")
  builder.write_string(quote_json(config.app.name))
  builder.write_string(",\"version\":")
  builder.write_string(quote_json(config.app.version))
  builder.write_string("},\"windows\":[")
  for index, window in config.windows {
    if index > 0 {
      builder.write_char(',')
    }
    builder.write_string("{\"label\":")
    builder.write_string(quote_json(window.label))
    builder.write_string(",\"title\":")
    builder.write_string(quote_json(window.title))
    builder.write_string(",\"width\":")
    builder.write_string(window.width.to_string())
    builder.write_string(",\"height\":")
    builder.write_string(window.height.to_string())
    builder.write_string(",\"entry\":")
    builder.write_string(quote_json(window.entry))
    builder.write_string(",\"visible\":")
    builder.write_string(window.visible.to_string())
    builder.write_string(",\"resizable\":")
    builder.write_string(window.resizable.to_string())
    builder.write_char('}')
  }
  builder.write_string("],\"security\":{\"csp\":")
  builder.write_string(quote_json(config.security.csp))
  builder.write_string("}}")
  builder.to_string()
}

///|
pub fn compile_config(source : StringView) -> EmbeddedConfig raise ConfigError {
  let config = parse_config(source)
  let canonical_json = canonicalize_config(config)
  let fingerprint = fingerprint_string(canonical_json)
  { canonical_json, fingerprint }
}
