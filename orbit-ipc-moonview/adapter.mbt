///|
pub enum PagePrincipal {
  Window
  RemotePage
} derive(Eq, Debug)

///|
pub fn PagePrincipal::window() -> PagePrincipal {
  Window
}

///|
pub fn PagePrincipal::remote_page() -> PagePrincipal {
  RemotePage
}

///|
fn bridge_script(enable_invocation : Bool) -> String {
  let invocation_enabled = if enable_invocation { "true" } else { "false" }
  (
    #|(() => {
    #|  if (window.top !== window) return;
    #|  const api = window.moonview;
    #|  if (!api || typeof api.postMessage !== "function") return;
    #|  const invocationEnabled =
  ) +
  invocation_enabled +
  (
    #|; const pending = new Map(); const listeners = new Map(); const maxMessageBytes = 262144; const defaultTimeoutMs = 30000; let nextId = 0;
    #|  let legacyHandler = typeof api.onmessage === "function" ? api.onmessage : null;
    #|  class IpcError extends Error { constructor(code, message, data = null) { super(message); this.name = "OrbitIpcError"; this.code = code; this.data = data; } }
    #|  const validEventName = name => typeof name === "string" && /^[^\x00-\x1F\x7F]{1,128}$/.test(name);
    #|  const unlisten = (name, listener) => { const handlers = listeners.get(name); if (!handlers || typeof listener !== "function") return false; const removed = handlers.delete(listener); if (handlers.size === 0) listeners.delete(name); return removed; };
    #|  const listen = (name, listener) => { if (!validEventName(name)) throw new TypeError("invalid Orbit event name"); if (typeof listener !== "function") throw new TypeError("Orbit event listener must be a function"); let handlers = listeners.get(name); if (!handlers) { handlers = new Set(); listeners.set(name, handlers); } handlers.add(listener); return () => unlisten(name, listener); };
    #|  const dispatchEvent = message => { if (message.version !== 1 || message.type !== "event" || !validEventName(message.event)) return false; const handlers = listeners.get(message.event); if (!handlers) return true; const event = Object.freeze({ name: message.event, payload: message.payload, source: message.source ?? null, target: message.target ?? null }); for (const handler of Array.from(handlers)) { try { handler(event); } catch (error) { setTimeout(() => { throw error; }, 0); } } return true; };
    #|  const complete = event => { let response; try { response = JSON.parse(String(event.data)); } catch (_) { if (legacyHandler) legacyHandler(event); return; } if (dispatchEvent(response)) return; const request = pending.get(response.id); if (request) { pending.delete(response.id); clearTimeout(request.timer); if (response.version !== 1 || typeof response.ok !== "boolean") request.reject(new IpcError("invalid_response", "invalid IPC response")); else if (response.ok) request.resolve(response.result); else { const error = response.error || {}; request.reject(new IpcError(error.code || "command_failed", error.message || "IPC command failed", error.data)); } return; } if (legacyHandler) legacyHandler(event); };
    #|  Object.defineProperty(api, "onmessage", { configurable: true, get: () => complete, set: handler => { legacyHandler = typeof handler === "function" ? handler : null; } });
    #|  const invoke = (command, payload = null, options = {}) => { if (!invocationEnabled) return Promise.reject(new IpcError("ipc_unavailable", "Orbit IPC is not enabled for this page")); if (typeof command !== "string" || !/^[A-Za-z0-9_.:/-]{1,128}$/.test(command)) return Promise.reject(new IpcError("invalid_command", "invalid IPC command name")); const timeoutMs = options.timeout ?? defaultTimeoutMs; if (!Number.isInteger(timeoutMs) || timeoutMs <= 0 || timeoutMs > 300000) return Promise.reject(new IpcError("invalid_timeout", "timeout must be an integer between 1 and 300000")); const id = `orbit-${Date.now().toString(36)}-${(++nextId).toString(36)}`; let message; try { message = JSON.stringify({ version: 1, id, command, payload: payload === undefined ? null : payload }); } catch (_) { return Promise.reject(new IpcError("serialization_failed", "IPC payload is not JSON serializable")); } if (!message || new TextEncoder().encode(message).byteLength > maxMessageBytes) return Promise.reject(new IpcError("message_too_large", "IPC message exceeds the 256 KiB limit")); return new Promise((resolve, reject) => { const timer = setTimeout(() => { pending.delete(id); reject(new IpcError("timeout", `IPC command timed out after ${timeoutMs}ms`)); }, timeoutMs); pending.set(id, { resolve, reject, timer }); try { api.postMessage(message); } catch (_) { pending.delete(id); clearTimeout(timer); reject(new IpcError("transport_failed", "IPC transport is unavailable")); } }); };
    #|  const orbit = { listen, unlisten }; if (invocationEnabled) { orbit.invoke = invoke; orbit.IpcError = IpcError; }
    #|  Object.defineProperty(window, "__ORBIT__", { configurable: false, enumerable: false, writable: false, value: Object.freeze(orbit) });
    #|})();
  )
}

///|
pub fn initialization_script(application_script : String) -> String {
  "\{bridge_script(true)}\n\{application_script}"
}

///|
/// Installs page event listeners without making the IPC invocation API
/// available to the page.
pub fn event_initialization_script(application_script : String) -> String {
  "\{bridge_script(false)}\n\{application_script}"
}

///|
pub fn encode_page_event(
  event : @event.EventEnvelope,
) -> Result[String, @event.EventDeliveryFailure] {
  let message = "{\"version\":1,\"type\":\"event\",\"event\":\{Json::string(event.name.value()).stringify()},\"payload\":\{event.payload.stringify()},\"source\":\{event.source.to_json().stringify()},\"target\":\{event.target.to_json().stringify()}}"
  if message.length() > 262_144 {
    Err(
      @event.EventDeliveryFailure::new(
        code="event_too_large",
        message="page event exceeds the 256 KiB message limit",
      ),
    )
  } else {
    Ok(message)
  }
}

///|
pub fn dispatch(
  registry : @ipc.CommandRegistry,
  policy : @ipc.CommandPolicy,
  label : String,
  principal : PagePrincipal,
  page_message : @runtime.RuntimePageMessage,
) -> String? {
  let context = try {
    match principal {
      Window => @ipc.InvocationContext::window(label)
      RemotePage =>
        @ipc.InvocationContext::remote_page(label, origin=page_message.origin())
    }
  } catch {
    _ => return None
  }
  Some(registry.dispatch_with_context(page_message.body(), policy, context))
}

///|
test "bridge is top-level only and bounded" {
  let script = initialization_script("window.app = true")
  assert_true(script.contains("window.top !== window"))
  assert_true(script.contains("message_too_large"))
  assert_true(script.contains("legacyHandler"))
  assert_true(script.contains("const listen"))
  assert_true(script.contains("type !== \"event\""))
  assert_true(script.has_suffix("window.app = true"))
}

///|
test "event-only bridge omits the invocation API" {
  let script = event_initialization_script("window.app = true")
  assert_true(script.contains("const invocationEnabled =false"))
  assert_true(script.contains("const orbit = { listen, unlisten }"))
}

///|
test "page events preserve the routed envelope" {
  let event = @event.EventEnvelope::new(
    name=@event.EventName::new("orbit://application/changed"),
    payload={ "revision": 4 },
    source=Application,
    target=Window("main"),
  )
  match encode_page_event(event) {
    Ok(message) => {
      assert_true(message.contains("\"type\":\"event\""))
      assert_true(message.contains("\"event\":\"orbit://application/changed\""))
      assert_true(message.contains("\"revision\":4"))
    }
    Err(error) => abort(error.message)
  }
}
