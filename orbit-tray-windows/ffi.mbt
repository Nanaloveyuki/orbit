///|
priv type NativeTrayItem

///|
#borrow(pixels, tooltip, status)
extern "C" fn native_create_item(
  pixels : Bytes,
  width : Int32,
  height : Int32,
  tooltip : Bytes,
  visible : Bool,
  status : Ref[Int32],
) -> NativeTrayItem = "orbit_tray_windows_create_item"

///|
#borrow(item, pixels, tooltip, status)
extern "C" fn native_replace_item(
  item : NativeTrayItem,
  pixels : Bytes,
  width : Int32,
  height : Int32,
  tooltip : Bytes,
  visible : Bool,
  status : Ref[Int32],
) -> Unit = "orbit_tray_windows_replace_item"

///|
#borrow(item)
extern "C" fn native_destroy_item(item : NativeTrayItem) -> Unit = "orbit_tray_windows_destroy_item"

///|
#borrow(item)
extern "C" fn native_item_slot(item : NativeTrayItem) -> Int32 = "orbit_tray_windows_item_slot"

///|
#borrow(item, menu, status)
extern "C" fn native_open_menu(
  item : NativeTrayItem,
  menu : Bytes,
  status : Ref[Int32],
) -> Unit = "orbit_tray_windows_open_menu"

///|
extern "C" fn native_next_event() -> Bytes = "orbit_tray_windows_next_event"
