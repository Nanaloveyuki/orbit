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
fn validate_config_shape(value : Json) -> Array[ConfigDiagnostic] {
  let diagnostics : Array[ConfigDiagnostic] = []
  match value {
    Object(object) => {
      validate_object_keys(
        object,
        "$",
        ["schema_version", "app", "windows", "security"],
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
    }
    _ =>
      diagnostics.push(
        diagnostic("invalid_type", "$", "configuration must be a JSON object"),
      )
  }
  diagnostics
}
