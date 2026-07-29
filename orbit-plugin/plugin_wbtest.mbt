///|
test "manifest requires strict JSON and declared fields" {
  match
    parse_manifest(
      "{\"id\":\"demo.echo\",\"name\":\"Demo\",\"version\":\"1\",\"commands\":[\"echo\"],\"permissions\":[]}",
    ) {
    Ok(manifest) => assert_eq(manifest.commands, ["echo"])
    Err(_) => fail("expected manifest")
  }
  match parse_manifest("{\"id\":\"a\",\"id\":\"b\"}") {
    Err(InvalidManifest(_)) => ()
    _ => fail("duplicate keys must be rejected")
  }
}

///|
test "every declared permission requires an explicit grant" {
  let manifest = parse_manifest(
    "{\"id\":\"demo.echo\",\"name\":\"Demo\",\"version\":\"1\",\"commands\":[\"echo\"],\"permissions\":[\"fs.read\",\"net.fetch\"]}",
  ).unwrap()
  let policy = PluginPolicy::new()
  policy.grant("fs.read")
  assert_eq(permissions_allowed(manifest, policy), Some("net.fetch"))
  policy.grant("net.fetch")
  assert_eq(permissions_allowed(manifest, policy), None)
}
