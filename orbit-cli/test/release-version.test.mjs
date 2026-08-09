import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { acceptsMooncakeDryRunResult } from "../scripts/mooncake-dry-run.mjs";

const repository = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const script = resolve(repository, "orbit-cli", "scripts", "verify-release-version.mjs");
const version = JSON.parse(readFileSync(resolve(repository, "orbit-cli", "package.json"), "utf8")).version;

test("release version check binds the tag, MoonBit module, and npm package", () => {
  const accepted = spawnSync(process.execPath, [script, repository, `v${version}`], { encoding: "utf8" });
  assert.equal(accepted.status, 0, accepted.stderr);
  assert.equal(accepted.stdout.trim(), version);

  const rejected = spawnSync(process.execPath, [script, repository, "v0.0.0-invalid"], { encoding: "utf8" });
  assert.notEqual(rejected.status, 0);
  assert.match(rejected.stderr, /must equal/);
});

test("Mooncake dry-run accepts only the known successful 202 response", () => {
  const success = "Server status: 202 Accepted\nDry run completed successfully. No changes were made.";
  assert.equal(acceptsMooncakeDryRunResult(0, ""), true);
  assert.equal(acceptsMooncakeDryRunResult(1, success), true);
  assert.equal(acceptsMooncakeDryRunResult(1, "Server status: 202 Accepted"), false);
  assert.equal(acceptsMooncakeDryRunResult(2, success), false);
});
