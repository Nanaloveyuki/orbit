///|
fn has_name(names : ArrayView[String], candidate : String) -> Bool {
  for name in names {
    if name == candidate {
      return true
    }
  }
  false
}

///|
fn validate_object_keys(
  object : Map[String, Json],
  path : String,
  required : Array[String],
  diagnostics : Array[ConfigDiagnostic],
) -> Unit {
  for name, _ in object {
    if !has_name(required, name) {
      diagnostics.push(
        diagnostic(
          "unknown_field",
          path + "." + name,
          "field is not part of the Orbit configuration schema",
        ),
      )
    }
  }
  for name in required {
    if !object.contains(name) {
      diagnostics.push(
        diagnostic(
          "missing_field",
          path + "." + name,
          "required field is missing",
        ),
      )
    }
  }
}

///|
fn validate_string_field(
  object : Map[String, Json],
  name : String,
  path : String,
  diagnostics : Array[ConfigDiagnostic],
) -> Unit {
  match object.get(name) {
    Some(String(_)) | None => ()
    Some(_) =>
      diagnostics.push(
        diagnostic("invalid_type", path + "." + name, "field must be a string"),
      )
  }
}

///|
fn validate_bool_field(
  object : Map[String, Json],
  name : String,
  path : String,
  diagnostics : Array[ConfigDiagnostic],
) -> Unit {
  match object.get(name) {
    Some(True) | Some(False) | None => ()
    Some(_) =>
      diagnostics.push(
        diagnostic("invalid_type", path + "." + name, "field must be a boolean"),
      )
  }
}

///|
fn validate_int_field(
  object : Map[String, Json],
  name : String,
  path : String,
  diagnostics : Array[ConfigDiagnostic],
) -> Unit {
  match object.get(name) {
    Some(Number(number, ..)) =>
      if number > 2147483647.0 || number < -2147483648.0 {
        diagnostics.push(
          diagnostic(
            "invalid_type",
            path + "." + name,
            "integer field is outside the supported range",
          ),
        )
      } else if number.to_int().to_double() != number {
        diagnostics.push(
          diagnostic(
            "invalid_type",
            path + "." + name,
            "field must be an integer",
          ),
        )
      }
    None => ()
    Some(_) =>
      diagnostics.push(
        diagnostic(
          "invalid_type",
          path + "." + name,
          "field must be an integer",
        ),
      )
  }
}

///|
fn validate_string_array(
  value : Json,
  path : String,
  diagnostics : Array[ConfigDiagnostic],
) -> Unit {
  match value {
    Array(values) =>
      for index, value in values {
        match value {
          String(_) => ()
          _ =>
            diagnostics.push(
              diagnostic(
                "invalid_type",
                "\{path}[\{index}]",
                "array item must be a string",
              ),
            )
        }
      }
    _ =>
      diagnostics.push(
        diagnostic("invalid_type", path, "field must be an array"),
      )
  }
}

///|
fn validate_app_shape(
  value : Json,
  diagnostics : Array[ConfigDiagnostic],
) -> Unit {
  match value {
    Object(object) => {
      validate_object_keys(
        object,
        "$.app",
        ["identifier", "name", "version"],
        diagnostics,
      )
      validate_string_field(object, "identifier", "$.app", diagnostics)
      validate_string_field(object, "name", "$.app", diagnostics)
      validate_string_field(object, "version", "$.app", diagnostics)
    }
    _ =>
      diagnostics.push(
        diagnostic("invalid_type", "$.app", "field must be an object"),
      )
  }
}

///|
fn validate_windows_shape(
  value : Json,
  diagnostics : Array[ConfigDiagnostic],
) -> Unit {
  match value {
    Array(windows) =>
      for index, value in windows {
        let path = "$.windows[\{index}]"
        match value {
          Object(object) => {
            validate_object_keys(
              object,
              path,
              [
                "label", "title", "width", "height", "entry", "visible", "resizable",
              ],
              diagnostics,
            )
            validate_string_field(object, "label", path, diagnostics)
            validate_string_field(object, "title", path, diagnostics)
            validate_int_field(object, "width", path, diagnostics)
            validate_int_field(object, "height", path, diagnostics)
            validate_string_field(object, "entry", path, diagnostics)
            validate_bool_field(object, "visible", path, diagnostics)
            validate_bool_field(object, "resizable", path, diagnostics)
          }
          _ =>
            diagnostics.push(
              diagnostic("invalid_type", path, "window must be an object"),
            )
        }
      }
    _ =>
      diagnostics.push(
        diagnostic("invalid_type", "$.windows", "field must be an array"),
      )
  }
}

///|
fn validate_security_shape(
  value : Json,
  diagnostics : Array[ConfigDiagnostic],
) -> Unit {
  match value {
    Object(object) => {
      validate_object_keys(object, "$.security", ["csp"], diagnostics)
      validate_string_field(object, "csp", "$.security", diagnostics)
    }
    _ =>
      diagnostics.push(
        diagnostic("invalid_type", "$.security", "field must be an object"),
      )
  }
}

///|
fn validate_capabilities_shape(
  value : Json,
  diagnostics : Array[ConfigDiagnostic],
) -> Unit {
  match value {
    Array(capabilities) =>
      for index, value in capabilities {
        let path = "$.capabilities[\{index}]"
        match value {
          Object(object) => {
            validate_object_keys(
              object,
              path,
              ["identifier", "windows", "commands"],
              diagnostics,
            )
            validate_string_field(object, "identifier", path, diagnostics)
            match object.get("windows") {
              Some(value) =>
                validate_string_array(value, path + ".windows", diagnostics)
              None => ()
            }
            match object.get("commands") {
              Some(value) =>
                validate_string_array(value, path + ".commands", diagnostics)
              None => ()
            }
          }
          _ =>
            diagnostics.push(
              diagnostic("invalid_type", path, "capability must be an object"),
            )
        }
      }
    _ =>
      diagnostics.push(
        diagnostic("invalid_type", "$.capabilities", "field must be an array"),
      )
  }
}

///|
fn validate_plugins_shape(
  value : Json,
  diagnostics : Array[ConfigDiagnostic],
) -> Unit {
  match value {
    Array(plugins) =>
      for index, value in plugins {
        let path = "$.plugins[\{index}]"
        match value {
          Object(object) => {
            validate_object_keys_with_optional(
              object,
              path,
              ["id", "library", "permissions"],
              ["manifest"],
              diagnostics,
            )
            validate_string_field(object, "id", path, diagnostics)
            validate_string_field(object, "library", path, diagnostics)
            match object.get("manifest") {
              Some(_) =>
                validate_string_field(object, "manifest", path, diagnostics)
              None => ()
            }
            match object.get("permissions") {
              Some(value) =>
                validate_string_array(value, path + ".permissions", diagnostics)
              None => ()
            }
          }
          _ =>
            diagnostics.push(
              diagnostic("invalid_type", path, "plugin must be an object"),
            )
        }
      }
    _ =>
      diagnostics.push(
        diagnostic("invalid_type", "$.plugins", "field must be an array"),
      )
  }
}

///|
fn validate_v1_config_shape(value : Json) -> Array[ConfigDiagnostic] {
  let diagnostics : Array[ConfigDiagnostic] = []
  match value {
    Object(object) => {
      validate_object_keys(
        object,
        "$",
        [
          "schema_version", "app", "windows", "security", "capabilities", "plugins",
        ],
        diagnostics,
      )
      validate_int_field(object, "schema_version", "$", diagnostics)
      match object.get("app") {
        Some(value) => validate_app_shape(value, diagnostics)
        None => ()
      }
      match object.get("windows") {
        Some(value) => validate_windows_shape(value, diagnostics)
        None => ()
      }
      match object.get("security") {
        Some(value) => validate_security_shape(value, diagnostics)
        None => ()
      }
      match object.get("capabilities") {
        Some(value) => validate_capabilities_shape(value, diagnostics)
        None => ()
      }
      match object.get("plugins") {
        Some(value) => validate_plugins_shape(value, diagnostics)
        None => ()
      }
    }
    _ =>
      diagnostics.push(
        diagnostic("invalid_type", "$", "configuration must be a JSON object"),
      )
  }
  diagnostics
}

///|
fn validate_object_keys_with_optional(
  object : Map[String, Json],
  path : String,
  required : Array[String],
  optional : Array[String],
  diagnostics : Array[ConfigDiagnostic],
) -> Unit {
  for name, _ in object {
    if !has_name(required, name) && !has_name(optional, name) {
      diagnostics.push(
        diagnostic(
          "unknown_field",
          path + "." + name,
          "field is not part of the Orbit configuration schema",
        ),
      )
    }
  }
  for name in required {
    if !object.contains(name) {
      diagnostics.push(
        diagnostic(
          "missing_field",
          path + "." + name,
          "required field is missing",
        ),
      )
    }
  }
}

///|
fn validate_v2_window_shape(
  value : Json,
  path : String,
  diagnostics : Array[ConfigDiagnostic],
) -> Unit {
  match value {
    Object(object) => {
      validate_object_keys(
        object,
        path,
        ["label", "title", "width", "height", "entry", "visible", "resizable"],
        diagnostics,
      )
      validate_string_field(object, "label", path, diagnostics)
      validate_string_field(object, "title", path, diagnostics)
      validate_int_field(object, "width", path, diagnostics)
      validate_int_field(object, "height", path, diagnostics)
      validate_string_field(object, "entry", path, diagnostics)
      validate_bool_field(object, "visible", path, diagnostics)
      validate_bool_field(object, "resizable", path, diagnostics)
    }
    _ =>
      diagnostics.push(
        diagnostic("invalid_type", path, "window must be an object"),
      )
  }
}

///|
fn validate_v2_app_shape(
  value : Json,
  diagnostics : Array[ConfigDiagnostic],
) -> Unit {
  match value {
    Object(object) => {
      validate_object_keys_with_optional(
        object,
        "$.app",
        ["identifier", "name", "version", "windows"],
        ["product_name", "publisher"],
        diagnostics,
      )
      validate_string_field(object, "identifier", "$.app", diagnostics)
      validate_string_field(object, "name", "$.app", diagnostics)
      validate_string_field(object, "version", "$.app", diagnostics)
      match object.get("product_name") {
        Some(String(_)) | Some(Null) | None => ()
        Some(_) =>
          diagnostics.push(
            diagnostic(
              "invalid_type", "$.app.product_name", "field must be a string or null",
            ),
          )
      }
      match object.get("publisher") {
        Some(String(_)) | Some(Null) | None => ()
        Some(_) =>
          diagnostics.push(
            diagnostic(
              "invalid_type", "$.app.publisher", "field must be a string or null",
            ),
          )
      }
      match object.get("windows") {
        Some(Array(windows)) =>
          for index, window in windows {
            validate_v2_window_shape(
              window,
              "$.app.windows[\{index}]",
              diagnostics,
            )
          }
        Some(_) =>
          diagnostics.push(
            diagnostic(
              "invalid_type", "$.app.windows", "field must be an array",
            ),
          )
        None => ()
      }
    }
    _ =>
      diagnostics.push(
        diagnostic("invalid_type", "$.app", "field must be an object"),
      )
  }
}

///|
fn validate_v2_bundle_shape(
  value : Json,
  diagnostics : Array[ConfigDiagnostic],
) -> Unit {
  match value {
    Object(object) => {
      validate_object_keys(object, "$.bundle", ["icons"], diagnostics)
      match object.get("icons") {
        Some(value) =>
          validate_string_array(value, "$.bundle.icons", diagnostics)
        None => ()
      }
    }
    _ =>
      diagnostics.push(
        diagnostic("invalid_type", "$.bundle", "field must be an object"),
      )
  }
}

///|
fn validate_v2_web_shape(
  value : Json,
  diagnostics : Array[ConfigDiagnostic],
) -> Unit {
  match value {
    Object(object) => {
      validate_object_keys_with_optional(
        object,
        "$.web",
        ["embedded"],
        ["remote"],
        diagnostics,
      )
      match object.get("embedded") {
        Some(Object(embedded)) => {
          validate_object_keys(embedded, "$.web.embedded", ["csp"], diagnostics)
          validate_string_field(embedded, "csp", "$.web.embedded", diagnostics)
        }
        Some(_) =>
          diagnostics.push(
            diagnostic(
              "invalid_type", "$.web.embedded", "field must be an object",
            ),
          )
        None => ()
      }
      match object.get("remote") {
        Some(Object(remote)) => {
          validate_object_keys(
            remote,
            "$.web.remote",
            ["http_url", "allowed_origins", "fallback_entry"],
            diagnostics,
          )
          validate_string_field(remote, "http_url", "$.web.remote", diagnostics)
          match remote.get("allowed_origins") {
            Some(value) =>
              validate_string_array(
                value, "$.web.remote.allowed_origins", diagnostics,
              )
            None => ()
          }
          validate_string_field(
            remote, "fallback_entry", "$.web.remote", diagnostics,
          )
        }
        Some(_) =>
          diagnostics.push(
            diagnostic(
              "invalid_type", "$.web.remote", "field must be an object",
            ),
          )
        None => ()
      }
    }
    _ =>
      diagnostics.push(
        diagnostic("invalid_type", "$.web", "field must be an object"),
      )
  }
}

///|
fn validate_v2_build_shape(
  value : Json,
  diagnostics : Array[ConfigDiagnostic],
) -> Unit {
  match value {
    Object(object) => {
      validate_object_keys_with_optional(
        object,
        "$.build",
        [],
        ["vite"],
        diagnostics,
      )
      match object.get("vite") {
        None => ()
        Some(Object(vite)) => {
          validate_object_keys(
            vite,
            "$.build.vite",
            ["dev_command", "dev_url", "build_command", "dist_dir"],
            diagnostics,
          )
          validate_string_field(
            vite, "dev_command", "$.build.vite", diagnostics,
          )
          validate_string_field(vite, "dev_url", "$.build.vite", diagnostics)
          validate_string_field(
            vite, "build_command", "$.build.vite", diagnostics,
          )
          validate_string_field(vite, "dist_dir", "$.build.vite", diagnostics)
        }
        Some(Null) => ()
        Some(_) =>
          diagnostics.push(
            diagnostic(
              "invalid_type", "$.build.vite", "field must be an object or null",
            ),
          )
      }
    }
    _ =>
      diagnostics.push(
        diagnostic("invalid_type", "$.build", "field must be an object"),
      )
  }
}

///|
fn validate_v2_capabilities_shape(
  value : Json,
  diagnostics : Array[ConfigDiagnostic],
) -> Unit {
  match value {
    Array(capabilities) =>
      for index, value in capabilities {
        let path = "$.capabilities[\{index}]"
        match value {
          Object(capability) => {
            validate_object_keys(
              capability,
              path,
              ["identifier", "effect", "principals", "scopes", "commands"],
              diagnostics,
            )
            validate_string_field(capability, "identifier", path, diagnostics)
            validate_string_field(capability, "effect", path, diagnostics)
            match capability.get("principals") {
              Some(Array(principals)) =>
                for principal_index, value in principals {
                  let principal_path = "\{path}.principals[\{principal_index}]"
                  match value {
                    Object(principal) => {
                      validate_object_keys(
                        principal,
                        principal_path,
                        ["kind", "identifier"],
                        diagnostics,
                      )
                      validate_string_field(
                        principal, "kind", principal_path, diagnostics,
                      )
                      validate_string_field(
                        principal, "identifier", principal_path, diagnostics,
                      )
                    }
                    _ =>
                      diagnostics.push(
                        diagnostic(
                          "invalid_type", principal_path, "principal must be an object",
                        ),
                      )
                  }
                }
              Some(_) =>
                diagnostics.push(
                  diagnostic(
                    "invalid_type",
                    path + ".principals",
                    "field must be an array",
                  ),
                )
              None => ()
            }
            match capability.get("scopes") {
              Some(Array(scopes)) =>
                for scope_index, value in scopes {
                  let scope_path = "\{path}.scopes[\{scope_index}]"
                  match value {
                    Object(scope) => {
                      validate_object_keys(
                        scope,
                        scope_path,
                        ["kind", "value"],
                        diagnostics,
                      )
                      validate_string_field(
                        scope, "kind", scope_path, diagnostics,
                      )
                      validate_string_field(
                        scope, "value", scope_path, diagnostics,
                      )
                    }
                    _ =>
                      diagnostics.push(
                        diagnostic(
                          "invalid_type", scope_path, "scope must be an object",
                        ),
                      )
                  }
                }
              Some(_) =>
                diagnostics.push(
                  diagnostic(
                    "invalid_type",
                    path + ".scopes",
                    "field must be an array",
                  ),
                )
              None => ()
            }
            match capability.get("commands") {
              Some(value) =>
                validate_string_array(value, path + ".commands", diagnostics)
              None => ()
            }
          }
          _ =>
            diagnostics.push(
              diagnostic("invalid_type", path, "capability must be an object"),
            )
        }
      }
    _ =>
      diagnostics.push(
        diagnostic("invalid_type", "$.capabilities", "field must be an array"),
      )
  }
}

///|
fn validate_v2_config_shape(value : Json) -> Array[ConfigDiagnostic] {
  let diagnostics : Array[ConfigDiagnostic] = []
  match value {
    Object(object) => {
      validate_object_keys(
        object,
        "$",
        [
          "schema_version", "app", "bundle", "web", "build", "capabilities", "plugins",
        ],
        diagnostics,
      )
      validate_int_field(object, "schema_version", "$", diagnostics)
      match object.get("app") {
        Some(value) => validate_v2_app_shape(value, diagnostics)
        None => ()
      }
      match object.get("bundle") {
        Some(value) => validate_v2_bundle_shape(value, diagnostics)
        None => ()
      }
      match object.get("web") {
        Some(value) => validate_v2_web_shape(value, diagnostics)
        None => ()
      }
      match object.get("build") {
        Some(value) => validate_v2_build_shape(value, diagnostics)
        None => ()
      }
      match object.get("capabilities") {
        Some(value) => validate_v2_capabilities_shape(value, diagnostics)
        None => ()
      }
      match object.get("plugins") {
        Some(value) => validate_plugins_shape(value, diagnostics)
        None => ()
      }
    }
    _ =>
      diagnostics.push(
        diagnostic("invalid_type", "$", "configuration must be a JSON object"),
      )
  }
  diagnostics
}
