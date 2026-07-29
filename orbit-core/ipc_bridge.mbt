///|
fn ipc_bridge_script() -> String {
  (
    #|(() => {
    #|  if (window.top !== window) return;
    #|  const api = window.moonview;
    #|  if (!api || typeof api.postMessage !== "function") return;
    #|
    #|  const pending = new Map();
    #|  const maxMessageBytes = 262144;
    #|  const defaultTimeoutMs = 30000;
    #|  let nextId = 0;
    #|  let legacyHandler = typeof api.onmessage === "function" ? api.onmessage : null;
    #|
    #|  class IpcError extends Error {
    #|    constructor(code, message, data = null) {
    #|      super(message);
    #|      this.name = "OrbitIpcError";
    #|      this.code = code;
    #|      this.data = data;
    #|    }
    #|  }
    #|
    #|  const complete = event => {
    #|    let response;
    #|    try {
    #|      response = JSON.parse(String(event.data));
    #|    } catch (_) {
    #|      if (legacyHandler) legacyHandler(event);
    #|      return;
    #|    }
    #|    const request = pending.get(response.id);
    #|    if (request) {
    #|      pending.delete(response.id);
    #|      clearTimeout(request.timer);
    #|      if (response.version !== 1 || typeof response.ok !== "boolean") {
    #|        request.reject(new IpcError("invalid_response", "invalid IPC response"));
    #|      } else if (response.ok) {
    #|        request.resolve(response.result);
    #|      } else {
    #|        const error = response.error || {};
    #|        request.reject(new IpcError(error.code || "command_failed", error.message || "IPC command failed", error.data));
    #|      }
    #|      return;
    #|    }
    #|    if (legacyHandler) legacyHandler(event);
    #|  };
    #|
    #|  Object.defineProperty(api, "onmessage", {
    #|    configurable: true,
    #|    get: () => complete,
    #|    set: handler => { legacyHandler = typeof handler === "function" ? handler : null; },
    #|  });
    #|
    #|  const invoke = (command, payload = null, options = {}) => {
    #|    if (typeof command !== "string" || !/^[A-Za-z0-9_.:/-]{1,128}$/.test(command)) {
    #|      return Promise.reject(new IpcError("invalid_command", "invalid IPC command name"));
    #|    }
    #|    const timeoutMs = options.timeout ?? defaultTimeoutMs;
    #|    if (!Number.isInteger(timeoutMs) || timeoutMs <= 0 || timeoutMs > 300000) {
    #|      return Promise.reject(new IpcError("invalid_timeout", "timeout must be an integer between 1 and 300000"));
    #|    }
    #|    const id = `orbit-${Date.now().toString(36)}-${(++nextId).toString(36)}`;
    #|    let message;
    #|    try {
    #|      message = JSON.stringify({ version: 1, id, command, payload: payload === undefined ? null : payload });
    #|    } catch (_) {
    #|      return Promise.reject(new IpcError("serialization_failed", "IPC payload is not JSON serializable"));
    #|    }
    #|    if (!message || new TextEncoder().encode(message).byteLength > maxMessageBytes) {
    #|      return Promise.reject(new IpcError("message_too_large", "IPC message exceeds the 256 KiB limit"));
    #|    }
    #|    return new Promise((resolve, reject) => {
    #|      const timer = setTimeout(() => {
    #|        pending.delete(id);
    #|        reject(new IpcError("timeout", `IPC command timed out after ${timeoutMs}ms`));
    #|      }, timeoutMs);
    #|      pending.set(id, { resolve, reject, timer });
    #|      try {
    #|        api.postMessage(message);
    #|      } catch (_) {
    #|        pending.delete(id);
    #|        clearTimeout(timer);
    #|        reject(new IpcError("transport_failed", "IPC transport is unavailable"));
    #|      }
    #|    });
    #|  };
    #|
    #|  Object.defineProperty(window, "__ORBIT__", {
    #|    configurable: false,
    #|    enumerable: false,
    #|    writable: false,
    #|    value: Object.freeze({ invoke, IpcError }),
    #|  });
    #|})();
  )
}

///|
pub fn ipc_initialization_script(initialization_script : String) -> String {
  "\{ipc_bridge_script()}\n\{initialization_script}"
}

///|
test "IPC bridge exposes promise invocation and preserves legacy handlers" {
  let script = ipc_bridge_script()
  assert_true(script.contains("\"__ORBIT__\""))
  assert_true(script.contains("const invoke ="))
  assert_true(script.contains("new Promise"))
  assert_true(script.contains("setTimeout"))
  assert_true(script.contains("TextEncoder"))
  assert_true(script.contains("legacyHandler"))
  assert_true(script.contains("window.top !== window"))
  assert_true(script.contains("message_too_large"))
}

///|
test "IPC bridge runs before application initialization scripts" {
  let script = ipc_initialization_script("window.exampleInitialized = true")
  assert_true(script.has_prefix("(() =>"))
  assert_true(script.has_suffix("window.exampleInitialized = true"))
}
