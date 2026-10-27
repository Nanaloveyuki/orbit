///|
test "file capabilities remain bound to the selecting window" {
  let registry = @orbit-file.FileCapabilityRegistry::new()
  let capability = registry.mint("main", "C:\\secret\\report.txt", Read) catch {
    _ => fail("expected random handle")
  }
  assert_eq(capability.name(), "report.txt")
  assert_true(capability.id().length() >= 20)
  let path = registry.resolve("main", capability.id(), Read) catch {
    _ => fail("expected selecting window to resolve its handle")
  }
  assert_eq(path, "C:\\secret\\report.txt")
  let cross_window_denied = try {
    ignore(registry.resolve("other", capability.id(), Read))
    false
  } catch {
    WrongPrincipal(_) => true
    _ => false
  }
  assert_true(cross_window_denied)
  let wrong_kind_denied = try {
    ignore(registry.resolve("main", capability.id(), Write))
    false
  } catch {
    WrongKind(_) => true
    _ => false
  }
  assert_true(wrong_kind_denied)
  let directory_denied = try {
    ignore(registry.mint("main", "C:\\secret\\folder", Directory))
    false
  } catch {
    DirectoryUnavailable => true
    _ => false
  }
  assert_true(directory_denied)
  registry.revoke_window("main")
  let revoked = try {
    ignore(registry.resolve("main", capability.id(), Read))
    false
  } catch {
    UnknownHandle(_) => true
    _ => false
  }
  assert_true(revoked)
}
