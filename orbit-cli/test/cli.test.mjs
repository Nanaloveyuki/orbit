import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { test } from "node:test";
import { moonCommands, parseInvocation } from "../src/cli.mjs";

test("generate defaults output and package to the configuration directory", () => {
  const cwd = resolve("workspace");
  const config = resolve(cwd, "example/orbit.conf.json");
  const invocation = parseInvocation(["generate", "--config", "example/orbit.conf.json"], cwd);
  assert.equal(invocation.workspace, cwd);
  assert.equal(invocation.config, config);
  assert.equal(invocation.output, resolve(dirname(config), "generated_page.mbt"));
  assert.equal(invocation.packagePath, dirname(config));
  assert.deepEqual(moonCommands(invocation), [[
    "run",
    "--target",
    "native",
    "orbit-build",
    config,
    resolve(dirname(config), "generated_page.mbt"),
  ]]);
});

test("build generates before compiling the configured package", () => {
  const cwd = resolve("repo/orbit");
  const invocation = parseInvocation([
    "build",
    "--config",
    "orbit-example/orbit.conf.json",
    "--orbit-build",
    "tools/orbit-build",
  ], cwd);
  const commands = moonCommands(invocation);
  assert.deepEqual(commands[0].slice(0, 4), ["run", "--target", "native", "tools/orbit-build"]);
  assert.deepEqual(commands[1], [
    "run",
    "--target",
    "native",
    "--build-only",
    resolve(cwd, "orbit-example"),
  ]);
});

test("unknown options are rejected before spawning Moon", () => {
  assert.throws(
    () => parseInvocation(["dev", "--unsafe"], resolve("workspace")),
    /unknown option: --unsafe/,
  );
});
