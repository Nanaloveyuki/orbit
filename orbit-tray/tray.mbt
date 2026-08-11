///|
pub(all) suberror TrayError {
  InvalidIdentifier(String)
  DuplicateMenuCommand(String)
  EmptyIcon
  Unavailable
} derive(Debug)

///|
pub struct TrayItemId {
  priv value_ : String
} derive(Eq, Debug)

///|
pub fn TrayItemId::new(value : String) -> TrayItemId raise TrayError {
  if value.trim().is_empty() {
    raise InvalidIdentifier("tray item identifier must not be empty")
  }
  { value_: value }
}

///|
pub fn TrayItemId::value(self : TrayItemId) -> String {
  self.value_
}

///|
pub struct TrayCommandId {
  priv value_ : String
} derive(Eq, Debug)

///|
pub fn TrayCommandId::new(value : String) -> TrayCommandId raise TrayError {
  if value.trim().is_empty() {
    raise InvalidIdentifier("tray command identifier must not be empty")
  }
  { value_: value }
}

///|
pub fn TrayCommandId::value(self : TrayCommandId) -> String {
  self.value_
}

///|
pub struct TrayIcon {
  png : Bytes
}

///|
pub fn TrayIcon::from_png(png : Bytes) -> TrayIcon raise TrayError {
  if png.length() == 0 {
    raise EmptyIcon
  }
  { png, }
}

///|
pub fn TrayIcon::png(self : TrayIcon) -> Bytes {
  self.png
}

///|
pub(all) enum TrayMenuEntry {
  Command(TrayCommandId, String, Bool, Bool)
  Separator
  Submenu(String, Array[TrayMenuEntry])
} derive(Debug)

///|
pub(all) enum TrayEvent {
  PrimaryActivation
  SecondaryActivation
  Command(TrayCommandId)
} derive(Debug)

///|
pub struct TrayController {
  priv replace_item_ : (TrayItem) -> Result[Unit, TrayError]
  priv open_menu_ : (TrayItemId) -> Result[Unit, TrayError]
}

///|
pub fn TrayController::new(
  replace_item : (TrayItem) -> Result[Unit, TrayError],
  open_menu : (TrayItemId) -> Result[Unit, TrayError],
) -> TrayController {
  { replace_item_: replace_item, open_menu_: open_menu }
}

///|
pub fn TrayController::replace_item(
  self : TrayController,
  item : TrayItem,
) -> Unit raise TrayError {
  match (self.replace_item_)(item) {
    Ok(_) => ()
    Err(error) => raise error
  }
}

///|
pub fn TrayController::open_menu(
  self : TrayController,
  id : TrayItemId,
) -> Unit raise TrayError {
  match (self.open_menu_)(id) {
    Ok(_) => ()
    Err(error) => raise error
  }
}

///|
pub struct TrayItem {
  id : TrayItemId
  icon : TrayIcon
  tooltip : String
  visible : Bool
  menu : Array[TrayMenuEntry]
}

///|
fn validate_menu_entries(
  entries : Array[TrayMenuEntry],
  commands : Map[String, Bool],
) -> Unit raise TrayError {
  for entry in entries {
    match entry {
      Command(id, _, _, _) => {
        let value = id.value()
        if commands.contains(value) {
          raise DuplicateMenuCommand(value)
        }
        commands[value] = true
      }
      Separator => ()
      Submenu(_, children) => validate_menu_entries(children, commands)
    }
  }
}

///|
pub fn TrayItem::new(
  id : TrayItemId,
  icon : TrayIcon,
  tooltip : String,
  visible? : Bool = true,
  menu? : Array[TrayMenuEntry] = [],
) -> TrayItem raise TrayError {
  let commands : Map[String, Bool] = Map([])
  validate_menu_entries(menu, commands)
  { id, icon, tooltip, visible, menu }
}

///|
pub fn TrayItem::id(self : TrayItem) -> TrayItemId {
  self.id
}

///|
pub fn TrayItem::icon(self : TrayItem) -> TrayIcon {
  self.icon
}

///|
pub fn TrayItem::tooltip(self : TrayItem) -> String {
  self.tooltip
}

///|
pub fn TrayItem::visible(self : TrayItem) -> Bool {
  self.visible
}

///|
pub fn TrayItem::menu(self : TrayItem) -> Array[TrayMenuEntry] {
  self.menu
}
