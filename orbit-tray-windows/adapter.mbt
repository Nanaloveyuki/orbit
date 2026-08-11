///|
using @core {trait DesktopExtension}

///|
type TrayCallback = (
  @core.DesktopController,
  @tray.TrayController,
  @tray.TrayItemId,
  @tray.TrayEvent,
) -> Unit

///|
struct MountedTrayItem {
  item : @tray.TrayItem
  native : NativeTrayItem
  slot : Int
}

///|
pub struct WindowsTrayExtension {
  priv configured_items : Array[@tray.TrayItem]
  priv items : Ref[Array[MountedTrayItem]]
  priv callback : TrayCallback
  priv controller : Ref[@core.DesktopController?]
  priv tray_controller : Ref[@tray.TrayController?]
  priv alive : Ref[Bool]
}

///|
pub fn WindowsTrayExtension::new(
  items : Array[@tray.TrayItem],
  callback : TrayCallback,
) -> WindowsTrayExtension {
  {
    configured_items: items,
    items: Ref([]),
    callback,
    controller: Ref(None),
    tray_controller: Ref(None),
    alive: Ref(false),
  }
}

///|
pub fn WindowsTrayExtension::as_extension(
  self : WindowsTrayExtension,
) -> &@core.DesktopExtension {
  self as &@core.DesktopExtension
}

///|
fn tray_image(item : @tray.TrayItem) -> Result[@image.Image, String] {
  Ok(@image.decode_png(item.icon().png())) catch {
    _ => Err("tray icon must be a valid PNG")
  }
}

///|
fn create_native_item(item : @tray.TrayItem) -> Result[MountedTrayItem, String] {
  let image = match tray_image(item) {
    Ok(image) => image
    Err(reason) => return Err(reason)
  }
  let status = Ref(0)
  let native = native_create_item(
    image.pixels,
    image.width,
    image.height,
    @utf8.encode(item.tooltip(), bom=false),
    item.visible(),
    status,
  )
  if status.val != 0 {
    return Err("Windows tray item creation failed")
  }
  Ok({ item, native, slot: native_item_slot(native) })
}

///|
fn WindowsTrayExtension::replace(
  self : WindowsTrayExtension,
  item : @tray.TrayItem,
) -> Result[Unit, @tray.TrayError] {
  if !self.alive.val {
    return Err(Unavailable)
  }
  for index in 0..<self.items.val.length() {
    let mounted = self.items.val[index]
    if mounted.item.id() == item.id() {
      let image = match tray_image(item) {
        Ok(image) => image
        Err(_) => return Err(Unavailable)
      }
      let status = Ref(0)
      native_replace_item(
        mounted.native,
        image.pixels,
        image.width,
        image.height,
        @utf8.encode(item.tooltip(), bom=false),
        item.visible(),
        status,
      )
      if status.val != 0 {
        return Err(Unavailable)
      }
      self.items.val[index] = { ..mounted, item, }
      return Ok(())
    }
  }
  Err(Unavailable)
}

///|
fn WindowsTrayExtension::open_menu(
  self : WindowsTrayExtension,
  id : @tray.TrayItemId,
) -> Result[Unit, @tray.TrayError] {
  if !self.alive.val {
    return Err(Unavailable)
  }
  for mounted in self.items.val {
    if mounted.item.id() == id {
      let status = Ref(0)
      native_open_menu(mounted.native, encode_menu(mounted.item.menu()), status)
      return if status.val == 0 { Ok(()) } else { Err(Unavailable) }
    }
  }
  Err(Unavailable)
}

///|
fn append_u16(output : Array[Byte], value : Int) -> Unit {
  output.push((value & 0xFF).to_byte())
  output.push(((value >> 8) & 0xFF).to_byte())
}

///|
fn append_bytes(output : Array[Byte], bytes : Bytes) -> Unit {
  for byte in bytes {
    output.push(byte)
  }
}

///|
fn encode_menu_entries(
  entries : Array[@tray.TrayMenuEntry],
  output : Array[Byte],
  commands : Array[@tray.TrayCommandId],
) -> Unit {
  for entry in entries {
    match entry {
      Command(id, label, enabled, checked) => {
        let label = @utf8.encode(label, bom=false)
        output.push(b'\x01')
        append_u16(output, label.length())
        append_bytes(output, label)
        output.push(if enabled { b'\x01' } else { b'\x00' })
        output.push(if checked { b'\x01' } else { b'\x00' })
        append_u16(output, commands.length())
        commands.push(id)
      }
      Separator => output.push(b'\x02')
      Submenu(label, children) => {
        let child : Array[Byte] = []
        encode_menu_entries(children, child, commands)
        let label = @utf8.encode(label, bom=false)
        output.push(b'\x03')
        append_u16(output, label.length())
        append_bytes(output, label)
        append_u16(output, child.length())
        append_bytes(output, Bytes::from_array(child))
      }
    }
  }
}

///|
fn encode_menu(entries : Array[@tray.TrayMenuEntry]) -> Bytes {
  let output : Array[Byte] = []
  let commands : Array[@tray.TrayCommandId] = []
  encode_menu_entries(entries, output, commands)
  Bytes::from_array(output)
}

///|
fn menu_commands(
  entries : Array[@tray.TrayMenuEntry],
) -> Array[@tray.TrayCommandId] {
  let output : Array[Byte] = []
  let commands : Array[@tray.TrayCommandId] = []
  encode_menu_entries(entries, output, commands)
  commands
}

///|
impl DesktopExtension for WindowsTrayExtension with fn identifier(self) {
  ignore(self)
  "orbit.tray.windows"
}

///|
impl DesktopExtension for WindowsTrayExtension with fn commands(_self) {
  []
}

///|
impl DesktopExtension for WindowsTrayExtension with fn start(self, controller) {
  let identifiers : Map[String, Bool] = Map([])
  for item in self.configured_items {
    let id = item.id().value()
    if identifiers.contains(id) {
      return Err("duplicate Windows tray item: \{id}")
    }
    identifiers[id] = true
    let mounted = match create_native_item(item) {
      Ok(mounted) => mounted
      Err(reason) => {
        for current in self.items.val {
          native_destroy_item(current.native)
        }
        self.items.val.clear()
        return Err(reason)
      }
    }
    self.items.val.push(mounted)
  }
  self.controller.val = Some(controller)
  self.tray_controller.val = Some(
    @tray.TrayController::new(item => self.replace(item), id => {
      self.open_menu(id)
    }),
  )
  self.alive.val = true
  Ok(())
}

///|
impl DesktopExtension for WindowsTrayExtension with fn poll(self, controller) {
  let bytes = native_next_event()
  if bytes.length() == 0 {
    return Ok(())
  }
  if bytes.length() != 7 {
    return Err("Windows tray event queue returned an invalid record")
  }
  let slot = bytes[0].to_int() |
    (bytes[1].to_int() << 8) |
    (bytes[2].to_int() << 16) |
    (bytes[3].to_int() << 24)
  let kind = bytes[4].to_int()
  let event = match kind {
    1 => @tray.TrayEvent::PrimaryActivation
    2 => @tray.TrayEvent::SecondaryActivation
    _ => @tray.TrayEvent::PrimaryActivation
  }
  let tray_controller = match self.tray_controller.val {
    Some(tray_controller) => tray_controller
    None => return Err("Windows tray controller is unavailable")
  }
  for mounted in self.items.val {
    if mounted.slot == slot {
      if kind == 3 {
        let index = bytes[5].to_int() | (bytes[6].to_int() << 8)
        let commands = menu_commands(mounted.item.menu())
        if index < 0 || index >= commands.length() {
          return Err("Windows tray menu returned an invalid command")
        }
        (self.callback)(
          controller,
          tray_controller,
          mounted.item.id(),
          Command(commands[index]),
        )
        return Ok(())
      }
      (self.callback)(controller, tray_controller, mounted.item.id(), event)
      return Ok(())
    }
  }
  Ok(())
}

///|
impl DesktopExtension for WindowsTrayExtension with fn window_destroyed(
  _self,
  _label,
) {
  Ok(())
}

///|
impl DesktopExtension for WindowsTrayExtension with fn shutdown(self) {
  for mounted in self.items.val {
    native_destroy_item(mounted.native)
  }
  self.items.val.clear()
  self.alive.val = false
  self.controller.val = None
  self.tray_controller.val = None
  Ok(())
}
