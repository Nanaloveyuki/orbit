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
  let receive;
  const sent = [];
  const window = {
    ajni: { postMessage: message => sent.push(JSON.parse(message)) },
    addEventListener: (_, listener) => { receive = listener; },
  };
  window.top = window;
  vm.runInNewContext(script, { window, TextEncoder, Date: { now: () => 0 }, ...timers });
  return { api: window.__ORBIT__, sent, receive: event => receive(event) };
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
