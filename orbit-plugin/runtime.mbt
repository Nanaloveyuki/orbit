///|
pub(all) struct PluginDeclaration {
  id : String
  library : String
  sidecar : PluginSidecarManifest
  permissions : Array[String]
} derive(Eq, Debug)

///|
pub fn PluginDeclaration::new(
  id~ : String,
  library~ : String,
  sidecar~ : PluginSidecarManifest,
  permissions? : Array[String] = [],
) -> PluginDeclaration {
  { id, library, sidecar, permissions }
}

///|
pub(all) enum PluginRuntimeError {
  DuplicatePlugin(String)
  IncompatibleSidecar(String)
  IdentityMismatch(String, String)
  SidecarMismatch(String)
  MissingPermission(String, String)
  InvalidDevelopmentDirectory
  LoadFailure(String, PluginError)
  RegistrationFailure(String)
} derive(Eq, Debug)

///|
/// Owns loaded plugin libraries for one desktop process. Calling `shutdown`
/// always destroys plugin instances before their libraries are closed.
pub struct PluginRuntime {
  priv libraries : Array[PluginLibrary]
}

///|
pub fn PluginRuntime::new() -> PluginRuntime {
  { libraries: [] }
}

///|
fn path_join(root : String, relative : String) -> String {
  if root.is_empty() {
    relative
  } else if root.has_suffix("/") || root.has_suffix("\\") {
    root + relative
  } else {
    root + "/" + relative
  }
}

///|
fn declared_twice(declarations : Array[PluginDeclaration]) -> String? {
  let seen : Map[String, Bool] = Map([])
  for declaration in declarations {
    if declaration.id.is_empty() || seen.contains(declaration.id) {
      return Some(declaration.id)
    }
    seen[declaration.id] = true
  }
  None
}

///|
fn policy_for(declaration : PluginDeclaration) -> PluginPolicy {
  let policy = PluginPolicy::new()
  for permission in declaration.permissions {
    policy.grant(permission)
  }
  policy
}

///|
pub fn PluginRuntime::start(
  self : PluginRuntime,
  declarations : Array[PluginDeclaration],
  development_directory? : String? = None,
) -> Result[Unit, PluginRuntimeError] {
  self.shutdown()
  match development_directory {
    Some(directory) if directory.trim().is_empty() =>
      return Err(InvalidDevelopmentDirectory)
    _ => ()
  }
  match declared_twice(declarations) {
    Some(id) => return Err(DuplicatePlugin(id))
    None => ()
  }
  for declaration in declarations {
    if declaration.sidecar.schema_version != 2 ||
      declaration.sidecar.abi_version != 1 {
      self.shutdown()
      return Err(IncompatibleSidecar(declaration.id))
    }
    let path = match development_directory {
      Some(directory) => path_join(directory, declaration.library)
      None => declaration.library
    }
    let library = match load(path) {
      Ok(library) => library
      Err(error) => {
        self.shutdown()
        return Err(LoadFailure(declaration.id, error))
      }
    }
    let manifest = library.manifest()
    if manifest.id != declaration.id {
      library.close()
      self.shutdown()
      return Err(IdentityMismatch(declaration.id, manifest.id))
    }
    if !sidecar_matches_manifest(declaration.sidecar, manifest) {
      library.close()
      self.shutdown()
      return Err(SidecarMismatch(declaration.id))
    }
    for permission in manifest.permissions {
      if !declaration.permissions.contains(permission) {
        library.close()
        self.shutdown()
        return Err(MissingPermission(declaration.id, permission))
      }
    }
    match library.activate(policy_for(declaration)) {
      Ok(_) => self.libraries.push(library)
      Err(error) => {
        library.close()
        self.shutdown()
        return Err(LoadFailure(declaration.id, error))
      }
    }
  }
  Ok(())
}

///|
pub fn PluginRuntime::shutdown(self : PluginRuntime) -> Unit {
  for library in self.libraries {
    library.close()
  }
  self.libraries.clear()
}

///|
pub fn plugin_command_name(
  plugin_id : String,
  command : String,
) -> @ipc.CommandName raise @ipc.IpcError {
  @ipc.CommandName::new("plugin:\{plugin_id}/\{command}")
}

///|
fn PluginRuntime::invoke_json(
  self : PluginRuntime,
  plugin_id : String,
  command : String,
  payload : Json,
) -> Result[Json, @ipc.CommandFailure] {
  for library in self.libraries {
    if library.manifest().id == plugin_id {
      let request = @utf8.encode(payload.stringify(), bom=false)
      return match library.invoke(command, request) {
        Ok(response) => {
          let text = @utf8.decode(response) catch {
            _ =>
              return Err(
                @ipc.CommandFailure::new(
                  code="plugin_invalid_response",
                  message="plugin returned non-UTF-8 response: \{plugin_id}",
                ),
              )
          }
          match @strict_json.parse(text) {
            Ok(_) => {
              let response = @json.parse(text) catch {
                _ =>
                  return Err(
                    @ipc.CommandFailure::new(
                      code="plugin_invalid_response",
                      message="plugin response could not be decoded: \{plugin_id}",
                    ),
                  )
              }
              Ok(response)
            }
            Err(_) =>
              Err(
                @ipc.CommandFailure::new(
                  code="plugin_invalid_response",
                  message="plugin returned malformed JSON: \{plugin_id}",
                ),
              )
          }
        }
        Err(_) =>
          Err(
            @ipc.CommandFailure::new(
              code="plugin_command_failed",
              message="plugin command failed: \{plugin_id}/\{command}",
            ),
          )
      }
    }
  }
  Err(
    @ipc.CommandFailure::new(
      code="plugin_unavailable",
      message="plugin is not active: \{plugin_id}",
    ),
  )
}

///|
pub fn PluginRuntime::register_ipc(
  self : PluginRuntime,
  registry : @ipc.CommandRegistry,
) -> Result[Unit, PluginRuntimeError] {
  for library in self.libraries {
    let manifest = library.manifest()
    for command in manifest.commands {
      let name = plugin_command_name(manifest.id, command) catch {
        _ => return Err(RegistrationFailure("invalid plugin command"))
      }
      registry.register_json(name, payload => {
        self.invoke_json(manifest.id, command, payload)
      }) catch {
        _ =>
          return Err(
            RegistrationFailure(
              "duplicate or invalid plugin command: \{manifest.id}/\{command}",
            ),
          )
      }
    }
  }
  Ok(())
}
