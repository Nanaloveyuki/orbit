///|
fn test_provider() -> @runtime.RuntimeResourceProvider {
  @runtime.RuntimeResourceProvider::new(scheme="orbit", handler=_request => None) catch {
    _ => abort("test provider should be valid")
  }
}

///|
test "Android asset URLs preserve embedded paths" {
  let provider = test_provider()
  assert_eq(
    android_asset_url(
      provider, "https://orbit.local", "orbit://app/assets/index.js",
    ),
    Some("https://orbit.local/assets/assets/index.js"),
  )
  assert_eq(
    android_asset_url(
      provider, "https://orbit.local", "https://example.test/index.js",
    ),
    None,
  )
}

///|
test "Android responses split MIME parameters from encoding" {
  assert_eq(response_mime_type("text/html; charset=utf-8"), "text/html")
  assert_eq(response_encoding("text/html; charset=utf-8"), "utf-8")
  assert_eq(response_encoding("image/png"), "")
}
