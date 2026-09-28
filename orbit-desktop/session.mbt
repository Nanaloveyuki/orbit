///|
pub struct DesktopSessionExtension {
  priv keep_awake : Ref[@proton_keepawake.Guard?]
}

///|
pub fn DesktopSessionExtension::new() -> DesktopSessionExtension {
  { keep_awake: Ref(None), }
}

///|
pub fn DesktopSessionExtension::as_extension(
  self : DesktopSessionExtension,
) -> &@core.DesktopExtension {
  self as &@core.DesktopExtension
}

///|
fn release_keep_awake(extension : DesktopSessionExtension) -> Unit {
  match extension.keep_awake.val {
    Some(active) => active.release() catch { _ => () }
    None => ()
  }
  extension.keep_awake.val = None
}

///|
fn auto_launch(
  name : String,
  path : String,
  enabled : Bool,
) -> Result[Bool, @ipc.CommandFailure] {
  if !@proton_auto_launch.is_supported() {
    return Err(unavailable("auto launch is unavailable"))
  }
  match @proton_auto_launch.new(name, path~) {
    Err(_) => Err(failed("auto launch configuration failed"))
    Ok(launcher) => {
      let result = if enabled { launcher.enable() } else { launcher.disable() }
      match result {
        Ok(_) => Ok(enabled)
        Err(_) => Err(failed("auto launch update failed"))
      }
    }
  }
}

///|
fn acquire_keep_awake(
  extension : DesktopSessionExtension,
  scope : @proton_keepawake.Scope,
  reason : String?,
) -> Result[Json, @ipc.CommandFailure] {
  match reason {
    Some(reason) =>
      match bounded_text(reason) {
        Ok(_) => ()
        Err(failure) => return Err(failure)
      }
    None => ()
  }
  release_keep_awake(extension)
  try {
    let active = @proton_keepawake.acquire(reason?, scope~)
    extension.keep_awake.val = Some(active)
    Ok({ "active": active.active(), "scope": scope_name(active.scope()) })
  } catch {
    _ => Err(unavailable("keep awake is unavailable"))
  }
}

///|
impl DesktopExtension for DesktopSessionExtension with fn identifier(self) {
  ignore(self)
  "orbit.desktop.session"
}

///|
impl DesktopExtension for DesktopSessionExtension with fn commands(self) {
  [
    command("orbit.safe_storage.available", fn(_ui, _payload) {
      Ok({ "available": @proton_safe_storage.is_available() })
    }),
    command("orbit.safe_storage.encrypt", fn(_ui, payload) {
      if !@proton_safe_storage.is_available() {
        return Err(unavailable("safe storage is unavailable"))
      }
      match string_field(payload, "text").bind(bounded_text) {
        Err(failure) => Err(failure)
        Ok(text) =>
          match @proton_safe_storage.encrypt_string(text) {
            Ok(value) => Ok({ "value": value })
            Err(_) => Err(failed("safe storage encryption failed"))
          }
      }
    }),
    command("orbit.safe_storage.decrypt", fn(_ui, payload) {
      if !@proton_safe_storage.is_available() {
        return Err(unavailable("safe storage is unavailable"))
      }
      match string_field(payload, "value").bind(bounded_text) {
        Err(failure) => Err(failure)
        Ok(value) =>
          match @proton_safe_storage.decrypt_string(value) {
            Ok(text) => Ok({ "text": text })
            Err(_) => Err(failed("safe storage decryption failed"))
          }
      }
    }),
    command("orbit.auto_launch.supported", fn(_ui, _payload) {
      Ok({ "supported": @proton_auto_launch.is_supported() })
    }),
    command("orbit.auto_launch.set", fn(_ui, payload) {
      if object_field(payload, "enabled") is None {
        return Err(invalid_payload())
      }
      match string_field(payload, "name").bind(safe_text) {
        Err(failure) => Err(failure)
        Ok(name) =>
          match string_field(payload, "path").bind(safe_text) {
            Err(failure) => Err(failure)
            Ok(path) =>
              match bool_field(payload, "enabled", false) {
                Err(failure) => Err(failure)
                Ok(enabled) =>
                  match auto_launch(name, path, enabled) {
                    Ok(enabled) => Ok({ "enabled": enabled })
                    Err(failure) => Err(failure)
                  }
              }
          }
      }
    }),
    command("orbit.keepawake.acquire", fn(_ui, payload) {
      match optional_string_field(payload, "scope") {
        Err(failure) => Err(failure)
        Ok(requested) =>
          match parse_scope(requested) {
            Err(failure) => Err(failure)
            Ok(scope) =>
              match optional_string_field(payload, "reason") {
                Err(failure) => Err(failure)
                Ok(reason) => acquire_keep_awake(self, scope, reason)
              }
          }
      }
    }),
    command("orbit.keepawake.release", fn(_ui, _payload) {
      let active = self.keep_awake.val is Some(_)
      release_keep_awake(self)
      Ok({ "released": active })
    }),
  ]
}

///|
impl DesktopExtension for DesktopSessionExtension with fn start(
  _self,
  _controller,
) {
  Ok(())
}

///|
impl DesktopExtension for DesktopSessionExtension with fn poll(
  _self,
  _controller,
) {
  Ok(())
}

///|
impl DesktopExtension for DesktopSessionExtension with fn window_suspended(
  _self,
  _label,
) {
  Ok(())
}

///|
impl DesktopExtension for DesktopSessionExtension with fn window_destroyed(
  _self,
  _label,
) {
  Ok(())
}

///|
impl DesktopExtension for DesktopSessionExtension with fn shutdown(self) {
  release_keep_awake(self)
  Ok(())
}
