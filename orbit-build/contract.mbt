///|
priv suberror BindingContractError {
  BindingContractError(String)
} derive(Debug)

///|
priv struct ContractType {
  id : Int
  native_type : String
  frontend_type : String
}

///|
const CONTRACT_ORBIT_VERSION : String = "0.1.0-alpha.12"

///|
priv struct ContractCompiler {
  definitions : Map[String, Json]
  resolved : Map[String, ContractType]
  resolving : Map[String, Bool]
  native : Array[String]
  frontend : Array[String]
  mut next_id : Int
}

///|
priv struct CompiledContract {
  schema : Json
  native : String
  frontend : String
  commands : Map[String, (ContractType, ContractType)]
  events : Map[String, ContractType]
}

///|
fn[T] contract_error(
  path : String,
  message : String,
) -> T raise BindingContractError {
  raise BindingContractError("\{path}: \{message}")
}

///|
fn contract_object(
  value : Json,
  path : String,
) -> Map[String, Json] raise BindingContractError {
  match value {
    Object(fields) => fields
    _ => contract_error(path, "expected an object")
  }
}

///|
fn contract_keys(
  fields : Map[String, Json],
  allowed : Array[String],
  path : String,
) -> Unit raise BindingContractError {
  for key, _ in fields {
    if !allowed.contains(key) {
      contract_error(path + "." + key, "unsupported contract field")
    }
  }
}

///|
fn contract_required(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Json raise BindingContractError {
  match fields.get(key) {
    Some(value) => value
    None => contract_error(path + "." + key, "required field is missing")
  }
}

///|
fn[T] contract_names(values : Map[String, T]) -> Array[String] {
  let names = []
  for name, _ in values {
    names.push(name)
  }
  names.sort()
  names
}

///|
fn contract_quote(value : String) -> String {
  Json::string(value).stringify()
}

///|
fn contract_identifier(name : String, uppercase : Bool) -> Bool {
  if name.is_empty() {
    return false
  }
  for index, char in name.to_array() {
    let code = char.to_int()
    let upper = code >= 65 && code <= 90
    let lower = code >= 97 && code <= 122
    if index == 0 {
      if (uppercase && !upper) || (!uppercase && !lower) {
        return false
      }
    } else if !upper && !lower && !(code >= 48 && code <= 57) && char != '_' {
      return false
    }
  }
  ![
    "fn", "let", "mut", "match", "type", "struct", "enum", "trait", "pub", "priv",
    "async", "raise", "try", "catch", "else", "if", "for", "while", "return", "break",
    "continue", "guard", "in", "as", "impl", "with", "derive", "test", "const", "defer",
    "errdefer", "loop", "true", "false", "is", "using", "extern", "typealias",
  ].contains(name)
}

///|
fn ContractCompiler::finish(
  self : ContractCompiler,
  id : Int,
  native_type : String,
  frontend_type : String,
  decode : String,
  encode : String,
) -> ContractType {
  self.native.push(
    "///|\npub fn orbit_contract_decode_\{id}(value : Json, path : String) -> \{native_type} raise OrbitContractError {\n\{decode}\n}\n\n///|\npub fn orbit_contract_encode_\{id}(value : \{native_type}, path : String) -> Json {\n\{encode}\n}\n",
  )
  { id, native_type, frontend_type, }
}

///|
fn ContractCompiler::named(
  self : ContractCompiler,
  name : String,
  depth : Int,
) -> ContractType raise BindingContractError {
  match self.resolved.get(name) {
    Some(value) => return value
    None => ()
  }
  if self.resolving.contains(name) {
    contract_error(
      "types." + name,
      "recursive type references are not supported",
    )
  }
  let schema = contract_required(self.definitions, name, "types")
  self.resolving[name] = true
  let node = self.compile(
    schema,
    "types." + name,
    depth,
    name=Some("Orbit" + name),
  )
  self.resolving.remove(name)
  self.frontend.push("export type \{name} = \{node.frontend_type};")
  let result = { ..node, frontend_type: name, }
  self.resolved[name] = result
  result
}

///|
fn ContractCompiler::compile(
  self : ContractCompiler,
  schema : Json,
  path : String,
  depth : Int,
  name? : String? = None,
) -> ContractType raise BindingContractError {
  if depth > 64 {
    contract_error(path, "schema nesting exceeds 64 levels")
  }
  let fields = contract_object(schema, path)
  if fields.contains("$ref") {
    contract_keys(fields, ["$ref", "description"], path)
    let reference = match fields.get("$ref") {
      Some(String(reference)) if reference.has_prefix("#/types/") =>
        reference[8:].to_owned()
      _ => contract_error(path, "$ref must name #/types/Name")
    }
    return self.named(reference, depth + 1)
  }
  let id = self.next_id
  self.next_id += 1
  if fields.contains("anyOf") {
    contract_keys(fields, ["anyOf", "description"], path)
    let inner = match fields.get("anyOf") {
      Some(Array([left, right])) =>
        if left == { "type": "null" } {
          right
        } else if right == { "type": "null" } {
          left
        } else {
          contract_error(
            path, "anyOf supports exactly one nullable alternative",
          )
        }
      _ =>
        contract_error(
          path, "anyOf must contain a value schema and {type: null}",
        )
    }
    let child = self.compile(inner, path + ".anyOf", depth + 1)
    return self.finish(
      id,
      "\{child.native_type}?",
      "(\{child.frontend_type} | null)",
      "  match value { Null => None; _ => Some(orbit_contract_decode_\{child.id}(value, path)) }",
      "  match value { None => Null; Some(item) => orbit_contract_encode_\{child.id}(item, path) }",
    )
  }
  if fields.contains("enum") {
    contract_keys(fields, ["enum", "description"], path)
    let values = match fields.get("enum") {
      Some(Array(values)) =>
        values.map(value => {
          match value {
            String(value) => value
            _ => contract_error(path, "enum values must be strings")
          }
        })
      _ => contract_error(path, "enum must be an array")
    }
    if values.is_empty() {
      contract_error(path, "enum must contain at least one value")
    }
    let type_name = name.unwrap_or("OrbitContract\{id}")
    let variants = []
    let seen : Map[String, Bool] = Map([])
    for value in values {
      let variant = contract_type_name(value)
      if seen.contains(variant) {
        contract_error(
          path, "enum values collide after identifier normalization",
        )
      }
      seen[variant] = true
      variants.push("  \{variant}")
    }
    self.native.push(
      "///|\npub(all) enum \{type_name} {\n\{variants.join("\n")}\n} derive(Eq, Debug)\n",
    )
    let decode_cases = []
    let encode_cases = []
    for value in values {
      let variant = contract_type_name(value)
      decode_cases.push(
        "    \{contract_quote(value)} => \{type_name}::\{variant}",
      )
      encode_cases.push(
        "    \{type_name}::\{variant} => Json::string(\{contract_quote(value)})",
      )
    }
    return self.finish(
      id,
      type_name,
      values.map(contract_quote).join(" | "),
      "  match value {\n\{decode_cases.join("\n")}\n    _ => orbit_contract_fail(path)\n  }",
      "  ignore(path)\n  match value {\n\{encode_cases.join("\n")}\n  }",
    )
  }
  if fields.get("type") == Some("tagged_union") {
    contract_keys(fields, ["type", "tag", "variants", "description"], path)
    let tag = match contract_required(fields, "tag", path) {
      String(value) if contract_identifier(value, false) => value
      _ =>
        contract_error(
          path + ".tag",
          "tag must be a lower camel-case field name",
        )
    }
    let variants = contract_object(
      contract_required(fields, "variants", path),
      path + ".variants",
    )
    if variants.is_empty() {
      contract_error(path, "tagged_union must contain variants")
    }
    let type_name = name.unwrap_or("OrbitContract\{id}")
    let enum_cases = []
    let frontend_cases = []
    let decode_cases = []
    let encode_cases = []
    for variant_name in contract_names(variants) {
      let variant = contract_type_name(variant_name)
      let child = self.compile(
        variants[variant_name],
        path + ".variants." + variant_name,
        depth + 1,
        name=Some(type_name + variant),
      )
      enum_cases.push("  \{variant}(\{child.native_type})")
      frontend_cases.push(
        "(\{child.frontend_type} & { \{contract_quote(tag)}: \{contract_quote(variant_name)} })",
      )
      decode_cases.push(
        "    \{contract_quote(variant_name)} => \{type_name}::\{variant}(orbit_contract_decode_\{child.id}(value, path))",
      )
      encode_cases.push(
        "    \{type_name}::\{variant}(payload) => orbit_contract_encode_\{child.id}(payload, path)",
      )
    }
    self.native.push(
      "///|\npub(all) enum \{type_name} {\n\{enum_cases.join("\n")}\n} derive(Debug)\n",
    )
    let decode = "  guard value is Object(items) else { orbit_contract_fail(path) }\n  let tag_value = match items.get(\"\{tag}\") { Some(String(value)) => value; _ => orbit_contract_fail(path + \".\" + \{contract_quote(tag)}) }\n  match tag_value {\n\{decode_cases.join("\n")}\n    _ => orbit_contract_fail(path + \".\" + \{contract_quote(tag)})\n  }"
    let encode = "  ignore(path)\n  match value {\n\{encode_cases.join("\n")}\n  }"
    return self.finish(
      id,
      type_name,
      frontend_cases.join(" | "),
      decode,
      encode,
    )
  }
  let kind = match fields.get("type") {
    Some(String(kind)) => kind
    _ => contract_error(path, "type is required")
  }
  let scalar_keys = ["type", "description"]
  match kind {
    "string" => {
      contract_keys(fields, scalar_keys, path)
      self.finish(
        id, "String", "string", "  match value { String(text) => text; _ => orbit_contract_fail(path) }",
        "  ignore(path)\n  Json::string(value)",
      )
    }
    "boolean" => {
      contract_keys(fields, scalar_keys, path)
      self.finish(
        id, "Bool", "boolean", "  match value { True => true; False => false; _ => orbit_contract_fail(path) }",
        "  ignore(path)\n  Json::boolean(value)",
      )
    }
    "null" => {
      contract_keys(fields, scalar_keys, path)
      self.finish(
        id, "Unit", "null", "  match value { Null => (); _ => orbit_contract_fail(path) }",
        "  ignore(value)\n  ignore(path)\n  Json::null()",
      )
    }
    "integer" => {
      contract_keys(fields, scalar_keys, path)
      self.finish(
        id, "Int", "number", "  match value { Number(number, ..) if number >= -2147483648.0 && number <= 2147483647.0 && number.to_int().to_double() == number => number.to_int(); _ => orbit_contract_fail(path) }",
        "  ignore(path)\n  Json(value)",
      )
    }
    "number" => {
      contract_keys(fields, scalar_keys, path)
      self.finish(
        id, "Double", "number", "  match value { Number(number, ..) => number; _ => orbit_contract_fail(path) }",
        "  ignore(path)\n  Json(value)",
      )
    }
    "array" => {
      contract_keys(fields, ["type", "items", "description"], path)
      let child = self.compile(
        contract_required(fields, "items", path),
        path + ".items",
        depth + 1,
      )
      self.finish(
        id,
        "Array[\{child.native_type}]",
        "Array<\{child.frontend_type}>",
        "  match value { Array(items) => items.mapi((index, item) => orbit_contract_decode_\{child.id}(item, path + \"[\" + index.to_string() + \"]\")); _ => orbit_contract_fail(path) }",
        "  Json::array(value.mapi((index, item) => orbit_contract_encode_\{child.id}(item, path + \"[\" + index.to_string() + \"]\")))",
      )
    }
    "object" => self.object_type(fields, path, depth, id, name)
    _ => contract_error(path, "unsupported type: " + kind)
  }
}

///|
fn contract_symbol(name : String) -> String {
  String::from_array(
    name
    .to_array()
    .map(char => {
      let code = char.to_int()
      if (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        (code >= 48 && code <= 57) {
        char
      } else {
        '_'
      }
    }),
  )
}

///|
fn contract_type_name(value : String) -> String raise BindingContractError {
  let chars = value.to_array()
  let result = []
  let mut upper = true
  for char in chars {
    let code = char.to_int()
    if (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      (code >= 48 && code <= 57) {
      if upper && code >= 97 && code <= 122 {
        result.push((code - 32).unsafe_to_char())
      } else {
        result.push(char)
      }
      upper = false
    } else {
      upper = true
    }
  }
  let name = String::from_array(result)
  if name.is_empty() || !contract_identifier(name, true) {
    contract_error("enum", "value cannot become a MoonBit variant")
  }
  name
}

///|
fn contract_registration(
  name : String,
  request : ContractType,
  response : ContractType,
) -> String {
  let symbol = contract_symbol(name)
  let command = contract_quote(name)
  let output = []
  for asynchronous in [false, true] {
    let async_prefix = if asynchronous { "async " } else { "" }
    let register_prefix = if asynchronous {
      "register_async"
    } else {
      "register"
    }
    let function_name = "\{register_prefix}_\{symbol}"
    output.push(
      "///|\npub fn \{function_name}(registry : @ipc.CommandRegistry, handler : \{async_prefix}(\{request.native_type}) -> Result[\{response.native_type}, @ipc.CommandFailure]) -> Unit raise @ipc.IpcError {\n  \{function_name}_context(registry, \{async_prefix}fn(_, request) { handler(request) })\n}\n",
    )
    output.push(
      "///|\npub fn \{function_name}_context(registry : @ipc.CommandRegistry, handler : \{async_prefix}(@ipc.InvocationContext, \{request.native_type}) -> Result[\{response.native_type}, @ipc.CommandFailure]) -> Unit raise @ipc.IpcError {\n  registry.\{register_prefix}_context_json(@ipc.CommandName::new(\{command}), \{async_prefix}fn(context, payload) {\n    let request = orbit_contract_decode_\{request.id}(payload, \"request\") catch { OrbitContractError(message) => return Err(@ipc.CommandFailure::new(code=\"invalid_payload\", message=message)) }\n    match handler(context, request) {\n      Err(error) => Err(error)\n      Ok(response) => {\n        let result = orbit_contract_encode_\{response.id}(response, \"response\")\n        Ok(result)\n      }\n    }\n  })\n}\n",
    )
  }
  output.join("\n")
}

///|
fn compile_contract(
  source : String,
) -> CompiledContract raise BindingContractError {
  match @strict_json.parse(source) {
    Err(_) =>
      contract_error("$", "contract must be strict JSON without duplicate keys")
    Ok(_) => ()
  }
  let schema = @json.parse(source) catch {
    _ => contract_error("$", "invalid JSON")
  }
  let root = contract_object(schema, "$")
  contract_keys(root, ["schema_version", "types", "commands", "events"], "$")
  let version = contract_object(
    contract_required(root, "schema_version", "$"),
    "$.schema_version",
  )
  contract_keys(version, ["orbit", "contract"], "$.schema_version")
  if version.get("orbit") != Some(Json::string(CONTRACT_ORBIT_VERSION)) {
    contract_error(
      "$.schema_version.orbit", "must match the Orbit release version",
    )
  }
  match version.get("contract") {
    Some(Number(value, ..)) if value >= 1.0 &&
      value.to_int().to_double() == value => ()
    _ =>
      contract_error("$.schema_version.contract", "must be a positive integer")
  }
  let definitions = contract_object(
    contract_required(root, "types", "$"),
    "types",
  )
  let compiler = ContractCompiler::{
    definitions,
    resolved: Map([]),
    resolving: Map([]),
    native: [],
    frontend: [],
    next_id: 0,
  }
  let reserved = [
    "CommandMap", "EventMap", "CommandDefinition", "InvokeOptions", "ListenOptions",
    "Unlisten", "OrbitEvent", "OrbitIpcError", "OrbitBridge", "ClientOptions", "CommandArguments",
    "OrbitClient",
  ]
  for name in contract_names(definitions) {
    if !contract_identifier(name, true) ||
      reserved.contains(name) ||
      name.has_prefix("Contract") {
      contract_error(
        "types." + name,
        "type name must be a unique non-reserved PascalCase identifier",
      )
    }
    ignore(compiler.named(name, 0))
  }
  let commands = contract_object(
    contract_required(root, "commands", "$"),
    "commands",
  )
  let compiled_commands = Map([])
  let registrations = []
  let symbols : Map[String, Bool] = Map([])
  for name in contract_names(commands) {
    ignore(@ipc.CommandName::new(name)) catch {
      _ => contract_error("commands." + name, "invalid command name")
    }
    let entry = contract_object(commands[name], "commands." + name)
    contract_keys(entry, ["request", "response"], "commands." + name)
    let request = compiler.compile(
      contract_required(entry, "request", name),
      name + ".request",
      0,
    )
    let response = compiler.compile(
      contract_required(entry, "response", name),
      name + ".response",
      0,
    )
    let symbol = contract_symbol(name)
    for
      function_name in [
        "register_\{symbol}",
        "register_\{symbol}_context",
        "register_async_\{symbol}",
        "register_async_\{symbol}_context",
      ] {
      if symbols.contains(function_name) {
        contract_error(
          name, "generated registration function name collides with another command",
        )
      }
      symbols[function_name] = true
    }
    compiled_commands[name] = (request, response)
    registrations.push(contract_registration(name, request, response))
  }
  let events = match root.get("events") {
    Some(events) => contract_object(events, "events")
    None => Map([])
  }
  let compiled_events = Map([])
  for name in contract_names(events) {
    if name.is_empty() ||
      name.length() > 128 ||
      name.to_array().any(char => char.to_int() < 32 || char.to_int() == 127) {
      contract_error("events." + name, "invalid event name")
    }
    let node = compiler.compile(events[name], "events." + name, 0)
    let function_name = "event_" + contract_symbol(name)
    if symbols.contains(function_name) {
      contract_error(
        name, "generated event function name collides with another event",
      )
    }
    symbols[function_name] = true
    compiled_events[name] = node
    registrations.push(
      "///|\npub fn \{function_name}(payload : \{node.native_type}, target? : @event.EventTarget = @event.Any, source? : @event.EventTarget = @event.Application) -> @event.EventEnvelope {\n  let payload = orbit_contract_encode_\{node.id}(payload, \"event\")\n  let name = @event.EventName::new(\{contract_quote(name)}) catch { _ => abort(\"generated Orbit event name is invalid\") }\n  @event.EventEnvelope::new(name~, payload~, target~, source~)\n}\n",
    )
  }
  let header = "// Generated by orbit-build. DO NOT EDIT.\n\n///|\npub(all) suberror OrbitContractError { OrbitContractError(String) }\n\n///|\nfn[T] orbit_contract_fail(path : String) -> T raise OrbitContractError { raise OrbitContractError(\"invalid value at \" + path) }\n"
  {
    schema,
    native: header +
    compiler.native.join("\n") +
    "\n" +
    registrations.join("\n"),
    frontend: compiler.frontend.join("\n") + "\n",
    commands: compiled_commands,
    events: compiled_events,
  }
}

///|
fn ContractCompiler::object_type(
  self : ContractCompiler,
  fields : Map[String, Json],
  path : String,
  depth : Int,
  id : Int,
  name : String?,
) -> ContractType raise BindingContractError {
  contract_keys(
    fields,
    ["type", "properties", "required", "additionalProperties", "description"],
    path,
  )
  if !fields.contains("properties") {
    if fields.contains("required") {
      contract_error(path, "required needs properties")
    }
    let child = self.compile(
      contract_required(fields, "additionalProperties", path),
      path + ".additionalProperties",
      depth + 1,
    )
    return self.finish(
      id,
      "Map[String, \{child.native_type}]",
      "Record<string, \{child.frontend_type}>",
      "  guard value is Object(items) else { orbit_contract_fail(path) }\n  let result = Map([])\n  for key, item in items { result[key] = orbit_contract_decode_\{child.id}(item, path + \".\" + key) }\n  result",
      "  let result = Map([])\n  for key, item in value { result[key] = orbit_contract_encode_\{child.id}(item, path + \".\" + key) }\n  Json::object(result)",
    )
  }
  if fields.get("additionalProperties") != Some(false) {
    contract_error(path, "record types require additionalProperties: false")
  }
  let properties = contract_object(
    contract_required(fields, "properties", path),
    path + ".properties",
  )
  if properties.is_empty() {
    contract_error(
      path, "empty records are not supported; use type: null for an empty request",
    )
  }
  let required = match fields.get("required") {
    None => []
    Some(Array(values)) =>
      values.map(value => {
        match value {
          String(name) => name
          _ => contract_error(path, "required must contain property names")
        }
      })
    _ => contract_error(path, "required must be an array")
  }
  let seen : Map[String, Bool] = Map([])
  for field in required {
    if !properties.contains(field) || seen.contains(field) {
      contract_error(path, "required contains an unknown or duplicate property")
    }
    seen[field] = true
  }
  let native_type = name.unwrap_or("OrbitContract\{id}")
  let native_fields = []
  let frontend_fields = []
  let decode_fields = []
  let encode_fields = []
  let property_names = contract_names(properties)
  for field in property_names {
    if !contract_identifier(field, false) {
      contract_error(
        path + "." + field,
        "property must be a non-keyword MoonBit field identifier",
      )
    }
    let child = self.compile(properties[field], path + "." + field, depth + 1)
    let quoted = contract_quote(field)
    let child_path = "path + \".\" + \{quoted}"
    if required.contains(field) {
      native_fields.push("  \{field} : \{child.native_type}")
      frontend_fields.push("\{quoted}: \{child.frontend_type}")
      decode_fields.push(
        "    \{field}: orbit_contract_decode_\{child.id}(match items.get(\{quoted}) { Some(item) => item; None => orbit_contract_fail(\{child_path}) }, \{child_path}),",
      )
      encode_fields.push(
        "  result[\{quoted}] = orbit_contract_encode_\{child.id}(value.\{field}, \{child_path})",
      )
    } else {
      native_fields.push("  \{field} : \{child.native_type}?")
      frontend_fields.push("\{quoted}?: \{child.frontend_type}")
      decode_fields.push(
        "    \{field}: match items.get(\{quoted}) { Some(item) => Some(orbit_contract_decode_\{child.id}(item, \{child_path})); None => None },",
      )
      encode_fields.push(
        "  match value.\{field} { Some(item) => result[\{quoted}] = orbit_contract_encode_\{child.id}(item, \{child_path}); None => () }",
      )
    }
  }
  self.native.push(
    "///|\npub(all) struct \{native_type} {\n\{native_fields.join("\n")}\n} derive(Debug)\n",
  )
  let keys = Json::array(property_names.map(Json::string)).stringify()
  self.finish(
    id,
    native_type,
    "{ \{frontend_fields.join("; ")} }",
    "  guard value is Object(items) else { orbit_contract_fail(path) }\n  for key, _ in items { if !\{keys}.contains(key) { orbit_contract_fail(path + \".\" + key) } }\n  {\n\{decode_fields.join("\n")}\n  }",
    "  let result : Map[String, Json] = Map([])\n\{encode_fields.join("\n")}\n  Json::object(result)",
  )
}


