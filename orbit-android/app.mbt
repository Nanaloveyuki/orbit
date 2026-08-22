///|
pub(all) suberror AndroidAppError {
  InvalidOptions(String)
} derive(Debug)

///|
pub struct AndroidAppOptions {
  runtime_options : @runtime.RuntimeOptions
  ipc_registry : @ipc.CommandRegistry?
  ipc_policy : @ipc.CommandPolicy?
  trusted_origin : String
}

///|
pub fn AndroidAppOptions::new(
  runtime_options~ : @runtime.RuntimeOptions,
  ipc_registry? : @ipc.CommandRegistry? = None,
  ipc_policy? : @ipc.CommandPolicy? = None,
  trusted_origin? : String = "https://orbit.local",
) -> AndroidAppOptions raise AndroidAppError {
  match (ipc_registry, ipc_policy) {
    (Some(_), None) | (None, Some(_)) =>
      raise InvalidOptions(
        "Android IPC registry and policy must be configured together",
      )
    _ => ()
  }
  if trusted_origin.is_empty() {
    raise InvalidOptions("Android trusted origin must not be empty")
  }
  { runtime_options, ipc_registry, ipc_policy, trusted_origin }
}

///|
fn configured_runtime_options(
  options : AndroidAppOptions,
) -> @runtime.RuntimeOptions {
  match (options.ipc_registry, options.ipc_policy) {
    (Some(_), Some(_)) =>
      options.runtime_options.with_initialization_script(
        @ipc_moonview.initialization_script(
          options.runtime_options.initialization_script,
        ),
      )
    _ =>
      options.runtime_options.with_initialization_script(
        @ipc_moonview.event_initialization_script(
          options.runtime_options.initialization_script,
        ),
      )
  }
}

///|
fn create_runtime(
  options : AndroidAppOptions,
  runtime_slot : Ref[&@runtime.WebViewRuntime?],
) -> Unit {
  if runtime_slot.val is Some(_) {
    return
  }
  let factory = @android_runtime.AndroidRuntimeFactory::new(
    trusted_origin=options.trusted_origin,
  )
  let host = @runtime.RuntimeHost::new(1UL) catch { _ => return }
  let runtime = @runtime.RuntimeFactory::create(
    factory,
    host,
    configured_runtime_options(options),
  ) catch {
    error => {
      options.runtime_options.lifecycle_handler()(Failed(error))
      return
    }
  }
  runtime_slot.val = Some(runtime)
  runtime.set_message_handler(
    Some(message => {
      match (options.ipc_registry, options.ipc_policy, runtime_slot.val) {
        (Some(registry), Some(policy), Some(runtime)) =>
          match
            @ipc_moonview.dispatch(
              registry,
              policy,
              options.runtime_options.label(),
              @ipc_moonview.PagePrincipal::window(),
              message,
            ) {
            Some(response) => runtime.post_message(response) catch { _ => () }
            None => ()
          }
        _ => ()
      }
    }),
  ) catch {
    _ => ()
  }
}

///|
fn destroy_runtime(runtime_slot : Ref[&@runtime.WebViewRuntime?]) -> Unit {
  match runtime_slot.val {
    Some(runtime) => runtime.destroy() catch { _ => () }
    None => ()
  }
  runtime_slot.val = None
}

///|
fn resize_runtime(
  runtime_slot : Ref[&@runtime.WebViewRuntime?],
  width : Int,
  height : Int,
) -> Unit {
  if width <= 0 || height <= 0 {
    return
  }
  match runtime_slot.val {
    Some(runtime) => {
      let bounds = @runtime.RuntimeBounds::new(width~, height~) catch {
        _ => return
      }
      runtime.set_bounds(bounds) catch {
        _ => ()
      }
    }
    None => ()
  }
}

///|
/// Installs the process-wide Android lifecycle handler. Call this from the
/// Android executable's `main`; the Kotlin host will deliver Activity events.
pub fn run(options : AndroidAppOptions) -> Unit {
  let runtime_slot : Ref[&@runtime.WebViewRuntime?] = Ref(None)
  ignore(
    @ajni_android.install_event_handler(event => {
      match event {
        Lifecycle(Created) => create_runtime(options, runtime_slot)
        Lifecycle(Destroyed) => destroy_runtime(runtime_slot)
        SurfaceChanged(width, height) =>
          resize_runtime(runtime_slot, width, height)
        _ => ()
      }
    }),
  )
}
