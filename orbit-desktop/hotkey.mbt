///|
pub struct DesktopHotkeyExtension {
  priv events : @event.EventRouter?
  priv manager : Ref[@proton_global_hotkey.GlobalHotkeyManager?]
}

///|
pub fn DesktopHotkeyExtension::new(
  events? : @event.EventRouter? = None,
) -> DesktopHotkeyExtension {
  { events, manager: Ref(None), }
}

///|
pub fn DesktopHotkeyExtension::as_extension(
  self : DesktopHotkeyExtension,
) -> &@core.DesktopExtension {
  self as &@core.DesktopExtension
}

///|
fn register_hotkey(
  extension : DesktopHotkeyExtension,
  accelerator : String,
  enabled : Bool,
) -> Result[Json, @ipc.CommandFailure] {
  let manager = match extension.manager.val {
    Some(manager) => manager
    None => return Err(unavailable("global hotkeys are unavailable"))
  }
  let result = if enabled {
    manager.register(accelerator)
  } else {
    manager.unregister(accelerator)
  }
  match result {
    Ok(changed) => Ok({ "accelerator": accelerator, "changed": changed })
    Err(_) => Err(failed("global hotkey registration failed"))
  }
}

///|
impl DesktopExtension for DesktopHotkeyExtension with fn identifier(self) {
  ignore(self)
  "orbit.desktop.hotkey"
}

///|
impl DesktopExtension for DesktopHotkeyExtension with fn commands(self) {
  [
    command("orbit.hotkey.supported", fn(_ui, _payload) {
      Ok({ "supported": @proton_global_hotkey.is_supported() })
    }),
    command("orbit.hotkey.register", fn(_ui, payload) {
      match string_field(payload, "accelerator").bind(bounded_text) {
        Err(failure) => Err(failure)
        Ok(accelerator) =>
          match bool_field(payload, "enabled", true) {
            Err(failure) => Err(failure)
            Ok(enabled) => register_hotkey(self, accelerator, enabled)
          }
      }
    }),
    command("orbit.hotkey.list", fn(_ui, _payload) {
      match self.manager.val {
        Some(manager) => Ok({ "accelerators": manager.list() })
        None => Err(unavailable("global hotkeys are unavailable"))
      }
    }),
  ]
}

///|
impl DesktopExtension for DesktopHotkeyExtension with fn start(
  self,
  _controller,
) {
  if !@proton_global_hotkey.is_supported() {
    return Err("global hotkeys are unavailable on this platform")
  }
  match @proton_global_hotkey.create() {
    Ok(manager) => {
      self.manager.val = Some(manager)
      Ok(())
    }
    Err(_) => Err("global hotkey backend failed to start")
  }
}

///|
impl DesktopExtension for DesktopHotkeyExtension with fn poll(self, _controller) {
  let manager = match self.manager.val {
    Some(manager) => manager
    None => return Ok(())
  }
  let router = match self.events {
    Some(router) => router
    None => {
      ignore(manager.drain_triggered())
      return Ok(())
    }
  }
  let name = @event.EventName::new("orbit.hotkey.triggered") catch {
    _ => return Err("global hotkey event name is invalid")
  }
  for accelerator in manager.drain_triggered() {
    let event = @event.EventEnvelope::new(
      name~,
      payload={ "accelerator": accelerator },
      source=@event.Application,
      target=@event.Application,
    )
    match router.emit(event) {
      Ok(_) => ()
      Err(_) => return Err("global hotkey event delivery failed")
    }
  }
  Ok(())
}

///|
impl DesktopExtension for DesktopHotkeyExtension with fn window_suspended(
  _self,
  _label,
) {
  Ok(())
}

///|
impl DesktopExtension for DesktopHotkeyExtension with fn window_destroyed(
  _self,
  _label,
) {
  Ok(())
}

///|
impl DesktopExtension for DesktopHotkeyExtension with fn shutdown(self) {
  match self.manager.val {
    Some(manager) => manager.destroy()
    None => ()
  }
  self.manager.val = None
  Ok(())
}
