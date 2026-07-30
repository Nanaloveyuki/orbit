import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { test } from "node:test";
import {
  createNsisScript,
  expandSigningCommand,
  installerDescriptor,
  installerMetadataPath,
  moonCommands,
  packageDescriptor,
  packageMetadataCommand,
  packageIntegrity,
  parseInvocation,
  verifyInstaller,
  verifyPackage,
  viteWorkflowCommand,
} from "../src/cli.mjs";

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

test("bindings default to an inspectable JavaScript module beside the configuration", () => {
  const cwd = resolve("workspace");
  const invocation = parseInvocation(["bindings", "--config", "app/orbit.conf.json"], cwd);
  assert.equal(invocation.output, resolve(cwd, "app/orbit-bindings.mjs"));
  assert.deepEqual(moonCommands(invocation), [[
    "run",
    "--target",
    "native",
    "orbit-build",
    "bindings",
    resolve(cwd, "app/orbit.conf.json"),
    resolve(cwd, "app/orbit-bindings.mjs"),
  ]]);
});

test("icon generation requires a source and passes explicit output settings", () => {
  const cwd = resolve("workspace");
  assert.throws(() => parseInvocation(["icon"], cwd), /icon requires --source/);
  assert.throws(
    () => parseInvocation(["icon", "--source", "icon.png", "--compression", "10"], cwd),
    /--compression must be an integer between 0 and 9/,
  );
  const invocation = parseInvocation([
    "icon",
    "--source",
    "assets/app.png",
    "--out-dir",
    "artifacts/icons",
    "--compression",
    "9",
  ], cwd);
  assert.deepEqual(moonCommands(invocation), [[
    "run",
    "--target",
    "native",
    "orbit-build",
    "icon",
    resolve(cwd, "assets/app.png"),
    resolve(cwd, "artifacts/icons"),
    "9",
  ]]);
});

test("package metadata stays in orbit-build and the package descriptor records compatibility", () => {
  const cwd = resolve("workspace");
  const invocation = parseInvocation([
    "package",
    "--config",
    "app/orbit.conf.json",
  ], cwd);
  assert.equal(invocation.binary, undefined);
  assert.deepEqual(packageMetadataCommand(invocation), [
    "run",
    "--target",
    "native",
    "orbit-build",
    "package-metadata",
    resolve(cwd, "app/orbit.conf.json"),
  ]);
  const descriptor = packageDescriptor({
    schema_version: 2,
    configuration_fingerprint: "f00d",
    application: {
      identifier: "dev.orbit.example",
      name: "Orbit Example",
      version: "0.1.0",
      product_name: null,
      publisher: null,
    },
    plugins: [],
  }, resolve(cwd, "app/orbit-example.exe"), true);
  assert.equal(descriptor.format, 2);
  assert.equal(descriptor.configuration.fingerprint, "f00d");
  assert.equal(descriptor.executable, "bin/orbit-example.exe");
  assert.equal(descriptor.executableDiscovered, true);
  assert.deepEqual(descriptor.plugins, null);
  assert.equal(descriptor.target.platform, process.platform);
  assert.equal(descriptor.target.arch, process.arch);
});

test("package integrity rejects modified and undeclared payload files", (context) => {
  const packageDirectory = mkdtempSync(join(tmpdir(), "orbit-package-"));
  context.after(() => rmSync(packageDirectory, { recursive: true, force: true }));
  mkdirSync(join(packageDirectory, "bin"));
  writeFileSync(join(packageDirectory, "bin", "app.exe"), "original");
  writeFileSync(join(packageDirectory, "orbit-package.json"), `${JSON.stringify({
    format: 2,
    application: { identifier: "dev.orbit.example" },
    integrity: packageIntegrity(packageDirectory),
  })}\n`);
  assert.equal(verifyPackage(packageDirectory).format, 2);

  writeFileSync(join(packageDirectory, "bin", "app.exe"), "modified");
  assert.throws(() => verifyPackage(packageDirectory), /integrity verification failed/);

  writeFileSync(join(packageDirectory, "bin", "app.exe"), "original");
  writeFileSync(join(packageDirectory, "unexpected.txt"), "unexpected");
  assert.throws(() => verifyPackage(packageDirectory), /integrity verification failed/);
});

test("installer requires explicit signing policy and creates a current-user NSIS script", () => {
  const cwd = resolve("workspace");
  assert.throws(
    () => parseInvocation([
      "installer",
      "--package-dir",
      "package",
      "--webview2-bootstrapper",
      "webview2.exe",
    ], cwd),
    /requires --sign-command <command> or --allow-unsigned/,
  );
  const invocation = parseInvocation([
    "installer",
    "--package-dir",
    "package",
    "--webview2-bootstrapper",
    "webview2.exe",
    "--allow-unsigned",
  ], cwd);
  assert.equal(invocation.allowUnsigned, true);
  const script = createNsisScript({
    installer: resolve(cwd, "dist/dev.orbit.example-0.1.0-setup.exe"),
    packageDirectory: resolve(cwd, "package"),
    bootstrapper: resolve(cwd, "webview2.exe"),
    application: {
      identifier: "dev.orbit.example",
      name: "Orbit Example",
      version: "0.1.0",
      product_name: null,
    },
  });
  assert.match(script, /RequestExecutionLevel user/);
  assert.match(script, /\$LOCALAPPDATA\\dev\.orbit\.example/);
  assert.match(script, /webview2-bootstrapper\.exe" \/silent \/install/);
  assert.match(script, /File \/r/);
  assert.match(script, /WriteUninstaller/);
  assert.match(script, /DeleteRegKey HKCU/);
});

test("installer metadata verifies its artifact and signing commands require all paths", (context) => {
  const directory = mkdtempSync(join(tmpdir(), "orbit-installer-"));
  context.after(() => rmSync(directory, { recursive: true, force: true }));
  const installer = join(directory, "dev.orbit.example-0.1.0-setup.exe");
  writeFileSync(installer, "installer bytes");
  const packageManifest = {
    format: 2,
    orbit: "0.1.0-alpha.1",
    moonview: "0.1.0-beta.3",
    pluginAbi: 1,
    target: { platform: "win32", arch: "x64" },
    configuration: { schemaVersion: 2, fingerprint: "f00d" },
    application: { identifier: "dev.orbit.example", name: "Orbit Example", version: "0.1.0" },
    integrity: { algorithm: "sha256" },
  };
  writeFileSync(installerMetadataPath(installer), `${JSON.stringify(
    installerDescriptor(packageManifest, installer, false),
  )}\n`);
  assert.equal(verifyInstaller(installer).signed, false);
  assert.match(
    expandSigningCommand("sign {installer} {package_dir} {package_manifest}", {
      installer,
      packageDirectory: directory,
      packageManifest: join(directory, "orbit-package.json"),
    }),
    /sign/,
  );
  assert.throws(
    () => expandSigningCommand("sign {installer}", { installer, packageDirectory: directory, packageManifest: "manifest" }),
    /must include \{package_dir\}/,
  );

  writeFileSync(installer, "modified installer bytes");
  assert.throws(() => verifyInstaller(installer), /installer integrity verification failed/);
});
