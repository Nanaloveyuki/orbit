///|
pub(all) struct PluginManifest {
  id : String
  name : String
  version : String
  commands : Array[String]
  permissions : Array[String]
} derive(Eq, Debug)

///|
/// A build-validated sidecar descriptor. JSON Schema values are retained as
/// ordinary inspectable JSON rather than becoming a second invocation ABI.
pub(all) struct PluginCommandDescriptor {
  name : String
  request_schema : Json
  response_schema : Json
} derive(Eq, Debug, FromJson)

///|
pub(all) struct PluginSidecarManifest {
  schema_version : Int
  abi_version : Int
  id : String
  name : String
  version : String
  platforms : Array[String]
  requested_permissions : Array[String]
  commands : Array[PluginCommandDescriptor]
} derive(Eq, Debug, FromJson)

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
  AsyncRuntimeRequired
  ExecutorFailed
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
  priv abi_version : @abi.AbiVersion
  priv mut executor : @abi.PluginExecutor?
  priv mut executor_ready : Bool
  priv mut executor_stopped : Bool
  priv mut executor_failed : Bool
  priv mut host_request_active : Bool
  priv executor_condition : @cond_var.Cond
  priv mut next_invocation_id : UInt64
  priv pending_invocations : Map[UInt64, PendingPluginInvocation]
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
fn PluginLibrary::abi_version(self : PluginLibrary) -> @abi.AbiVersion {
  self.abi_version
}

///|
pub fn PluginLibrary::close(self : PluginLibrary) -> Result[Unit, PluginError] {
  self.executor_ready = false
  self.executor_stopped = true
  self.host_request_active = false
  self.executor_condition.broadcast()
  for _, pending in self.pending_invocations {
    pending.result = Some(Err(ExecutorFailed))
    pending.condition.signal()
  }
  self.pending_invocations.clear()
  match self.executor {
    Some(executor) => {
      executor.begin_shutdown()
      match executor.join() {
        Ok(_) => self.executor = None
        Err(_) => return Err(ExecutorFailed)
      }
    }
    None => ()
  }
  match self.instance {
    Some(instance) => instance.destroy()
    None => ()
  }
  self.instance = None
  match self.library.close() {
    Ok(_) => Ok(())
    Err(_) => Err(LoadFailed)
  }
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
fn unique_nonempty(values : Array[String]) -> Bool {
  let seen : Map[String, Bool] = Map([])
  for value in values {
    if value.is_empty() || seen.contains(value) {
      return false
    }
    seen[value] = true
  }
  true
}

///|
fn valid_sidecar_manifest(sidecar : PluginSidecarManifest) -> Bool {
  if sidecar.schema_version != 2 ||
    (sidecar.abi_version != 1 && sidecar.abi_version != 2) ||
    sidecar.id.is_empty() ||
    sidecar.name.is_empty() ||
    sidecar.version.is_empty() ||
    sidecar.platforms.is_empty() ||
    sidecar.commands.is_empty() ||
    !unique_nonempty(sidecar.platforms) ||
    !unique_nonempty(sidecar.requested_permissions) {
    return false
  }
  let allowed_platforms = ["windows", "linux", "macos"]
  let commands : Map[String, Bool] = Map([])
  for command in sidecar.commands {
    if command.name.is_empty() || commands.contains(command.name) {
      return false
    }
    match (command.request_schema, command.response_schema) {
      (Object(_), Object(_)) => ()
      _ => return false
    }
    commands[command.name] = true
  }
  sidecar.platforms.all(platform => allowed_platforms.contains(platform))
}

///|
pub fn parse_sidecar_manifest(
  source : String,
) -> Result[PluginSidecarManifest, PluginError] {
  match @strict_json.parse_with_limits(source, manifest_limits()) {
    Ok(_) => ()
    Err(_) => return Err(InvalidManifest("sidecar must be strict JSON"))
  }
  let value = @json.parse(source) catch {
    _ => return Err(InvalidManifest("sidecar could not be decoded"))
  }
  let sidecar : PluginSidecarManifest = @json.from_json(value) catch {
    _ => return Err(InvalidManifest("sidecar fields are invalid"))
  }
  if valid_sidecar_manifest(sidecar) {
    Ok(sidecar)
  } else {
    Err(InvalidManifest("sidecar fields are invalid"))
  }
}

///|
pub fn sidecar_matches_manifest(
  sidecar : PluginSidecarManifest,
  manifest : PluginManifest,
) -> Bool {
  sidecar.id == manifest.id &&
  sidecar.name == manifest.name &&
  sidecar.version == manifest.version &&
  sidecar.requested_permissions == manifest.permissions &&
  sidecar.commands.map(command => command.name) == manifest.commands
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
        Ok(value) =>
          Ok({
            library,
            abi,
            manifest: value,
            instance: None,
            abi_version: abi.abi_version(),
            executor: None,
            executor_ready: false,
            executor_stopped: false,
            executor_failed: false,
            host_request_active: false,
            executor_condition: @cond_var.Cond(),
            next_invocation_id: 1UL,
            pending_invocations: Map([]),
          })
        Err(error) => {
          ignore(library.close())
          Err(error)
        }
      }
    }
    _ => {
      ignore(library.close())
      Err(MissingSymbol("required Orbit plugin ABI symbol"))
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
  wakeup_callback? : FuncRef[() -> Unit],
) -> Result[Unit, PluginError] {
  if self.instance is Some(_) || self.executor is Some(_) {
    return Ok(())
  }
  match permissions_allowed(self.manifest, policy) {
    Some(permission) => Err(PermissionDenied(permission))
    None =>
      match self.abi_version {
        @abi.AbiVersion::V1 =>
          match self.abi.create() {
            Ok(instance) => {
              self.instance = Some(instance)
              Ok(())
            }
            Err(_) => Err(ActivationFailed)
          }
        @abi.AbiVersion::V2 =>
          match wakeup_callback {
            None => Err(AsyncRuntimeRequired)
            Some(wakeup_callback) =>
              match self.abi.start_executor(wakeup_callback) {
                Ok(executor) => {
                  self.executor = Some(executor)
                  Ok(())
                }
                Err(_) => Err(ExecutorFailed)
              }
          }
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
  if self.abi_version == @abi.AbiVersion::V2 {
    return Err(AsyncRuntimeRequired)
  }
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
