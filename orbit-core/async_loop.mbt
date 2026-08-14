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
  failure : Ref[@orby.AppError?]
}

///|
using @external_loop {trait ExternalEventLoop}

///|
impl ExternalEventLoop for AsyncDesktopLoop with fn poll(self, timeout?) {
  try {
    match self.app_loop.poll(timeout?) {
      @orby.ExternalPoll::Continue => ()
      @orby.ExternalPoll::Exited(_code) => ()
    }
  } catch {
    error => self.failure.val = Some(error)
  }
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
