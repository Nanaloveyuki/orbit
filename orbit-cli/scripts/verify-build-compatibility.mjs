import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { compatibilityProfile } from "../src/cli.mjs";

const repository = fileURLToPath(new URL("../../", import.meta.url));
const result = spawnSync("moon", [
  "run", "--target", "native", "orbit-build", "package-metadata",
  "orbit-example/orbit.conf.json",
], { cwd: repository, encoding: "utf8" });
if (result.error) throw result.error;
assert.equal(result.status, 0, result.stderr);
const metadata = JSON.parse(result.stdout);
assert.deepEqual(metadata.compatibility, compatibilityProfile,
  "compiled orbit-build and CLI compatibility profiles must agree");
process.stdout.write("Compiled generator and CLI compatibility profiles agree.\n");
