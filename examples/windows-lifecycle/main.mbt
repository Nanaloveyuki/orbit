///|
fn[T] fail(message : String) -> T {
  abort("windows-lifecycle: \{message}")
}

///|
struct ApplicationState {
  latest : Ref[Json]
}

///|
fn command_registry(
  state : ApplicationState,
) -> @ipc.CommandRegistry raise @ipc.IpcError {
  let registry = @ipc.CommandRegistry::new()
  registry.register_json(@ipc.CommandName::new("lifecycle.state.load"), _payload => {
    Ok(state.latest.val)
  })
  registry.register_json(@ipc.CommandName::new("lifecycle.state.save"), payload => {
    state.latest.val = payload
    Ok({ "saved": true })
  })
  registry
}

///|
fn tray_icon() -> @tray.TrayIcon raise @tray.TrayError {
  let image = @image.Image::new(1, 1, b"\x2d\xb8\x92\xff") catch {
    _ => fail("could not create the tray icon")
  }
  let png = @image.encode_png(image) catch {
    _ => fail("could not encode the tray icon")
  }
  @tray.TrayIcon::from_png(png)
}

///|
fn tray_callback(
  desktop : @core.DesktopController,
  tray : @tray.TrayController,
  _item : @tray.TrayItemId,
  event : @tray.TrayEvent,
) -> Unit {
  match event {
    PrimaryActivation => desktop.show_window("main") catch { _ => () }
    SecondaryActivation =>
      tray.open_menu(@tray.TrayItemId::new("main")) catch {
        _ => ()
      }
    Command(command) =>
      match command.value() {
        "show" => desktop.show_window("main") catch { _ => () }
        "suspend" => desktop.suspend_window("main") catch { _ => () }
        "exit" => desktop.exit() catch { _ => () }
        _ => ()
      }
  }
}

///|
fn windows_tray_extension() -> &@core.DesktopExtension? {
  if @utils.current_platform() != @utils.Platform::Windows {
    return None
  }
  let item = @tray.TrayItem::new(
    @tray.TrayItemId::new("main"),
    tray_icon(),
    "Orbit Lifecycle Example",
    menu=[
      @tray.TrayMenuEntry::Command(
        @tray.TrayCommandId::new("show"),
        "Show window",
        true,
        false,
      ),
      @tray.TrayMenuEntry::Command(
        @tray.TrayCommandId::new("suspend"),
        "Suspend window",
        true,
        false,
      ),
      @tray.TrayMenuEntry::Separator,
      @tray.TrayMenuEntry::Command(
        @tray.TrayCommandId::new("exit"),
        "Exit",
        true,
        false,
      ),
    ],
  ) catch {
    _ => fail("could not configure the tray item")
  }
  let extension = @tray_windows.WindowsTrayExtension::new([item], tray_callback) catch {
    _ => fail("could not configure the Windows tray")
  }
  Some(extension.as_extension())
}

///|
fn main {
  let state = { latest: Ref({ "value": "" }) }
  let ipc_registry = command_registry(state) catch {
    _ => fail("could not register IPC commands")
  }
  let ipc_policy = configured_ipc_policy() catch {
    _ => fail("could not configure IPC permissions")
  }
  let file_extension = @desktop_file.DesktopFileExtension::new()
  let extensions = match windows_tray_extension() {
    Some(tray_extension) => [file_extension.as_extension(), tray_extension]
    None => [file_extension.as_extension()]
  }
  let desktop_options = @core.DesktopOptions::new(
    windows=configured_windows(),
    ipc_registry=Some(ipc_registry),
    ipc_policy=Some(ipc_policy),
    plugin_declarations=configured_plugins(),
    extensions~,
    close_request_handler=Some((_label, _controller) => {
      @core.DesktopCloseAction::suspend()
    }),
    runtime_suspend_handler=Some(_label => Ok(())),
  ) catch {
    _ => fail("could not create desktop options")
  }
  let factory = @moonview_runtime.MoonViewRuntimeFactory::new()
    as &@runtime.RuntimeFactory
  @core.run_async(factory, desktop_options, async fn() { @async.pause() }) catch {
    _ => fail("desktop application terminated with an error")
  }
}
