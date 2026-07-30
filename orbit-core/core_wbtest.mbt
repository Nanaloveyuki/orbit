///|
priv struct RecordingRuntime {
  messages : Ref[Array[String]]
}

///|
impl @runtime.WebViewRuntime for RecordingRuntime with fn capabilities(_self) {
  {
    navigation: true,
    script_evaluation: true,
    message_transport: true,
    bounds_updates: true,
    devtools: false,
  }
}

///|
impl @runtime.WebViewRuntime for RecordingRuntime with fn navigate(_self, _url) {

}

///|
impl @runtime.WebViewRuntime for RecordingRuntime with fn evaluate_script(
  _self,
  _script,
  _request_id,
) {

}

///|
impl @runtime.WebViewRuntime for RecordingRuntime with fn post_message(
  self,
  message,
) {
  self.messages.val.push(message)
}

///|
impl @runtime.WebViewRuntime for RecordingRuntime with fn set_message_handler(
  _self,
  _handler,
) {

}

///|
impl @runtime.WebViewRuntime for RecordingRuntime with fn set_bounds(
  _self,
  _bounds,
) {

}

///|
impl @runtime.WebViewRuntime for RecordingRuntime with fn destroy(_self) {

}

///|
test "page events reach only local window subscriptions" {
  let router = @event.EventRouter::new()
  let messages = Ref([])
  let runtime = RecordingRuntime::{ messages, } as &@runtime.WebViewRuntime
  let local_subscription = subscribe_page_events(
    Some(router),
    "main",
    Window,
    runtime,
  )
  let remote_subscription = subscribe_page_events(
    Some(router),
    "remote",
    RemotePage,
    runtime,
  )
  assert_true(local_subscription is Some(_))
  assert_true(remote_subscription is None)
  let event = @event.EventEnvelope::new(
    name=@event.EventName::new("orbit://application/changed"),
    payload={ "revision": 4 },
    target=Window("main"),
  )
  assert_eq((router as &@event.EventSink).emit(event), Ok(()))
  assert_eq(messages.val.length(), 1)
  assert_true(messages.val[0].contains("\"type\":\"event\""))
  assert_true(messages.val[0].contains("\"revision\":4"))
  match local_subscription {
    Some(subscription) => router.unsubscribe_additional(subscription)
    None => abort("expected local page event subscription")
  }
  assert_eq((router as &@event.EventSink).emit(event), Ok(()))
  assert_eq(messages.val.length(), 1)
}
