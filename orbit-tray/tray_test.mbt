///|
test "tray items reject duplicate menu command identifiers" {
  let icon = TrayIcon::from_png(b"png")
  let item = try {
    ignore(
      TrayItem::new(TrayItemId::new("main"), icon, "Orbit", menu=[
        Command(TrayCommandId::new("show"), "Show", true, false),
        Submenu("More", [
          Command(TrayCommandId::new("show"), "Again", true, false),
        ]),
      ]),
    )
    false
  } catch {
    DuplicateMenuCommand("show") => true
    _ => false
  }
  assert_true(item)
}

///|
test "tray controller replaces complete item state and explicitly opens menus" {
  let replaced : Ref[String?] = Ref(None)
  let opened : Ref[String?] = Ref(None)
  let controller = TrayController::new(
    item => {
      replaced.val = Some(item.id().value())
      Ok(())
    },
    id => {
      opened.val = Some(id.value())
      Ok(())
    },
  )
  let id = TrayItemId::new("main")
  controller.replace_item(
    TrayItem::new(id, TrayIcon::from_png(b"png"), "Orbit"),
  )
  controller.open_menu(id)
  assert_eq(replaced.val, Some("main"))
  assert_eq(opened.val, Some("main"))
}
