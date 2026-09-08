///|
test "remote IPC uses the message source, never a navigation destination" {
  let navigation = Some(
    @orbit_runtime.RemoteNavigation::new(
      allowed_origins=["https://a.example", "https://b.example"],
      fallback_url="orbit://app/offline.html",
    ),
  )
  assert_true(
    allows_navigation(None, navigation, _ => false, "https://b.example/"),
  )
  let message = authenticated_page_message(
    None,
    navigation,
    "body",
    Some("https://a.example/page"),
  ).unwrap()
  assert_eq(message.origin(), Some("https://a.example"))
  assert_true(
    authenticated_page_message(None, navigation, "body", None) is None,
  )
  assert_true(
    authenticated_page_message(
      None,
      navigation,
      "body",
      Some("https://evil.example/"),
    )
    is None,
  )
  assert_true(
    authenticated_page_message(
      None,
      navigation,
      "body",
      Some("https://a.example.evil/"),
    )
    is None,
  )
  assert_true(authenticated_page_message(None, None, "local", None) is Some(_))
}
