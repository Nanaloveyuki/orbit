import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { acceptsMooncakeDryRunResult } from "../scripts/mooncake-dry-run.mjs";
import { npmDistTag } from "../scripts/npm-dist-tag.mjs";

const repository = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const script = resolve(repository, "orbit-cli", "scripts", "verify-release-version.mjs");
const npmManifest = JSON.parse(readFileSync(resolve(repository, "orbit-cli", "package.json"), "utf8"));
const releaseWorkflow = readFileSync(resolve(repository, ".github", "workflows", "release.yml"), "utf8");
const version = npmManifest.version;

test("release version check binds the tag, MoonBit module, and npm package", () => {
  const accepted = spawnSync(process.execPath, [script, repository, `v${version}`], { encoding: "utf8" });
  assert.equal(accepted.status, 0, accepted.stderr);
  assert.equal(accepted.stdout.trim(), version);

  const rejected = spawnSync(process.execPath, [script, repository, "v0.0.0-invalid"], { encoding: "utf8" });
  assert.notEqual(rejected.status, 0);
  assert.match(rejected.stderr, /must equal/);
});

test("npm publication identifies the canonical GitHub repository", () => {
  assert.deepEqual(npmManifest.repository, {
    type: "git",
    url: "https://github.com/Nanaloveyuki/orbit.git",
    directory: "orbit-cli",
  });
});

test("release publishes the npm artifact through an explicit relative path", () => {
  assert.match(releaseWorkflow, /npm publish \.\/release\/\*\.tgz --access public --provenance --tag/);
});

test("npm dist-tags follow the release channel", () => {
  assert.equal(npmDistTag("0.1.0-alpha.1"), "alpha");
  assert.equal(npmDistTag("0.1.0-RC.2"), "rc");
  assert.equal(npmDistTag("0.1.0-1"), "next");
  assert.equal(npmDistTag("0.1.0"), "latest");
  assert.throws(() => npmDistTag("not-a-version"), /invalid release version/);
});

test("Mooncake dry-run accepts only the known successful 202 response", () => {
  const success = "Server status: 202 Accepted\nDry run completed successfully. No changes were made.";
  assert.equal(acceptsMooncakeDryRunResult(0, ""), true);
  assert.equal(acceptsMooncakeDryRunResult(1, success), true);
  assert.equal(acceptsMooncakeDryRunResult(255, success), true);
  assert.equal(acceptsMooncakeDryRunResult(1, "Server status: 202 Accepted"), false);
  assert.equal(acceptsMooncakeDryRunResult(null, success), false);
});
