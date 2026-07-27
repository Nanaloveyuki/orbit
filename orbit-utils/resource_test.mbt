///|
test "resource paths normalize separators and retain bytes" {
  let resource = EmbeddedResource::new(
    path="assets\\index.html",
    media_type="text/html",
    bytes=b"<html></html>",
  )
  inspect(resource.path(), content="assets/index.html")
  inspect(resource.fingerprint().length(), content="64")
  assert_true(resource.bytes() == b"<html></html>")
}

///|
test "resource table rejects duplicate normalized paths" {
  let table = ResourceTable::new()
  table.add(
    EmbeddedResource::new(
      path="assets/index.html",
      media_type="text/html",
      bytes=b"a",
    ),
  )
  let duplicate = try {
    table.add(
      EmbeddedResource::new(
        path="assets\\index.html",
        media_type="text/html",
        bytes=b"b",
      ),
    )
    false
  } catch {
    DuplicatePath(_) => true
    _ => false
  }
  assert_true(duplicate)
}

///|
test "CSP injection places policy first in head" {
  let html = inject_csp(
    "<!doctype html><html><head><title>Orbit</title></head><body></body></html>",
    "default-src 'self'",
  )
  assert_true(
    html.contains(
      "<head><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'self'\">",
    ),
  )
}

///|
test "resource paths reject traversal" {
  let rejected = normalize_resource_path("assets/../secret.txt")
  assert_true(rejected is Err(InvalidPath(_)))
}

///|
test "resource paths reject absolute Windows paths and NUL" {
  assert_true(
    normalize_resource_path("C:/assets/index.html") is Err(InvalidPath(_)),
  )
  assert_true(
    normalize_resource_path("assets/\u{0000}index.html") is Err(InvalidPath(_)),
  )
  assert_true(
    normalize_resource_path("assets/%2e%2e/secret") is Err(InvalidPath(_)),
  )
  assert_true(
    normalize_resource_path("index.html?debug=true") is Err(InvalidPath(_)),
  )
  assert_true(normalize_resource_path("index.html#main") is Err(InvalidPath(_)))
}

///|
test "SHA-256 fingerprints match the standard abc vector" {
  inspect(
    fingerprint_string("abc"),
    content="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

///|
test "CSP injection rejects an existing policy" {
  let rejected = try {
    ignore(
      inject_csp(
        "<html><head><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'\"></head></html>",
        "default-src 'self'",
      ),
    )
    false
  } catch {
    ExistingPolicy => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "CSP detection accepts whitespace around attribute assignment" {
  let rejected = try {
    ignore(
      inject_csp(
        "<html><head><meta http-equiv = \"Content-Security-Policy\" content=\"default-src 'none'\"></head></html>",
        "default-src 'self'",
      ),
    )
    false
  } catch {
    ExistingPolicy => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "CSP meta attributes are escaped" {
  inspect(
    csp_meta_tag("script-src 'nonce-\"unsafe\"' & 'self'"),
    content=(
      #|<meta http-equiv="Content-Security-Policy" content="script-src 'nonce-&quot;unsafe&quot;' &amp; 'self'">
    ),
  )
}

///|
test "CSP injection does not treat header as head" {
  let rejected = try {
    ignore(
      inject_csp(
        "<html><header>Not a head element</header><body></body></html>", "default-src 'self'",
      ),
    )
    false
  } catch {
    MissingHeadElement => true
    _ => false
  }
  assert_true(rejected)
}
