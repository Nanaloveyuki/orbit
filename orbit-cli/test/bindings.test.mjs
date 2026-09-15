import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = readFileSync(new URL("../../orbit-build/bindings.mbt", import.meta.url), "utf8");
const runtime = source.split("fn bindings_declarations")[0].split(/\r?\n/)
  .filter(line => line.trimStart().startsWith("#|"))
  .map(line => line.trimStart().slice(2)).join("\n");
const sdk = await import(`data:text/javascript,${encodeURIComponent('const commandNames = ["app.echo"]; const contractSchema = null;\n' + runtime)}`);

test("checked-in clients and declarations match the generator templates", async () => {
  const declarations = source.split("fn bindings_declarations")[1].split(/\r?\n/)
    .filter(line => line.trimStart().startsWith("#|"))
    .map(line => line.trimStart().slice(2)).join("\n");
  for (const directory of ["orbit-example", "examples/react-memo"]) {
    const base = new URL(`../../${directory}/`, import.meta.url);
    const generated = readFileSync(new URL("orbit-bindings.mjs", base), "utf8").replaceAll("\r\n", "\n");
    const types = readFileSync(new URL("orbit-bindings.d.mts", base), "utf8").replaceAll("\r\n", "\n");
    assert.equal(generated.slice(generated.indexOf("function validateContract")).trim(), runtime.trim(), `${directory}: regenerate client`);
    assert.equal(types.slice(types.indexOf("export interface CommandDefinition")).trim(), declarations.trim(), `${directory}: regenerate declarations`);
    const config = JSON.parse(readFileSync(new URL("orbit.conf.json", base), "utf8"));
    const candidates = config.capabilities.filter(grant => grant.effect === "allow" &&
      grant.principals.some(principal => ["window", "remote_page"].includes(principal.kind)) &&
      grant.scopes.every(scope => scope.kind !== "transport" || scope.value === "moonview"))
      .flatMap(grant => grant.commands);
    const generatedSdk = await import(new URL("orbit-bindings.mjs", base));
    assert.deepEqual(Object.keys(generatedSdk.commands).sort(), [...new Set(candidates)].sort());
    for (const command of candidates) assert.ok(types.includes(`${JSON.stringify(command)}:`));
  }
});

function host() {
  const handlers = new Set();
  const calls = [];
  return {
    handlers, calls,
    invoke(command, payload, options) {
      calls.push({ command, payload, options });
      return Promise.resolve(payload);
    },
    listen(name, handler) { handlers.add(handler); return () => handlers.delete(handler); },
    emit(payload) { for (const handler of [...handlers]) handler({ name: "changed", payload, source: null, target: null }); },
  };
}

test("generated client supports commands and late host discovery without global writes", async () => {
  const client = sdk.createClient();
  assert.equal(client.isAvailable(), false);
  await assert.rejects(client.invoke("app.echo"), { code: "ipc_unavailable" });
  const bridge = host();
  globalThis.__ORBIT__ = bridge;
  try {
    assert.equal(client.isAvailable(), true);
    assert.equal(await client.commands["app.echo"](7), 7);
    assert.equal(await sdk.invoke("app.echo", 8), 8);
  } finally { delete globalThis.__ORBIT__; client.dispose(); }
});

test("injected clients do not consult a global host", async () => {
  const first = host();
  const second = host();
  const a = sdk.createClient({ bridge: first });
  const b = sdk.createClient({ bridge: second });
  assert.equal(await a.commands["app.echo"](1), 1);
  assert.equal(await b.commands["app.echo"](2), 2);
  assert.equal(first.calls.length, 1);
  assert.equal(second.calls.length, 1);
});

test("host failures become inspectable OrbitIpcError instances", async () => {
  const client = sdk.createClient({ bridge: { invoke: () => Promise.reject({ code: "permission_denied", message: "Denied", data: { command: "app.echo" } }) } });
  await assert.rejects(client.invoke("app.echo"), error => error instanceof sdk.OrbitIpcError && error.code === "permission_denied" && error.data.command === "app.echo");
  const broken = sdk.createClient({ bridge: { invoke: () => { throw new Error("offline"); } } });
  await assert.rejects(broken.invoke("app.echo"), { code: "transport_failed", message: "offline" });
});

test("subscriptions support once, abort, independent listeners and disposal", () => {
  const bridge = host();
  const client = sdk.createClient({ bridge });
  const values = [];
  const controller = new AbortController();
  const off = client.listen("changed", event => values.push(event.payload), { signal: controller.signal });
  client.once("changed", event => values.push(event.payload * 10));
  bridge.emit(1);
  bridge.emit(2);
  assert.deepEqual(values, [1, 10, 2]);
  controller.abort();
  off();
  assert.equal(bridge.handlers.size, 0);
  client.listen("changed", () => {}, { signal: AbortSignal.abort() });
  assert.equal(bridge.handlers.size, 0);
  client.listen("changed", () => {});
  client.dispose();
  client.dispose();
  assert.equal(bridge.handlers.size, 0);
  assert.throws(() => client.listen("changed", () => {}), { code: "client_disposed" });
  assert.equal(client.isAvailable(), false);
});

test("client disposal aborts only its own calls", async () => {
  const bridge = host();
  bridge.invoke = (_, __, { signal }) => new Promise((resolve, reject) => {
    bridge.calls.push({ signal, resolve });
    signal.addEventListener("abort", () => reject({ code: "cancelled", message: "Cancelled" }), { once: true });
  });
  const first = sdk.createClient({ bridge });
  const second = sdk.createClient({ bridge });
  const a = first.invoke("app.echo");
  const b = second.invoke("app.echo");
  const rejected = assert.rejects(a, { code: "cancelled" });
  first.dispose();
  await rejected;
  assert.equal(bridge.calls[1].signal.aborted, false);
  bridge.calls[1].resolve(9);
  assert.equal(await b, 9);
  await assert.rejects(first.invoke("app.echo"), { code: "client_disposed" });
});

test("caller abort is forwarded and pre-aborted calls never reach the host", async () => {
  const bridge = host();
  bridge.invoke = (_, __, { signal }) => new Promise((resolve, reject) => {
    signal.addEventListener("abort", () => reject({ code: "cancelled", message: "Cancelled" }), { once: true });
  });
  const client = sdk.createClient({ bridge });
  const controller = new AbortController();
  const pending = client.invoke("app.echo", {}, { signal: controller.signal });
  const rejected = assert.rejects(pending, { code: "cancelled" });
  controller.abort();
  await rejected;
  await assert.rejects(client.invoke("app.echo", {}, { signal: AbortSignal.abort() }), { code: "cancelled" });
  await assert.rejects(client.invoke("app.echo", {}, { signal: {} }), { code: "invalid_signal" });
});

test("once subscriptions clean up even when an injected host delivers synchronously", () => {
  let removed = 0;
  let received = 0;
  const client = sdk.createClient({ bridge: { listen: (_, handler) => {
    handler({ name: "changed", payload: 1 });
    return () => removed++;
  } } });
  const off = client.once("changed", () => received++);
  off();
  client.dispose();
  assert.equal(received, 1);
  assert.equal(removed, 1);
});

test("client cancellation settles even when an older host ignores signals", async () => {
  let finish;
  const client = sdk.createClient({ bridge: { invoke: () => new Promise(resolve => { finish = resolve; }) } });
  const pending = client.invoke("app.echo");
  const rejected = assert.rejects(pending, { code: "cancelled" });
  client.dispose();
  await rejected;
  finish(1);
  await assert.rejects(pending, { code: "cancelled" });
});

test("contract-backed generated clients validate request and response JSON", async () => {
  const module = await import(new URL("../../orbit-example/orbit-bindings.mjs", import.meta.url));
  const handlers = new Set();
  const client = module.createClient({ bridge: { invoke: async (_, payload) => {
    assert.equal(payload, null);
    return { message: "ok" };
  }, listen: (_, handler) => { handlers.add(handler); return () => handlers.delete(handler); } } });
  assert.deepEqual(await client.commands["example.ping"](), { message: "ok" });
  await assert.rejects(client.commands["example.ping"]({ value: 1 }), { code: "invalid_payload" });
  const invalid = module.createClient({ bridge: { invoke: async () => ({ message: 1 }) } });
  await assert.rejects(invalid.commands["example.ping"](), { code: "invalid_response" });
  const revisions = [];
  client.listen("app.changed", event => revisions.push(event.payload.revision));
  for (const handler of handlers) handler({ name: "app.changed", payload: { revision: 2 }, source: null, target: null });
  assert.deepEqual(revisions, [2]);
  for (const handler of handlers) assert.throws(() => handler({ name: "app.changed", payload: { revision: "two" }, source: null, target: null }), { code: "invalid_event" });
});
