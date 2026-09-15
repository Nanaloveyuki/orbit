import { createClient, invoke, commands, type CommandDefinition, type OrbitEvent } from "../../orbit-example/orbit-bindings.mjs";

interface AppCommands {
  "example.ping": CommandDefinition<{ value: number }, { message: string }>;
}
interface AppEvents { changed: { revision: number }; }
const client = createClient<AppCommands, AppEvents>();
const result: Promise<{ message: string }> = client.commands["example.ping"]({ value: 1 });
const same: typeof result = client.invoke("example.ping", { value: 2 }, { signal: new AbortController().signal });
client.listen("changed", event => { const revision: number = event.payload.revision; void revision; });
client.once("changed", (event: OrbitEvent<{ revision: number }>) => { void event; });
client.dispose();
void same;
// @ts-expect-error unknown command
client.invoke("missing", {});
// @ts-expect-error request is required
client.invoke("example.ping");
// @ts-expect-error invalid payload
client.commands["example.ping"]({ value: "one" });
// @ts-expect-error invalid result
const wrong: Promise<number> = client.invoke("example.ping", { value: 1 });
// @ts-expect-error unknown event
client.listen("missing", () => {});
// @ts-expect-error contract names must occur in the generated command list
createClient<{ missing: CommandDefinition }>();
// No application contract is inferred from a permission grant.
const untyped: Promise<unknown> = commands["example.ping"]();
const raw: Promise<unknown> = invoke("dynamic.command");
void untyped; void raw; void wrong;
