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

///|
test "sidecar manifests require v2 descriptors and JSON Schema objects" {
  let valid = parse_sidecar_manifest(
    "{\"schema_version\":2,\"abi_version\":1,\"id\":\"demo.echo\",\"name\":\"Demo\",\"version\":\"1\",\"platforms\":[\"windows\"],\"requested_permissions\":[],\"commands\":[{\"name\":\"echo\",\"request_schema\":{},\"response_schema\":{}}]}",
  )
  assert_true(valid is Ok(_))
  let valid_v2 = parse_sidecar_manifest(
    "{\"schema_version\":2,\"abi_version\":2,\"id\":\"demo.echo\",\"name\":\"Demo\",\"version\":\"1\",\"platforms\":[\"windows\"],\"requested_permissions\":[],\"commands\":[{\"name\":\"echo\",\"request_schema\":{},\"response_schema\":{}}]}",
  )
  assert_true(valid_v2 is Ok(_))
  let invalid = parse_sidecar_manifest(
    "{\"schema_version\":1,\"abi_version\":1,\"id\":\"demo.echo\",\"name\":\"Demo\",\"version\":\"1\",\"platforms\":[\"windows\"],\"requested_permissions\":[],\"commands\":[{\"name\":\"echo\",\"request_schema\":[],\"response_schema\":{}}]}",
  )
  assert_true(invalid is Err(_))
}

///|
test "runtime rejects manually constructed incompatible sidecars before loading" {
  let runtime = PluginRuntime::new()
  let sidecar = PluginSidecarManifest::{
    schema_version: 2,
    abi_version: 3,
    id: "demo.incompatible",
    name: "Demo",
    version: "1",
    platforms: ["windows"],
    requested_permissions: [],
    commands: [
      {
        name: "echo",
        request_schema: Json::empty_object(),
        response_schema: Json::empty_object(),
      },
    ],
  }
  let declaration = PluginDeclaration::new(
    id="demo.incompatible",
    library="missing.dll",
    sidecar~,
  )
  match runtime.start([declaration]) {
    Err(IncompatibleSidecar(id)) => inspect(id, content="demo.incompatible")
    _ => fail("expected incompatible sidecar rejection")
  }
}

///|
test "empty runtime shutdown is idempotent and observable" {
  let runtime = PluginRuntime::new()
  assert_eq(runtime.shutdown(), Ok(()))
  assert_eq(runtime.shutdown(), Ok(()))
}
