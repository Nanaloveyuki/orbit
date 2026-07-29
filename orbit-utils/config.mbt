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
pub(all) struct CapabilityConfig {
  identifier : String
  windows : Array[String]
  commands : Array[String]
} derive(Eq, Debug, ToJson, FromJson)

///|
/// A native plugin declared by the application configuration.
///
/// `library` is always a normalized path relative to the installed
/// application root. Development overrides are deliberately runtime-only and
/// therefore never become part of an embedded configuration.
pub(all) struct PluginConfig {
  id : String
  library : String
  permissions : Array[String]
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct OrbitConfig {
  schema_version : Int
  app : AppConfig
  windows : Array[WindowConfig]
  security : SecurityConfig
  capabilities : Array[CapabilityConfig]
  plugins : Array[PluginConfig]
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
fn valid_command_name(value : String) -> Bool {
  if value.is_empty() || value.length() > 128 {
    return false
  }
  for char in value {
    let code = char.to_int()
    if !((code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      char == '-' ||
      char == '_' ||
      char == '.' ||
      char == ':' ||
      char == '/') {
      return false
    }
  }
  true
}

///|
fn valid_plugin_library_path(value : String) -> Bool {
  match normalize_resource_path(value) {
    Ok(path) =>
      path.has_prefix("plugins/") &&
      (
        path.has_suffix(".dll") ||
        path.has_suffix(".so") ||
        path.has_suffix(".dylib")
      )
    Err(_) => false
  }
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
  let capability_identifiers : Map[String, Bool] = Map([])
  for index, capability in config.capabilities {
    let path = "$.capabilities[\{index}]"
    let identifier = capability.identifier.trim().to_owned()
    if !valid_command_name(identifier) {
      diagnostics.push(
        diagnostic(
          "invalid_capability_identifier",
          path + ".identifier",
          "capability identifier must use ASCII command identifier characters",
        ),
      )
    } else if capability_identifiers.contains(identifier) {
      diagnostics.push(
        diagnostic(
          "duplicate_capability_identifier",
          path + ".identifier",
          "capability identifier must be unique",
        ),
      )
    } else {
      capability_identifiers[identifier] = true
    }
    if capability.windows.is_empty() {
      diagnostics.push(
        diagnostic(
          "required",
          path + ".windows",
          "capability must apply to at least one window",
        ),
      )
    }
    for window_index, window_label in capability.windows {
      let window_path = "\{path}.windows[\{window_index}]"
      let window_label = window_label.trim().to_owned()
      if !labels.contains(window_label) {
        diagnostics.push(
          diagnostic(
            "unknown_window", window_path, "capability window must reference a configured window label",
          ),
        )
      }
    }
    if capability.commands.is_empty() {
      diagnostics.push(
        diagnostic(
          "required",
          path + ".commands",
          "capability must allow at least one command",
        ),
      )
    }
    let command_names : Map[String, Bool] = Map([])
    for command_index, command in capability.commands {
      let command_path = "\{path}.commands[\{command_index}]"
      let command = command.trim().to_owned()
      if !valid_command_name(command) {
        diagnostics.push(
          diagnostic(
            "invalid_command_name", command_path, "capability command must use ASCII command identifier characters",
          ),
        )
      } else if command_names.contains(command) {
        diagnostics.push(
          diagnostic(
            "duplicate_command_name", command_path, "command must not be repeated within a capability",
          ),
        )
      } else {
        command_names[command] = true
      }
    }
  }
  let plugin_ids : Map[String, Bool] = Map([])
  for index, plugin in config.plugins {
    let path = "$.plugins[\{index}]"
    let id = plugin.id.trim().to_owned()
    if !valid_dotted_identifier(id) {
      diagnostics.push(
        diagnostic(
          "invalid_plugin_id",
          path + ".id",
          "plugin id must be a non-empty dotted ASCII identifier",
        ),
      )
    } else if plugin_ids.contains(id) {
      diagnostics.push(
        diagnostic(
          "duplicate_plugin_id",
          path + ".id",
          "plugin id must be unique",
        ),
      )
    } else {
      plugin_ids[id] = true
    }
    if !valid_plugin_library_path(plugin.library) {
      diagnostics.push(
        diagnostic(
          "invalid_plugin_library",
          path + ".library",
          "plugin library must be a normalized plugins/ relative path with a native library extension",
        ),
      )
    }
    let granted_permissions : Map[String, Bool] = Map([])
    for permission_index, permission in plugin.permissions {
      let permission_path = "\{path}.permissions[\{permission_index}]"
      let permission = permission.trim().to_owned()
      if !valid_command_name(permission) {
        diagnostics.push(
          diagnostic(
            "invalid_plugin_permission", permission_path, "plugin permission must use ASCII command identifier characters",
          ),
        )
      } else if granted_permissions.contains(permission) {
        diagnostics.push(
          diagnostic(
            "duplicate_plugin_permission", permission_path, "plugin permission must not be repeated",
          ),
        )
      } else {
        granted_permissions[permission] = true
      }
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
  let capabilities = config.capabilities.map(capability => CapabilityConfig::{
    identifier: capability.identifier.trim().to_owned(),
    windows: capability.windows.map(label => label.trim().to_owned()),
    commands: capability.commands.map(command => command.trim().to_owned()),
  })
  let plugins = config.plugins.map(plugin => PluginConfig::{
    id: plugin.id.trim().to_owned(),
    library: normalize_resource_path(plugin.library).unwrap_or(plugin.library),
    permissions: plugin.permissions.map(permission => {
      permission.trim().to_owned()
    }),
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
    capabilities,
    plugins,
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
  builder.write_string("},\"capabilities\":[")
  for index, capability in config.capabilities {
    if index > 0 {
      builder.write_char(',')
    }
    builder.write_string("{\"identifier\":")
    builder.write_string(quote_json(capability.identifier))
    builder.write_string(",\"windows\":[")
    for window_index, window in capability.windows {
      if window_index > 0 {
        builder.write_char(',')
      }
      builder.write_string(quote_json(window))
    }
    builder.write_string("],\"commands\":[")
    for command_index, command in capability.commands {
      if command_index > 0 {
        builder.write_char(',')
      }
      builder.write_string(quote_json(command))
    }
    builder.write_string("]}")
  }
  builder.write_string("],\"plugins\":[")
  for index, plugin in config.plugins {
    if index > 0 {
      builder.write_char(',')
    }
    builder.write_string("{\"id\":")
    builder.write_string(quote_json(plugin.id))
    builder.write_string(",\"library\":")
    builder.write_string(quote_json(plugin.library))
    builder.write_string(",\"permissions\":[")
    for permission_index, permission in plugin.permissions {
      if permission_index > 0 {
        builder.write_char(',')
      }
      builder.write_string(quote_json(permission))
    }
    builder.write_string("]}")
  }
  builder.write_string("]}")
  builder.to_string()
}

///|
pub fn compile_config(source : StringView) -> EmbeddedConfig raise ConfigError {
  let config = parse_config(source)
  let canonical_json = canonicalize_config(config)
  let fingerprint = fingerprint_string(canonical_json)
  { canonical_json, fingerprint }
}
