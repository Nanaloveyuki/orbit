///|
test "file capabilities remain bound to the selecting window" {
  let registry = FileCapabilityRegistry::new()
  let capability = registry
    .mint("main", "C:\\secret\\report.txt", Read)
    .unwrap_or_else(() => fail("expected random handle"))
  assert_eq(capability.name(), "report.txt")
  assert_true(capability.id().length() >= 20)
  match registry.resolve("main", capability.id(), Read) {
    Ok(path) => assert_eq(path, "C:\\secret\\report.txt")
    _ => fail("expected selecting window to resolve its handle")
  }
  match registry.resolve("other", capability.id(), Read) {
    Err(WrongPrincipal(_)) => ()
    _ => fail("expected cross-window denial")
  }
  match registry.resolve("main", capability.id(), Write) {
    Err(WrongKind(_)) => ()
    _ => fail("expected operation-kind denial")
  }
  registry.revoke_window("main")
  match registry.resolve("main", capability.id(), Read) {
    Err(UnknownHandle(_)) => ()
    _ => fail("expected revocation")
  }
}
