import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

// Reuse the reference application's pinned compiler; no second TypeScript dependency.
const compiler = fileURLToPath(new URL("../../examples/react-memo/node_modules/typescript/bin/tsc", import.meta.url));
const fixture = fileURLToPath(new URL("../fixtures/bindings.mts", import.meta.url));
const result = spawnSync(process.execPath, [compiler, "--noEmit", "--strict", "--module", "nodenext", "--target", "ES2022", fixture], { stdio: "inherit" });
if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
