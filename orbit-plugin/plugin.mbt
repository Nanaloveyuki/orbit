///|
pub(all) struct PluginManifest {
  id : String
  name : String
  version : String
  commands : Array[String]
  permissions : Array[String]
} derive(Eq, Debug)

///|
pub(all) enum PluginError {
  LoadFailed
  MissingSymbol(String)
  InvalidAbi
  InvalidManifest(String)
  PermissionDenied(String)
  CommandDenied(String)
  ActivationFailed
  InvocationFailed
} derive(Eq, Debug)

///|
/// A loaded plugin library whose manifest has passed strict JSON validation.
///
/// This discovery API deliberately does not create or invoke a plugin instance.
pub struct PluginLibrary {
  priv library : @dynlib.Library
  priv manifest : PluginManifest
  priv abi : @abi.Plugin
  priv mut instance : @abi.PluginInstance?
}

///|
/// Explicit grants for a plugin's declared permissions.
pub struct PluginPolicy {
  priv granted : Map[String, Bool]
}

///|
pub fn PluginPolicy::new() -> PluginPolicy {
  { granted: Map([]) }
}

///|
pub fn PluginPolicy::grant(self : PluginPolicy, permission : String) -> Unit {
  if !permission.is_empty() {
    self.granted[permission] = true
  }
}

///|
pub fn PluginPolicy::allows(self : PluginPolicy, permission : String) -> Bool {
  self.granted.contains(permission)
}

///|
pub fn PluginLibrary::manifest(self : PluginLibrary) -> PluginManifest {
  self.manifest
}

///|
pub fn PluginLibrary::close(self : PluginLibrary) -> Unit {
  match self.instance {
    Some(instance) => instance.destroy()
    None => ()
  }
  self.instance = None
  ignore(self.library.close())
}

///|
fn manifest_limits() -> @strict_json.JsonLimits {
  @strict_json.JsonLimits::new(
    max_input_chars=1_048_576,
    max_depth=16,
    max_string_chars=131_072,
    max_array_items=4_096,
    max_object_members=128,
  )
}

///|
fn object_field(
  members : Array[(String, @strict_json.Json)],
  key : String,
) -> @strict_json.Json? {
  for entry in members {
    match entry {
      (name, value) => if name == key { return Some(value) }
    }
  }
  None
}

///|
fn string_field(
  members : Array[(String, @strict_json.Json)],
  key : String,
) -> String? {
  match object_field(members, key) {
    Some(Text(value~)) => Some(value)
    _ => None
  }
}

///|
fn string_array(
  members : Array[(String, @strict_json.Json)],
  key : String,
) -> Array[String]? {
  match object_field(members, key) {
    Some(Array(items~)) => {
      let values = []
      for item in items {
        match item {
          Text(value~) if !value.is_empty() => values.push(value)
          _ => return None
        }
      }
      Some(values)
    }
    _ => None
  }
}

///|
pub fn parse_manifest(source : String) -> Result[PluginManifest, PluginError] {
  match @strict_json.parse_with_limits(source, manifest_limits()) {
    Ok(Object(members~)) =>
      match
        (
          string_field(members, "id"),
          string_field(members, "name"),
          string_field(members, "version"),
          string_array(members, "commands"),
          string_array(members, "permissions"),
        ) {
        (Some(id), Some(name), Some(version), Some(commands), Some(permissions)) =>
          if !id.is_empty() && !name.is_empty() && !version.is_empty() {
            Ok({ id, name, version, commands, permissions })
          } else {
            Err(InvalidManifest("required manifest fields are invalid"))
          }
        _ => Err(InvalidManifest("required manifest fields are invalid"))
      }
    Ok(_) => Err(InvalidManifest("manifest root must be an object"))
    Err(_) => Err(InvalidManifest("manifest must be strict JSON"))
  }
}

///|
fn resolve(
  library : @dynlib.Library,
  name : String,
) -> Result[@dynlib.Symbol, PluginError] {
  match library.resolve(name) {
    Ok(symbol) => Ok(symbol)
    Err(_) => Err(MissingSymbol(name))
  }
}

///|
pub fn load(path : String) -> Result[PluginLibrary, PluginError] {
  let library = match @dynlib.load(path) {
    Ok(value) => value
    Err(_) => return Err(LoadFailed)
  }
  let version = resolve(library, "orbit_plugin_abi_version")
  let manifest = resolve(library, "orbit_plugin_manifest_json")
  let create = resolve(library, "orbit_plugin_create")
  let invoke = resolve(library, "orbit_plugin_invoke")
  let destroy = resolve(library, "orbit_plugin_destroy")
  match (version, manifest, create, invoke, destroy) {
    (Ok(version), Ok(manifest), Ok(create), Ok(invoke), Ok(destroy)) => {
      let abi = match
        @abi.PluginAddresses::from_symbols(
          version, manifest, create, invoke, destroy,
        ) {
        Ok(addresses) =>
          match @abi.Plugin::open(addresses) {
            Ok(value) => value
            Err(_) => {
              ignore(library.close())
              return Err(InvalidAbi)
            }
          }
        Err(_) => {
          ignore(library.close())
          return Err(InvalidAbi)
        }
      }
      match parse_manifest(abi.manifest_json()) {
        Ok(value) => Ok({ library, abi, manifest: value, instance: None })
        Err(error) => {
          ignore(library.close())
          Err(error)
        }
      }
    }
    _ => {
      ignore(library.close())
      Err(MissingSymbol("required Orbit plugin ABI v1 symbol"))
    }
  }
}

///|
fn permissions_allowed(
  manifest : PluginManifest,
  policy : PluginPolicy,
) -> String? {
  for permission in manifest.permissions {
    if !policy.allows(permission) {
      return Some(permission)
    }
  }
  None
}

///|
/// Creates the plugin instance after every manifest permission is granted.
pub fn PluginLibrary::activate(
  self : PluginLibrary,
  policy : PluginPolicy,
) -> Result[Unit, PluginError] {
  if self.instance is Some(_) {
    return Ok(())
  }
  match permissions_allowed(self.manifest, policy) {
    Some(permission) => Err(PermissionDenied(permission))
    None =>
      match self.abi.create() {
        Ok(instance) => {
          self.instance = Some(instance)
          Ok(())
        }
        Err(_) => Err(ActivationFailed)
      }
  }
}

///|
/// Invokes one manifest-declared command on an activated plugin instance.
pub fn PluginLibrary::invoke(
  self : PluginLibrary,
  command : String,
  request : Bytes,
) -> Result[Bytes, PluginError] {
  if !self.manifest.commands.contains(command) {
    return Err(CommandDenied(command))
  }
  match self.instance {
    Some(instance) =>
      match instance.invoke(command, request) {
        Ok(response) => Ok(response)
        Err(_) => Err(InvocationFailed)
      }
    None => Err(ActivationFailed)
  }
}
