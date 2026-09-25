///|
test "native platform detection returns a known desktop platform" {
  match @orbit-utils.current_platform() {
    Windows | Linux | MacOS | Android | OpenHarmony => ()
    Unknown(value) => abort("unexpected native platform: \{value}")
  }
}
