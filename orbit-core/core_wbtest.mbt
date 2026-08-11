///|
test "runtime suspension preparation returns the state persistence error" {
  let labels : Array[String] = []
  let result = prepare_runtime_suspension(
    Some(label => {
      labels.push(label)
      Err("state persistence failed")
    }),
    "main",
  )
  assert_eq(labels, ["main"])
  match result {
    Err(reason) => assert_true(reason.contains("state persistence failed"))
    Ok(_) => abort("expected state preparation to reject suspension")
  }
}

///|
priv struct DiagnosticTestRuntimeFactory {}

///|
impl @runtime.RuntimeFactory for DiagnosticTestRuntimeFactory with fn create(
  _self,
  _host,
  _options,
) {
  raise @runtime.Unavailable("not used by the extension lifecycle test")
}

///|
priv struct FailingStartExtension {}

///|
impl DesktopExtension for FailingStartExtension with fn identifier(_self) {
  "test.failing_start"
}

///|
impl DesktopExtension for FailingStartExtension with fn commands(_self) {
  []
}

///|
impl DesktopExtension for FailingStartExtension with fn start(
  _self,
  _controller,
) {
  Err("sensitive extension failure detail")
}

///|
impl DesktopExtension for FailingStartExtension with fn poll(_self, _controller) {
  Ok(())
}

///|
impl DesktopExtension for FailingStartExtension with fn window_suspended(
  _self,
  _label,
) {
  Ok(())
}

///|
impl DesktopExtension for FailingStartExtension with fn window_destroyed(
  _self,
  _label,
) {
  Ok(())
}

///|
impl DesktopExtension for FailingStartExtension with fn shutdown(_self) {
  Ok(())
}

///|
test "extension startup failure records only its stable diagnostic code" {
  let runtime_options = @runtime.RuntimeOptions::new(
    label="main",
    bounds=@runtime.RuntimeBounds::new(width=800, height=600),
    initial_content=Html("<main></main>"),
  )
  let history = @diagnostics.DiagnosticHistory::new()
  let extension = FailingStartExtension::{  }
  let options = DesktopOptions::new(
    windows=[DesktopWindowOptions::new("Orbit", runtime_options)],
    extensions=[extension as &DesktopExtension],
    diagnostic_sink=Some(history as &@diagnostics.DiagnosticSink),
  )
  let factory = DiagnosticTestRuntimeFactory::{  }
  let app : DesktopApp = {
    factory: factory as &@runtime.RuntimeFactory,
    options,
    windows: [],
    plugins: @plugin.PluginRuntime::new(),
    started_extensions: [],
    active: None,
    async_exit: None,
    async_ipc: None,
    pending_runtime_failure: None,
    teardown_failure: None,
    shutting_down: false,
  }
  match app.start_extensions() {
    Err(reason) =>
      assert_true(reason.contains("sensitive extension failure detail"))
    Ok(_) => abort("expected extension startup to fail")
  }
  let record = history.snapshot()[0]
  inspect(record.message, content="extension.start_failed")
  inspect(record.fields.length(), content="2")
  inspect(record.fields[0].value, content="orbit")
  inspect(record.fields[1].value, content="extension.start_failed")
}
