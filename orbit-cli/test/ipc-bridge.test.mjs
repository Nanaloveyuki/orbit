import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const source = readFileSync(new URL("../../orbit-ipc-moonview/adapter.mbt", import.meta.url), "utf8");
const script = source.split(/\r?\n/)
  .filter(line => line.trimStart().startsWith("#|"))
  .map(line => line.trimStart().slice(2)).join("\n")
  .replace(/const invocationEnabled =\s*;/, "const invocationEnabled =true;");

function androidBridge(timers = { setTimeout, clearTimeout }) {
  const handlers = new Map();
  const sent = [];
  const window = {
    ajni: { postMessage: message => sent.push(JSON.parse(message)) },
    addEventListener: (name, listener) => { handlers.set(name, listener); },
  };
  window.top = window;
  vm.runInNewContext(script, { window, TextEncoder, Date: { now: () => 0 }, ...timers });
  return { api: window.__ORBIT__, sent, receive: event => handlers.get("message")(event), dispatch: name => handlers.get(name)?.() };
}

test("Android bridge rejects frame and synthetic events but accepts native messages", () => {
  const bridge = androidBridge();
  const received = [];
  bridge.api.listen("app.changed", event => received.push(event.payload));
  const data = JSON.stringify({ version: 1, type: "event", event: "app.changed", payload: 7 });
  bridge.receive({ data, isTrusted: true, source: {}, origin: "https://untrusted.example" });
  bridge.receive({ data, isTrusted: false, source: null });
  assert.deepEqual(received, []);
  bridge.receive({ data, isTrusted: true, source: null });
  assert.deepEqual(received, [7]);
});

test("a forged frame response cannot settle an Android invocation", async () => {
  const bridge = androidBridge();
  const result = bridge.api.invoke("app.echo");
  const response = value => JSON.stringify({ version: 1, id: bridge.sent[0].id, ok: true, result: value });
  bridge.receive({ data: response("forged"), isTrusted: true, source: {} });
  bridge.receive({ data: response("native"), isTrusted: true, source: null });
  assert.equal(await result, "native");
});

test("page requests enforce UTF8 bytes including the envelope", async () => {
  const bridge = androidBridge();
  const empty = JSON.stringify({ version: 1, type: "invoke", id: "orbit-0-1", command: "echo", payload: "", timeout_ms: 30000 });
  const payload = "x".repeat(262144 - new TextEncoder().encode(empty).byteLength);
  const accepted = bridge.api.invoke("echo", payload);
  assert.equal(new TextEncoder().encode(JSON.stringify(bridge.sent[0])).byteLength, 262144);
  bridge.receive({ data: JSON.stringify({ version: 1, id: bridge.sent[0].id, ok: true, result: 1 }), isTrusted: true, source: null });
  assert.equal(await accepted, 1);
  await assert.rejects(bridge.api.invoke("echo", payload + "x"), { code: "message_too_large" });
  await assert.rejects(bridge.api.invoke("echo", "\u4E2D".repeat(100000)), { code: "message_too_large" });
  assert.equal(bridge.sent.length, 1);
});

test("page timeout sends cancellation and late completion cannot settle again", async () => {
  let expire;
  const bridge = androidBridge({ setTimeout: callback => { expire = callback; return 1; }, clearTimeout: () => {} });
  const pending = bridge.api.invoke("echo", null, { timeout: 10 });
  const rejected = assert.rejects(pending, { code: "timeout" });
  expire();
  await rejected;
  assert.deepEqual(bridge.sent[1], { version: 1, type: "cancel", id: bridge.sent[0].id });
  bridge.receive({ data: JSON.stringify({ version: 1, id: bridge.sent[0].id, ok: true, result: "late" }), isTrusted: true, source: null });
  await assert.rejects(pending, { code: "timeout" });
});

test("AbortSignal cancels once, removes its listener, and ignores late completion", async () => {
  const bridge = androidBridge();
  const controller = new AbortController();
  let removed = 0;
  const remove = controller.signal.removeEventListener.bind(controller.signal);
  controller.signal.removeEventListener = (...args) => { removed++; remove(...args); };
  const pending = bridge.api.invoke("echo", null, { signal: controller.signal });
  const rejected = assert.rejects(pending, { code: "cancelled" });
  controller.abort();
  controller.abort();
  await rejected;
  assert.equal(removed, 1);
  assert.equal(bridge.sent.length, 2);
  assert.deepEqual(bridge.sent[1], { version: 1, type: "cancel", id: bridge.sent[0].id });
  bridge.receive({ data: JSON.stringify({ version: 1, id: bridge.sent[0].id, ok: true, result: 1 }), isTrusted: true, source: null });
  assert.equal(removed, 1);
});

test("pre-aborted and invalid options never send a request", async () => {
  const bridge = androidBridge();
  await assert.rejects(bridge.api.invoke("echo", null, { signal: AbortSignal.abort() }), { code: "cancelled" });
  await assert.rejects(bridge.api.invoke("echo", null, null), { code: "invalid_options" });
  await assert.rejects(bridge.api.invoke("echo", null, { signal: {} }), { code: "invalid_signal" });
  assert.equal(bridge.sent.length, 0);
});

test("successful calls remove abort listeners without sending cancellation", async () => {
  const bridge = androidBridge();
  const controller = new AbortController();
  const pending = bridge.api.invoke("echo", null, { signal: controller.signal });
  bridge.receive({ data: JSON.stringify({ version: 1, id: bridge.sent[0].id, ok: true, result: 3 }), isTrusted: true, source: null });
  assert.equal(await pending, 3);
  controller.abort();
  assert.equal(bridge.sent.length, 1);
});

test("pagehide cancels pending requests and clears subscriptions; pageshow reactivates", async () => {
  const bridge = androidBridge();
  let events = 0;
  bridge.api.listen("changed", () => events++);
  const pending = bridge.api.invoke("echo");
  const rejected = assert.rejects(pending, { code: "page_unloaded" });
  bridge.dispatch("pagehide");
  await rejected;
  await assert.rejects(bridge.api.invoke("echo"), { code: "page_unloaded" });
  bridge.receive({ data: JSON.stringify({ version: 1, type: "event", event: "changed", payload: 1 }), isTrusted: true, source: null });
  assert.equal(events, 0);
  bridge.dispatch("pageshow");
  const next = bridge.api.invoke("echo");
  bridge.receive({ data: JSON.stringify({ version: 1, id: bridge.sent.at(-1).id, ok: true, result: 5 }), isTrusted: true, source: null });
  assert.equal(await next, 5);
});

test("non-object messages do not break the bridge", () => {
  const bridge = androidBridge();
  for (const data of ["null", "false", "7", "[]", "\"text\""]) {
    assert.doesNotThrow(() => bridge.receive({ data, isTrusted: true, source: null }));
  }
});

test("desktop transport preserves its legacy handler and supports cancellation", async () => {
  const sent = [];
  const legacy = [];
  const window = { moonview: { postMessage: message => sent.push(JSON.parse(message)), onmessage: event => legacy.push(event.data) }, addEventListener() {} };
  window.top = window;
  vm.runInNewContext(script, { window, TextEncoder, setTimeout, clearTimeout, Date });
  window.moonview.onmessage({ data: "not-json" });
  assert.deepEqual(legacy, ["not-json"]);
  const controller = new AbortController();
  const pending = window.__ORBIT__.invoke("echo", null, { signal: controller.signal });
  const rejected = assert.rejects(pending, { code: "cancelled" });
  controller.abort();
  await rejected;
  assert.deepEqual(sent[1], { version: 1, type: "cancel", id: sent[0].id });
});
