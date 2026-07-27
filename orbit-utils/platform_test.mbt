///|
test "native platform detection returns a known desktop platform" {
  match current_platform() {
    Windows | Linux | MacOS | Android | OpenHarmony => ()
    Unknown(value) => abort("unexpected native platform: \{value}")
  }
}
