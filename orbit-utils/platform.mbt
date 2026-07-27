///|
pub(all) enum Platform {
  Windows
  Linux
  MacOS
  Android
  OpenHarmony
  Unknown(String)
} derive(Eq, Debug)

///|
pub fn Platform::parse(value : StringView) -> Platform {
  match value.to_lower() {
    "windows" => Windows
    "linux" => Linux
    "macos" | "darwin" => MacOS
    "android" => Android
    "openharmony" | "ohos" => OpenHarmony
    other => Unknown(other.to_owned())
  }
}

///|
extern "C" fn native_platform_code() -> Int = "orbit_current_platform"

///|
pub fn current_platform() -> Platform {
  match native_platform_code() {
    1 => Windows
    2 => Linux
    3 => MacOS
    4 => Android
    5 => OpenHarmony
    code => Unknown("native-\{code}")
  }
}
