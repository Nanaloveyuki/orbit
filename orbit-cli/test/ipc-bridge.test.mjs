import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const source = readFileSync(new URL("../../orbit-ipc-moonview/adapter.mbt", import.meta.url), "utf8");
const script = source.split(/\r?\n/)
  .filter(line => line.trimStart().startsWith("#|"))
  .map(line => line.trimStart().slice(2)).join("\n")
  .replace(/const invocationEnabled =\s*;/, "const invocationEnabled =true;");

function androidBridge() {
  let receive;
  const sent = [];
  const window = {
    ajni: { postMessage: message => sent.push(JSON.parse(message)) },
    addEventListener: (_, listener) => { receive = listener; },
  };
  window.top = window;
  vm.runInNewContext(script, { window, TextEncoder, setTimeout, clearTimeout });
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
