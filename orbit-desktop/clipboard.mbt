///|
pub struct DesktopClipboardExtension {}

///|
pub fn DesktopClipboardExtension::new() -> DesktopClipboardExtension {
  DesktopClipboardExtension::{ }
}

///|
pub fn DesktopClipboardExtension::as_extension(
  self : DesktopClipboardExtension,
) -> &@core.DesktopExtension {
  self as &@core.DesktopExtension
}

///|
impl DesktopExtension for DesktopClipboardExtension with fn identifier(self) {
  ignore(self)
  "orbit.desktop.clipboard"
}

///|
impl DesktopExtension for DesktopClipboardExtension with fn commands(_self) {
  [
    command("orbit.clipboard.supported", fn(_ui, _payload) {
      Ok({ "supported": @proton_clipboard.is_supported() })
    }),
    command("orbit.clipboard.read_text", fn(_ui, _payload) {
      if !@proton_clipboard.is_supported() {
        return Err(unavailable("clipboard is unavailable"))
      }
      match @proton_clipboard.read_text() {
        Ok(Some(text)) =>
          match bounded_text(text) {
            Ok(text) => Ok({ "text": text })
            Err(failure) => Err(failure)
          }
        Ok(None) => Ok({ "text": Json::null() })
        Err(_) => Err(failed("clipboard read failed"))
      }
    }),
    command("orbit.clipboard.write_text", fn(_ui, payload) {
      if !@proton_clipboard.is_supported() {
        return Err(unavailable("clipboard is unavailable"))
      }
      match string_field(payload, "text").bind(bounded_text) {
        Err(failure) => Err(failure)
        Ok(text) =>
          match @proton_clipboard.write_text(text) {
            Ok(_) => Ok({ "written": true })
            Err(_) => Err(failed("clipboard write failed"))
          }
      }
    }),
  ]
}

///|
impl DesktopExtension for DesktopClipboardExtension with fn start(
  _self,
  _controller,
) {
  Ok(())
}

///|
impl DesktopExtension for DesktopClipboardExtension with fn poll(
  _self,
  _controller,
) {
  Ok(())
}

///|
impl DesktopExtension for DesktopClipboardExtension with fn window_suspended(
  _self,
  _label,
) {
  Ok(())
}

///|
impl DesktopExtension for DesktopClipboardExtension with fn window_destroyed(
  _self,
  _label,
) {
  Ok(())
}

///|
impl DesktopExtension for DesktopClipboardExtension with fn shutdown(_self) {
  Ok(())
}
