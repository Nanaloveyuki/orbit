///|
pub(all) struct AppConfig {
  identifier : String
  name : String
  version : String
  product_name : String?
  publisher : String?
  windows : Array[WindowConfig]
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
pub(all) struct BundleConfig {
  icons : Array[String]
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct EmbeddedWebConfig {
  csp : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct RemoteWebConfig {
  http_url : String
  allowed_origins : Array[String]
  fallback_entry : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct WebConfig {
  embedded : EmbeddedWebConfig
  remote : RemoteWebConfig?
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct ViteBuildConfig {
  dev_command : String
  dev_url : String
  build_command : String
  dist_dir : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct BuildConfig {
  vite : ViteBuildConfig?
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct PrincipalConfig {
  kind : String
  identifier : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct ScopeConfig {
  kind : String
  value : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct CapabilityConfig {
  identifier : String
  effect : String
  principals : Array[PrincipalConfig]
  scopes : Array[ScopeConfig]
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
  bundle : BundleConfig
  web : WebConfig
  build : BuildConfig
  capabilities : Array[CapabilityConfig]
  plugins : Array[PluginConfig]
} derive(Eq, Debug, ToJson, FromJson)

///|
fn strict_config_json(source : StringView) -> Json raise ConfigError {
  let source = source.to_owned()
  match @strict_json.parse(source) {
    Ok(_) => ()
    Err(_) =>
      raise Invalid([
        diagnostic("invalid_json", "$", "configuration must be strict JSON"),
      ])
  }
  @json.parse(source) catch {
    error => raise Invalid([diagnostic("invalid_json", "$", error.to_string())])
  }
}

///|
fn json_schema_version(value : Json) -> Int? {
  match value {
    Object(object) =>
      match object.get("schema_version") {
        Some(Number(number, ..)) if number >= -2147483648.0 &&
          number <= 2147483647.0 &&
          number.to_int().to_double() == number => Some(number.to_int())
        _ => None
      }
    _ => None
  }
}

///|
fn unsupported_schema(expected : Int) -> ConfigError {
  Invalid([
    diagnostic(
      "unsupported_schema",
      "$.schema_version",
      "schema_version must be \{expected}",
    ),
  ])
}

///|
fn valid_optional_metadata(value : String?) -> Bool {
  match value {
    Some(value) => !value.trim().is_empty()
    None => true
  }
}

///|
fn valid_vite_url(value : String) -> Bool {
  (value.has_prefix("http://") || value.has_prefix("https://")) &&
  !value.has_suffix("/")
}

///|
fn https_origin(value : String) -> String? {
  if !value.has_prefix("https://") || value.length() <= 8 {
    return None
  }
  let chars = value.to_array()
  let mut end = chars.length()
  for index = 8; index < chars.length(); index = index + 1 {
    if chars[index] == '/' || chars[index] == '?' || chars[index] == '#' {
      end = index
      break
    }
  }
  let origin = String::from_array(chars[:end])
  if origin.length() <= 8 || origin.contains("@") || origin.contains(" ") {
    None
  } else {
    Some(origin)
  }
}

///|
fn valid_https_origin(value : String) -> Bool {
  match https_origin(value) {
    Some(origin) => origin == value
    None => false
  }
}

///|
fn valid_remote_url(value : String) -> Bool {
  match https_origin(value) {
    Some(_) => !value.contains(" ")
    None => false
  }
}

///|
fn valid_scope_kind(kind : String, value : String) -> Bool {
  match kind {
    "transport" =>
      value == "moonview" ||
      value == "http" ||
      value == "plugin" ||
      value == "background"
    "origin" => value.has_prefix("https://") && value.length() > 8
    _ => false
  }
}

///|
fn valid_principal_kind(kind : String) -> Bool {
  kind == "window" ||
  kind == "remote_page" ||
  kind == "http_client" ||
  kind == "plugin" ||
  kind == "background_task"
}

///|
pub fn validate_config(config : OrbitConfig) -> Array[ConfigDiagnostic] {
  let diagnostics : Array[ConfigDiagnostic] = []
  if config.schema_version != 2 {
    diagnostics.push(
      diagnostic(
        "unsupported_schema", "$.schema_version", "schema_version must be 2",
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
  if !valid_optional_metadata(config.app.product_name) {
    diagnostics.push(
      diagnostic(
        "invalid_metadata", "$.app.product_name", "product name must not be empty when configured",
      ),
    )
  }
  if !valid_optional_metadata(config.app.publisher) {
    diagnostics.push(
      diagnostic(
        "invalid_metadata", "$.app.publisher", "publisher must not be empty when configured",
      ),
    )
  }
  if config.app.windows.is_empty() {
    diagnostics.push(
      diagnostic("required", "$.app.windows", "at least one window is required"),
    )
  }
  let labels : Map[String, Bool] = Map([])
  for index, window in config.app.windows {
    let path = "$.app.windows[\{index}]"
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
    if window.title.trim().is_empty() {
      diagnostics.push(
        diagnostic(
          "required",
          path + ".title",
          "window title must not be empty",
        ),
      )
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
  let icon_paths : Map[String, Bool] = Map([])
  for index, icon in config.bundle.icons {
    let path = "$.bundle.icons[\{index}]"
    let icon = icon.trim().to_owned()
    match normalize_resource_path(icon) {
      Ok(normalized) =>
        if icon_paths.contains(normalized) {
          diagnostics.push(
            diagnostic(
              "duplicate_icon", path, "bundle icon must not be repeated",
            ),
          )
        } else {
          icon_paths[normalized] = true
        }
      Err(_) =>
        diagnostics.push(
          diagnostic(
            "invalid_icon", path, "bundle icon must be a normalized relative resource path",
          ),
        )
    }
  }
  if config.web.embedded.csp.trim().is_empty() {
    diagnostics.push(
      diagnostic(
        "required", "$.web.embedded.csp", "CSP policy must not be empty",
      ),
    )
  }
  match config.web.remote {
    Some(remote) => {
      let remote_url = remote.http_url.trim().to_owned()
      let remote_origin = https_origin(remote_url)
      if !valid_remote_url(remote_url) {
        diagnostics.push(
          diagnostic(
            "invalid_remote_url", "$.web.remote.http_url", "remote http_url must be an HTTPS URL",
          ),
        )
      }
      match normalize_resource_path(remote.fallback_entry) {
        Ok(_) => ()
        Err(_) =>
          diagnostics.push(
            diagnostic(
              "invalid_fallback_entry", "$.web.remote.fallback_entry", "remote fallback_entry must be a normalized relative resource path",
            ),
          )
      }
      if remote.allowed_origins.is_empty() {
        diagnostics.push(
          diagnostic(
            "required", "$.web.remote.allowed_origins", "remote mode requires at least one allowed HTTPS origin",
          ),
        )
      }
      let origins : Map[String, Bool] = Map([])
      for index, origin in remote.allowed_origins {
        let path = "$.web.remote.allowed_origins[\{index}]"
        let origin = origin.trim().to_owned()
        if !valid_https_origin(origin) {
          diagnostics.push(
            diagnostic(
              "invalid_remote_origin", path, "remote allowed origin must be an exact HTTPS origin",
            ),
          )
        } else if origins.contains(origin) {
          diagnostics.push(
            diagnostic(
              "duplicate_remote_origin", path, "remote allowed origin must not be repeated",
            ),
          )
        } else {
          origins[origin] = true
        }
      }
      match remote_origin {
        Some(origin) if !origins.contains(origin) =>
          diagnostics.push(
            diagnostic(
              "remote_origin_not_allowed", "$.web.remote.http_url", "remote URL origin must be included in allowed_origins",
            ),
          )
        _ => ()
      }
    }
    None => ()
  }
  match config.build.vite {
    Some(vite) => {
      if vite.dev_command.trim().is_empty() ||
        vite.build_command.trim().is_empty() {
        diagnostics.push(
          diagnostic(
            "required", "$.build.vite", "Vite commands must not be empty",
          ),
        )
      }
      if !valid_vite_url(vite.dev_url.trim().to_owned()) {
        diagnostics.push(
          diagnostic(
            "invalid_vite_url", "$.build.vite.dev_url", "Vite development URL must use http or https without a trailing slash",
          ),
        )
      }
      match normalize_resource_path(vite.dist_dir) {
        Ok(_) => ()
        Err(_) =>
          diagnostics.push(
            diagnostic(
              "invalid_dist_dir", "$.build.vite.dist_dir", "Vite dist directory must be a normalized relative path",
            ),
          )
      }
    }
    None => ()
  }
  if config.web.remote is Some(_) && config.build.vite is Some(_) {
    diagnostics.push(
      diagnostic(
        "remote_vite_conflict", "$.build.vite", "remote web mode cannot be combined with a Vite workflow",
      ),
    )
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
    if capability.effect != "allow" && capability.effect != "deny" {
      diagnostics.push(
        diagnostic(
          "invalid_capability_effect",
          path + ".effect",
          "capability effect must be allow or deny",
        ),
      )
    }
    if capability.principals.is_empty() {
      diagnostics.push(
        diagnostic(
          "required",
          path + ".principals",
          "capability must target at least one principal",
        ),
      )
    }
    let principal_keys : Map[String, Bool] = Map([])
    for principal_index, principal in capability.principals {
      let principal_path = "\{path}.principals[\{principal_index}]"
      let kind = principal.kind.trim().to_owned()
      let principal_identifier = principal.identifier.trim().to_owned()
      let key = kind + ":" + principal_identifier
      if !valid_principal_kind(kind) ||
        !valid_command_name(principal_identifier) {
        diagnostics.push(
          diagnostic(
            "invalid_principal", principal_path, "principal kind or identifier is invalid",
          ),
        )
      } else if (kind == "window" || kind == "remote_page") &&
        !labels.contains(principal_identifier) {
        diagnostics.push(
          diagnostic(
            "unknown_window", principal_path, "window or remote page principal must reference a configured window label",
          ),
        )
      } else if principal_keys.contains(key) {
        diagnostics.push(
          diagnostic(
            "duplicate_principal", principal_path, "principal must not be repeated within a capability",
          ),
        )
      } else {
        principal_keys[key] = true
      }
    }
    let scope_keys : Map[String, Bool] = Map([])
    for scope_index, scope in capability.scopes {
      let scope_path = "\{path}.scopes[\{scope_index}]"
      let kind = scope.kind.trim().to_owned()
      let value = scope.value.trim().to_owned()
      let key = kind + ":" + value
      if !valid_scope_kind(kind, value) {
        diagnostics.push(
          diagnostic(
            "invalid_scope", scope_path, "scope kind or value is invalid",
          ),
        )
      } else if scope_keys.contains(key) {
        diagnostics.push(
          diagnostic(
            "duplicate_scope", scope_path, "scope must not be repeated within a capability",
          ),
        )
      } else {
        scope_keys[key] = true
      }
    }
    let targets_remote_page = capability.principals.any(principal => {
      principal.kind.trim() == "remote_page"
    })
    if targets_remote_page {
      match config.web.remote {
        Some(remote) => {
          let has_moonview = capability.scopes.any(scope => {
            scope.kind.trim() == "transport" && scope.value.trim() == "moonview"
          })
          let has_allowed_origin = capability.scopes.any(scope => {
            scope.kind.trim() == "origin" &&
            remote.allowed_origins.any(origin => {
              origin.trim() == scope.value.trim()
            })
          })
          let all_origins_allowed = capability.scopes.all(scope => {
            scope.kind.trim() != "origin" ||
            remote.allowed_origins.any(origin => {
              origin.trim() == scope.value.trim()
            })
          })
          if !has_moonview || !has_allowed_origin || !all_origins_allowed {
            diagnostics.push(
              diagnostic(
                "remote_scope_required",
                path + ".scopes",
                "remote page capabilities require moonview transport and only allowed HTTPS origin scopes",
              ),
            )
          }
        }
        None =>
          diagnostics.push(
            diagnostic(
              "remote_without_config",
              path + ".principals",
              "remote page capabilities require web.remote configuration",
            ),
          )
      }
    }
    if capability.commands.is_empty() {
      diagnostics.push(
        diagnostic(
          "required",
          path + ".commands",
          "capability must contain at least one command",
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
  diagnostics
}

///|
pub fn normalize_config(config : OrbitConfig) -> OrbitConfig {
  let windows = config.app.windows.map(window => WindowConfig::{
    label: window.label.trim().to_owned(),
    title: window.title.trim().to_owned(),
    width: window.width,
    height: window.height,
    entry: normalize_resource_path(window.entry).unwrap_or(window.entry),
    visible: window.visible,
    resizable: window.resizable,
  })
  let vite = config.build.vite.map(vite => ViteBuildConfig::{
    dev_command: vite.dev_command.trim().to_owned(),
    dev_url: vite.dev_url.trim().to_owned(),
    build_command: vite.build_command.trim().to_owned(),
    dist_dir: normalize_resource_path(vite.dist_dir).unwrap_or(vite.dist_dir),
  })
  let capabilities = config.capabilities.map(capability => CapabilityConfig::{
    identifier: capability.identifier.trim().to_owned(),
    effect: capability.effect.trim().to_owned(),
    principals: capability.principals.map(principal => {
      kind: principal.kind.trim().to_owned(),
      identifier: principal.identifier.trim().to_owned(),
    }),
    scopes: capability.scopes.map(scope => {
      kind: scope.kind.trim().to_owned(),
      value: scope.value.trim().to_owned(),
    }),
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
      product_name: config.app.product_name.map(value => value.trim().to_owned()),
      publisher: config.app.publisher.map(value => value.trim().to_owned()),
      windows,
    },
    bundle: {
      icons: config.bundle.icons.map(icon => {
        normalize_resource_path(icon).unwrap_or(icon)
      }),
    },
    web: {
      embedded: { csp: config.web.embedded.csp.trim().to_owned() },
      remote: config.web.remote.map(remote => {
        http_url: remote.http_url.trim().to_owned(),
        allowed_origins: remote.allowed_origins.map(origin => {
          origin.trim().to_owned()
        }),
        fallback_entry: normalize_resource_path(remote.fallback_entry).unwrap_or(
          remote.fallback_entry,
        ),
      }),
    },
    build: { vite, },
    capabilities,
    plugins,
  }
}

///|
pub fn parse_config(source : StringView) -> OrbitConfig raise ConfigError {
  let value = strict_config_json(source)
  if json_schema_version(value) != Some(2) {
    raise unsupported_schema(2)
  }
  let shape_diagnostics = validate_v2_config_shape(value)
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
pub fn canonicalize_config(config : OrbitConfig) -> String {
  ToJson::to_json(normalize_config(config)).stringify()
}

///|
pub fn compile_config(source : StringView) -> EmbeddedConfig raise ConfigError {
  let config = parse_config(source)
  let canonical_json = canonicalize_config(config)
  let fingerprint = fingerprint_string(canonical_json)
  { canonical_json, fingerprint }
}

///|
pub fn migrate_config_v1(source : StringView) -> String raise ConfigError {
  let config = parse_v1_config(source)
  let windows = config.windows.map(window => WindowConfig::{
    label: window.label,
    title: window.title,
    width: window.width,
    height: window.height,
    entry: window.entry,
    visible: window.visible,
    resizable: window.resizable,
  })
  let capabilities = config.capabilities.map(capability => CapabilityConfig::{
    identifier: capability.identifier,
    effect: "allow",
    principals: capability.windows.map(window => {
      kind: "window",
      identifier: window,
    }),
    scopes: [],
    commands: capability.commands,
  })
  canonicalize_config({
    schema_version: 2,
    app: {
      identifier: config.app.identifier,
      name: config.app.name,
      version: config.app.version,
      product_name: Some(config.app.name),
      publisher: None,
      windows,
    },
    bundle: { icons: [] },
    web: { embedded: { csp: config.security.csp }, remote: None },
    build: { vite: None },
    capabilities,
    plugins: config.plugins.map(plugin => {
      id: plugin.id,
      library: plugin.library,
      permissions: plugin.permissions,
    }),
  })
}
