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
/// Owns loaded plugin libraries for one desktop process. `shutdown` destroys
/// plugin instances before closing their libraries. A library whose executor
/// cannot be joined remains retained and the failure is returned.
pub struct PluginRuntime {
  priv libraries : Array[PluginLibrary]
  priv mut async_state : PluginAsyncState?
}

///|
pub fn PluginRuntime::new() -> PluginRuntime {
  { libraries: [], async_state: None }
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
fn PluginRuntime::cleanup_failure(
  self : PluginRuntime,
  fallback : PluginRuntimeError,
) -> PluginRuntimeError {
  match self.shutdown() {
    Err(error) => error
    Ok(_) => fallback
  }
}

///|
fn PluginRuntime::cleanup_library_failure(
  self : PluginRuntime,
  library : PluginLibrary,
  fallback : PluginRuntimeError,
) -> PluginRuntimeError {
  self.libraries.push(library)
  self.cleanup_failure(fallback)
}

///|
pub fn PluginRuntime::start(
  self : PluginRuntime,
  declarations : Array[PluginDeclaration],
  development_directory? : String? = None,
) -> Result[Unit, PluginRuntimeError] {
  match self.shutdown() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
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
      (
        declaration.sidecar.abi_version != 1 &&
        declaration.sidecar.abi_version != 2
      ) {
      return Err(self.cleanup_failure(IncompatibleSidecar(declaration.id)))
    }
    let path = match development_directory {
      Some(directory) => path_join(directory, declaration.library)
      None => declaration.library
    }
    let library = match load(path) {
      Ok(library) => library
      Err(error) =>
        return Err(self.cleanup_failure(LoadFailure(declaration.id, error)))
    }
    let manifest = library.manifest()
    let reported_abi = match library.abi_version() {
      @abi.AbiVersion::V1 => 1
      @abi.AbiVersion::V2 => 2
    }
    if declaration.sidecar.abi_version != reported_abi {
      return Err(
        self.cleanup_library_failure(
          library,
          IncompatibleSidecar(declaration.id),
        ),
      )
    }
    if manifest.id != declaration.id {
      return Err(
        self.cleanup_library_failure(
          library,
          IdentityMismatch(declaration.id, manifest.id),
        ),
      )
    }
    if !sidecar_matches_manifest(declaration.sidecar, manifest) {
      return Err(
        self.cleanup_library_failure(library, SidecarMismatch(declaration.id)),
      )
    }
    for permission in manifest.permissions {
      if !declaration.permissions.contains(permission) {
        return Err(
          self.cleanup_library_failure(
            library,
            MissingPermission(declaration.id, permission),
          ),
        )
      }
    }
    let wakeup_callback = self.async_state.map(state => state.wakeup_callback)
    match library.activate(policy_for(declaration), wakeup_callback?) {
      Ok(_) => self.libraries.push(library)
      Err(error) =>
        return Err(
          self.cleanup_library_failure(
            library,
            LoadFailure(declaration.id, error),
          ),
        )
    }
  }
  Ok(())
}

///|
pub fn PluginRuntime::shutdown(
  self : PluginRuntime,
) -> Result[Unit, PluginRuntimeError] {
  match self.async_state {
    Some(state) => state.cancel_all_host_requests()
    None => ()
  }
  let retained : Array[PluginLibrary] = []
  let mut failure : PluginRuntimeError? = None
  for library in self.libraries {
    match library.close() {
      Ok(_) => ()
      Err(error) => {
        retained.push(library)
        if failure is None {
          failure = Some(LoadFailure(library.manifest.id, error))
        }
      }
    }
  }
  self.libraries.clear()
  for library in retained {
    self.libraries.push(library)
  }
  match failure {
    Some(error) => Err(error)
    None => Ok(())
  }
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
      try {
        match library.abi_version() {
          V1 =>
            registry.register_json(name, payload => {
              self.invoke_json(manifest.id, command, payload)
            })
          V2 =>
            registry.register_async_json(name, async fn(payload) {
              self.invoke_json_async(manifest.id, command, payload)
            })
        }
      } catch {
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
