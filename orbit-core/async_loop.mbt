///|
priv struct AsyncExit {
  finished : Ref[Bool]
  condition : @cond_var.Cond
}

///|
fn AsyncExit::new() -> AsyncExit {
  { finished: Ref(false), condition: @cond_var.Cond() }
}

///|
fn AsyncExit::finish(self : AsyncExit) -> Unit {
  if !self.finished.val {
    self.finished.val = true
    self.condition.signal()
  }
}

///|
async fn AsyncExit::wait(self : AsyncExit) -> Unit {
  if !self.finished.val {
    self.condition.wait()
  }
}

///|
priv struct AsyncDesktopLoop {
  app_loop : @orby.ExternalAppLoop[DesktopApp]
}

///|
using @external_loop { trait ExternalEventLoop }

///|
impl ExternalEventLoop for AsyncDesktopLoop with fn poll(self, timeout?) {
  self.app_loop.poll(timeout?)
}

///|
impl ExternalEventLoop for AsyncDesktopLoop with fn get_wakeup_callback_for_foreign_thread(
  self,
) {
  self.app_loop.wakeup_callback_for_foreign_thread()
}

///|
impl ExternalEventLoop for AsyncDesktopLoop with fn terminate(self) {
  ignore(self.app_loop.terminate())
}
