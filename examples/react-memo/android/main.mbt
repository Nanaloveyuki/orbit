///|
fn[T] fail(message : String) -> T {
  abort("orbit-react-memo-android: \{message}")
}

///|
fn memo_registry() -> @ipc.CommandRegistry raise @ipc.IpcError {
  let registry = @ipc.CommandRegistry::new()
  registry.register_json(@ipc.CommandName::new("memo.runtime"), _payload => {
    Ok({
      "application": app_name,
      "version": app_version,
      "runtime": "Orbit",
      "storage": "Android WebView localStorage",
    })
  })
  registry
}

///|
pub fn dispatch_android_event(kind : Int, first : Int, second : Int) -> Unit {
  @ajni_android.dispatch_from_android(kind, first, second)
}

///|
pub fn dispatch_android_webview_event(
  kind : Int,
  handle : Int64,
  payload : Bytes,
  detail : Bytes,
) -> Unit {
  @ajni_webview.dispatch_from_android(kind, handle, payload, detail)
}

///|

///|
fn configure_android_application() -> Unit {
  let options = @orbit_android.AndroidAppOptions::new(
    runtime_options=configured_android_runtime_options(),
    ipc_registry=Some(
      memo_registry() catch {
        _ => fail("could not register memo IPC commands")
      },
    ),
    ipc_policy=Some(
      configured_ipc_policy() catch {
        _ => fail("could not configure memo IPC permissions")
      },
    ),
  ) catch {
    _ => fail("could not create Android application options")
  }
  @orbit_android.run(options)
}

///|
/// Ajni invokes `moonbit_init` from `JNI_OnLoad`, not the executable entry.
let android_application : Unit = configure_android_application()

///|
fn main {
  ignore(android_application)
}
