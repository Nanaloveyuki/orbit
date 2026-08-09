import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { test } from "node:test";
import { gunzipSync } from "node:zlib";
import {
  archiveDescriptor,
  archiveMetadataPath,
  buildLinuxArchive,
  compatibilityProfile,
  createLinuxArchive,
  createNsisScript,
  expandArchiveSigningCommand,
  expandSigningCommand,
  installerDescriptor,
  installerMetadataPath,
  moonCommands,
  packageDescriptor,
  packageMetadataCommand,
  packageIntegrity,
  parseInvocation,
  verifyInstaller,
  verifyArchive,
  verifyPackage,
  viteWorkflowCommand,
  windowsToolCacheDirectory,
} from "../src/cli.mjs";

function tarEntryNames(archive) {
  const contents = gunzipSync(readFileSync(archive));
  const names = [];
  let offset = 0;
  while (offset + 512 <= contents.length && contents[offset] !== 0) {
    const field = (start, length) => contents.subarray(offset + start, offset + start + length)
      .toString("utf8").replace(/\0.*$/, "");
    const prefix = field(345, 155);
    const name = field(0, 100);
    names.push(prefix.length === 0 ? name : `${prefix}/${name}`);
    const size = Number.parseInt(field(124, 12).trim() || "0", 8);
    offset += 512 + Math.ceil(size / 512) * 512;
  }
  return names;
}

function createLinuxPackage(directory) {
  mkdirSync(join(directory, "bin"), { recursive: true });
  writeFileSync(join(directory, "bin", "orbit-example"), "linux application");
  const manifest = {
    format: 3,
    compatibility: { ...compatibilityProfile },
    target: { platform: "linux", arch: "x64" },
    configuration: { schemaVersion: 2, fingerprint: "f00d" },
    application: {
      identifier: "dev.orbit.example",
      name: "Orbit Example",
      version: "0.1.0",
    },
    executable: "bin/orbit-example",
    plugins: null,
    pluginDeclarations: [],
  };
  manifest.integrity = packageIntegrity(directory);
  writeFileSync(join(directory, "orbit-package.json"), `${JSON.stringify(manifest)}\n`);
  return manifest;
}

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
    compatibility: { ...compatibilityProfile },
    application: {
      identifier: "dev.orbit.example",
      name: "Orbit Example",
      version: "0.1.0",
      product_name: null,
      publisher: null,
    },
    windows: { webview_install_mode: "embed_bootstrapper" },
    plugins: [],
  }, resolve(cwd, "app/orbit-example.exe"), true);
  assert.equal(descriptor.format, 3);
  assert.deepEqual(descriptor.compatibility, compatibilityProfile);
  assert.equal(descriptor.configuration.fingerprint, "f00d");
  assert.equal(descriptor.executable, "bin/orbit-example.exe");
  assert.equal(descriptor.executableDiscovered, true);
  assert.equal(descriptor.windows.webview_install_mode, "embed_bootstrapper");
  assert.deepEqual(descriptor.plugins, null);
  assert.equal(descriptor.target.platform, process.platform);
  assert.equal(descriptor.target.arch, process.arch);
});

test("package verification enforces compatibility before integrity", (context) => {
  const packageDirectory = mkdtempSync(join(tmpdir(), "orbit-package-"));
  context.after(() => rmSync(packageDirectory, { recursive: true, force: true }));
  mkdirSync(join(packageDirectory, "bin"));
  writeFileSync(join(packageDirectory, "bin", "app.exe"), "original");
  const manifest = {
    format: 3,
    compatibility: { ...compatibilityProfile },
    target: { platform: process.platform, arch: process.arch },
    configuration: { schemaVersion: 2, fingerprint: "f00d" },
    executable: "bin/app.exe",
    plugins: null,
    pluginDeclarations: [],
    application: { identifier: "dev.orbit.example" },
  };
  const writeManifest = () => {
    manifest.integrity = packageIntegrity(packageDirectory);
    writeFileSync(join(packageDirectory, "orbit-package.json"), `${JSON.stringify(manifest)}\n`);
  };
  writeManifest();
  assert.equal(verifyPackage(packageDirectory).format, 3);

  manifest.compatibility.moonview = "0.0.0";
  writeManifest();
  assert.throws(() => verifyPackage(packageDirectory), /incompatible: moonview/);
  manifest.compatibility.moonview = compatibilityProfile.moonview;
  writeManifest();

  manifest.executable = "orbit-package.json";
  writeManifest();
  assert.throws(() => verifyPackage(packageDirectory), /incomplete or incompatible/);
  manifest.executable = "bin/app.exe";
  writeManifest();

  writeFileSync(join(packageDirectory, "bin", "app.exe"), "modified");
  assert.throws(() => verifyPackage(packageDirectory), /integrity verification failed/);

  writeFileSync(join(packageDirectory, "bin", "app.exe"), "original");
  writeFileSync(join(packageDirectory, "unexpected.txt"), "unexpected");
  assert.throws(() => verifyPackage(packageDirectory), /integrity verification failed/);
});

test("package verification rejects incompatible plugin sidecars", (context) => {
  const packageDirectory = mkdtempSync(join(tmpdir(), "orbit-plugin-package-"));
  context.after(() => rmSync(packageDirectory, { recursive: true, force: true }));
  mkdirSync(join(packageDirectory, "bin"));
  mkdirSync(join(packageDirectory, "plugins"));
  writeFileSync(join(packageDirectory, "bin", "app.exe"), "application");
  writeFileSync(join(packageDirectory, "plugins", "demo.dll"), "plugin");
  const platform = process.platform === "win32" ? "windows" : process.platform === "darwin" ? "macos" : "linux";
  const sidecar = {
    schema_version: 2,
    abi_version: 1,
    id: "demo.echo",
    platforms: [platform],
  };
  const sidecarPath = join(packageDirectory, "plugins", "demo.json");
  const manifest = {
    format: 3,
    compatibility: { ...compatibilityProfile },
    target: { platform: process.platform, arch: process.arch },
    configuration: { schemaVersion: 2, fingerprint: "f00d" },
    executable: "bin/app.exe",
    plugins: "plugins",
    pluginDeclarations: [{ id: "demo.echo", library: "plugins/demo.dll", manifest: "plugins/demo.json" }],
  };
  const writeManifest = () => {
    manifest.integrity = packageIntegrity(packageDirectory);
    writeFileSync(join(packageDirectory, "orbit-package.json"), `${JSON.stringify(manifest)}\n`);
  };
  writeFileSync(sidecarPath, `${JSON.stringify(sidecar)}\n`);
  writeManifest();
  assert.equal(verifyPackage(packageDirectory).plugins, "plugins");

  sidecar.abi_version = 2;
  writeFileSync(sidecarPath, `${JSON.stringify(sidecar)}\n`);
  writeManifest();
  assert.equal(verifyPackage(packageDirectory).plugins, "plugins");

  sidecar.abi_version = 3;
  writeFileSync(sidecarPath, `${JSON.stringify(sidecar)}\n`);
  writeManifest();
  assert.throws(() => verifyPackage(packageDirectory), /plugin sidecar is incompatible/);
});

test("installer requires explicit signing policy and creates a current-user NSIS script", () => {
  const cwd = resolve("workspace");
  assert.throws(
    () => parseInvocation([
      "installer",
      "--package-dir",
      "package",
    ], cwd),
    /requires --sign-command <command> or --allow-unsigned/,
  );
  const invocation = parseInvocation([
    "installer",
    "--package-dir",
    "package",
    "--allow-unsigned",
  ], cwd);
  assert.equal(invocation.allowUnsigned, true);
  assert.equal(invocation.webview2Bootstrapper, undefined);
  assert.match(windowsToolCacheDirectory(), /\.orbit[\\/]tools[\\/]windows$/);
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

test("NSIS scripts implement each configured Evergreen WebView2 mode", () => {
  const base = {
    installer: resolve("dist/dev.orbit.example-0.1.0-setup.exe"),
    packageDirectory: resolve("package"),
    bootstrapper: resolve("webview2.exe"),
    application: {
      identifier: "dev.orbit.example",
      name: "Orbit Example",
      version: "0.1.0",
      product_name: null,
    },
  };
  const downloaded = createNsisScript({
    ...base,
    webviewInstallMode: "download_bootstrapper",
  });
  assert.match(downloaded, /NSISdl::download/);
  assert.match(downloaded, /WebView2 Runtime download failed/);
  assert.doesNotMatch(downloaded, /File \/oname=webview2-bootstrapper\.exe/);

  const offline = createNsisScript({
    ...base,
    webviewInstallMode: "offline_installer",
  });
  assert.match(offline, /File \/oname=webview2-offline-installer\.exe/);
  assert.match(offline, /webview2-offline-installer\.exe" \/silent \/install/);

  const skipped = createNsisScript({
    ...base,
    webviewInstallMode: "skip",
  });
  assert.doesNotMatch(skipped, /WebView2 Runtime installation failed/);
  assert.doesNotMatch(skipped, /InitPluginsDir/);
  assert.throws(
    () => createNsisScript({ ...base, webviewInstallMode: "fixed_runtime" }),
    /unsupported WebView2 install mode/,
  );
});

test("installer metadata verifies its artifact and signing commands require all paths", (context) => {
  const directory = mkdtempSync(join(tmpdir(), "orbit-installer-"));
  context.after(() => rmSync(directory, { recursive: true, force: true }));
  const installer = join(directory, "dev.orbit.example-0.1.0-setup.exe");
  writeFileSync(installer, "installer bytes");
  const packageManifest = {
    format: 3,
    compatibility: { ...compatibilityProfile },
    target: { platform: "win32", arch: "x64" },
    configuration: { schemaVersion: 2, fingerprint: "f00d" },
    windows: { webview_install_mode: "skip" },
    application: { identifier: "dev.orbit.example", name: "Orbit Example", version: "0.1.0" },
    integrity: { algorithm: "sha256" },
  };
  writeFileSync(installerMetadataPath(installer), `${JSON.stringify(
    installerDescriptor(packageManifest, installer, false),
  )}\n`);
  assert.equal(verifyInstaller(installer).signed, false);
  assert.equal(verifyInstaller(installer).package.windows.webview_install_mode, "skip");
  const legacyDescriptor = installerDescriptor(
    { ...packageManifest, windows: undefined },
    installer,
    false,
  );
  assert.equal(
    legacyDescriptor.package.windows.webview_install_mode,
    "embed_bootstrapper",
  );
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

test("Linux archives require explicit signing policy and preserve a verified package", async (context) => {
  const directory = mkdtempSync(join(tmpdir(), "orbit-linux-archive-"));
  context.after(() => rmSync(directory, { recursive: true, force: true }));
  const packageDirectory = join(directory, "package");
  const manifest = createLinuxPackage(packageDirectory);
  assert.throws(
    () => parseInvocation(["archive", "--package-dir", "package"], directory),
    /requires --sign-command <command> or --allow-unsigned/,
  );
  const invocation = parseInvocation([
    "archive",
    "--package-dir",
    "package",
    "--out-dir",
    "artifacts",
    "--allow-unsigned",
  ], directory);
  const result = await buildLinuxArchive(invocation);
  assert.match(result.archive, /dev\.orbit\.example-0\.1\.0-linux-x64\.tar\.gz$/);
  assert.equal(verifyArchive(result.archive).signed, false);
  assert.deepEqual(tarEntryNames(result.archive), [
    "dev.orbit.example-0.1.0/",
    "dev.orbit.example-0.1.0/run",
    "dev.orbit.example-0.1.0/orbit-package/",
    "dev.orbit.example-0.1.0/orbit-package/bin/",
    "dev.orbit.example-0.1.0/orbit-package/orbit-package.json",
    "dev.orbit.example-0.1.0/orbit-package/bin/orbit-example",
  ]);
  const copy = join(directory, "copy.tar.gz");
  createLinuxArchive(packageDirectory, copy, manifest);
  assert.deepEqual(readFileSync(copy), readFileSync(result.archive));
  const nestedOutput = parseInvocation([
    "archive",
    "--package-dir",
    "package",
    "--out-dir",
    "package/artifacts",
    "--allow-unsigned",
  ], directory);
  await assert.rejects(
    () => buildLinuxArchive(nestedOutput),
    /output directory must not be inside the package directory/,
  );
  const signedInvocation = parseInvocation([
    "archive",
    "--package-dir",
    "package",
    "--out-dir",
    "signed-artifacts",
    "--sign-command",
    "node -e \"require('node:fs').writeFileSync(process.argv[1] + '.sig', 'signature')\" {archive} {package_dir} {package_manifest}",
  ], directory);
  const signed = await buildLinuxArchive(signedInvocation);
  assert.equal(verifyArchive(signed.archive).signed, true);
  assert.deepEqual(readFileSync(`${signed.archive}.sig`, "utf8"), "signature");
  const modifyingInvocation = parseInvocation([
    "archive",
    "--package-dir",
    "package",
    "--out-dir",
    "modified-artifacts",
    "--sign-command",
    "node -e \"require('node:fs').appendFileSync(process.argv[1], 'x')\" {archive} {package_dir} {package_manifest}",
  ], directory);
  await assert.rejects(
    () => buildLinuxArchive(modifyingInvocation),
    /sign-command must not modify the archive/,
  );
  assert.match(
    gunzipSync(readFileSync(result.archive)).toString("utf8"),
    /cd "\$root\/orbit-package"/,
  );
  writeFileSync(result.archive, "modified archive");
  assert.throws(() => verifyArchive(result.archive), /archive integrity verification failed/);
});

test("Linux archive metadata validates target and archive signing placeholders", async (context) => {
  const directory = mkdtempSync(join(tmpdir(), "orbit-linux-archive-metadata-"));
  context.after(() => rmSync(directory, { recursive: true, force: true }));
  const archive = join(directory, "dev.orbit.example-0.1.0-linux-x64.tar.gz");
  writeFileSync(archive, "archive bytes");
  const manifest = createLinuxPackage(join(directory, "package"));
  writeFileSync(archiveMetadataPath(archive), `${JSON.stringify(
    archiveDescriptor(manifest, archive, true),
  )}\n`);
  assert.equal(verifyArchive(archive).signed, true);
  assert.match(
    expandArchiveSigningCommand("sign {archive} {package_dir} {package_manifest}", {
      archive,
      packageDirectory: directory,
      packageManifest: join(directory, "orbit-package.json"),
    }),
    /sign/,
  );
  assert.throws(
    () => expandArchiveSigningCommand("sign {archive}", {
      archive,
      packageDirectory: directory,
      packageManifest: "manifest",
    }),
    /must include \{package_dir\}/,
  );
  const nonLinux = { ...manifest, target: { platform: "win32", arch: "x64" } };
  writeFileSync(archiveMetadataPath(archive), `${JSON.stringify(
    archiveDescriptor(nonLinux, archive, false),
  )}\n`);
  assert.throws(() => verifyArchive(archive), /incomplete or incompatible/);

  const invalidVersionPackage = join(directory, "invalid-version-package");
  const invalidVersion = createLinuxPackage(invalidVersionPackage);
  invalidVersion.application.version = "../invalid";
  writeFileSync(
    join(invalidVersionPackage, "orbit-package.json"),
    `${JSON.stringify(invalidVersion)}\n`,
  );
  const invalidVersionInvocation = parseInvocation([
    "archive",
    "--package-dir",
    "invalid-version-package",
    "--out-dir",
    "artifacts",
    "--allow-unsigned",
  ], directory);
  await assert.rejects(
    () => buildLinuxArchive(invalidVersionInvocation),
    /application version must use ASCII letters/,
  );
});
