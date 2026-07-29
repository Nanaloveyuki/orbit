import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { test } from "node:test";
import { moonCommands, parseInvocation, viteWorkflowCommand } from "../src/cli.mjs";

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

test("run and diagnose map to the expected Moon workflows", () => {
  const cwd = resolve("workspace");
  const run = parseInvocation(["run", "--plugin-dir", "dev-plugins"], cwd);
  assert.equal(run.pluginDir, resolve(cwd, "dev-plugins"));
  assert.deepEqual(moonCommands(run).at(-1), ["run", "--target", "native", resolve(cwd, ".")]);
  const diagnose = parseInvocation(["diagnose", "--json"], cwd);
  assert.deepEqual(moonCommands(diagnose), [["check", "--target", "native", resolve(cwd, ".")]]);
});

test("migrate-config requires a distinct explicit output path", () => {
  const cwd = resolve("workspace");
  assert.throws(
    () => parseInvocation(["migrate-config", "--config", "orbit.conf.json"], cwd),
    /migrate-config requires --output <path>/,
  );
  assert.throws(
    () => parseInvocation([
      "migrate-config",
      "--config",
      "orbit.conf.json",
      "--output",
      "orbit.conf.json",
    ], cwd),
    /migrate-config output must differ from --config/,
  );
  const invocation = parseInvocation([
    "migrate-config",
    "--config",
    "orbit.conf.json",
    "--output",
    "orbit.v2.conf.json",
  ], cwd);
  assert.deepEqual(moonCommands(invocation), [[
    "run",
    "--target",
    "native",
    "orbit-build",
    "migrate-config",
    resolve(cwd, "orbit.conf.json"),
    resolve(cwd, "orbit.v2.conf.json"),
  ]]);
});

test("Vite development uses the explicit generator mode and workflow query", () => {
  const cwd = resolve("workspace");
  const invocation = parseInvocation(["dev", "--dev-timeout", "45000"], cwd);
  const workflow = {
    dev_command: "npm run dev",
    dev_url: "http://127.0.0.1:5173",
    build_command: "npm run build",
    dist_dir: "dist",
  };
  assert.equal(invocation.devTimeout, 45000);
  assert.deepEqual(viteWorkflowCommand(invocation), [
    "run",
    "--target",
    "native",
    "orbit-build",
    "vite-workflow",
    resolve(cwd, "orbit.conf.json"),
  ]);
  assert.deepEqual(moonCommands(invocation, workflow), [[
    "run",
    "--target",
    "native",
    "orbit-build",
    "dev",
    resolve(cwd, "orbit.conf.json"),
    resolve(cwd, "generated_page.mbt"),
  ], ["run", "--target", "native", resolve(cwd, ".")]]);
});
