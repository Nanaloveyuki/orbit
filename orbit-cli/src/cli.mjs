import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import process from "node:process";
import { gzipSync } from "node:zlib";
import {
  buildLinuxPackage,
  linuxPackageFormats,
  linuxPackageMetadataPath,
  verifyLinuxPackageArtifact,
} from "./linux-packages.mjs";

const commands = new Set(["generate", "bindings", "build", "run", "dev", "diagnose", "package", "verify-package", "installer", "verify-installer", "archive", "verify-archive", "linux-package", "verify-linux-package", "migrate-config", "icon"]);
const webviewInstallModes = new Set([
  "download_bootstrapper",
  "embed_bootstrapper",
  "offline_installer",
  "skip",
]);

export const compatibilityProfile = Object.freeze({
  orbit: "0.1.0-alpha.1",
  orby: "0.1.0-beta.3",
  moonview: "0.1.0-beta.6",
  plugin_abi: 2,
  plugin_sidecar_schema: 2,
  configuration_schema: 2,
});

const compatibilityKeys = Object.keys(compatibilityProfile);

function verifyCompatibilityProfile(profile, subject) {
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) {
    throw new Error(`${subject} does not contain a compatibility profile`);
  }
  for (const key of compatibilityKeys) {
    if (profile[key] !== compatibilityProfile[key]) {
      throw new Error(`${subject} is incompatible: ${key}`);
    }
  }
}

function packagePlatformName(platform) {
  if (platform === "win32") return "windows";
  if (platform === "darwin") return "macos";
  if (platform === "linux") return "linux";
  throw new Error(`unsupported package platform: ${platform}`);
}

export function usage() {
  return [
    "Usage: orbit <generate|bindings|build|run|dev|diagnose|package|verify-package|installer|verify-installer|archive|verify-archive|linux-package|verify-linux-package|migrate-config|icon> [options]",
    "",
    "Options:",
    "  --config <path>       Configuration file (default: orbit.conf.json)",
    "  --output <path>       Generated source, bindings, or required v2 migration destination",
    "  --package <path>      Moon package to build or run (default: config directory)",
    "  --orbit-build <path>  Moon package for the generator (default: orbit-build)",
    "  --moon <command>      Moon executable (default: moon)",
    "  --workspace <path>    Working directory for Moon (default: current directory)",
    "  --plugin-dir <path>   Development-only plugin root passed as ORBIT_PLUGIN_DIRECTORY",
    "  --json                Emit structured diagnostics for the wrapper",
    "  --binary <path>       Explicit executable copied by package (default: discover Moon native output)",
    "  --out-dir <path>      Package output directory (default: dist)",
    "  --runtime-dir <path>  Optional WebView runtime files copied by package",
    "  --release             Build the application with Moon's release profile",
    "  --package-dir <path>  Package directory verified by verify-package",
    "  --webview2-bootstrapper <path>  Local Evergreen WebView2 bootstrapper for installer",
    "  --makensis <command>  NSIS compiler (default: makensis)",
    "  --sign-command <command>  External installer or archive signing command",
    "  --allow-unsigned       Permit an unsigned installer or archive",
    "  --installer <path>    Installer verified by verify-installer",
    "  --installer-metadata <path>  Installer metadata path (default: adjacent file)",
    "  --archive <path>      Archive verified by verify-archive",
    "  --archive-metadata <path>  Archive metadata path (default: adjacent file)",
    "  --format <format>     Linux native package format: deb, rpm, or arch",
    "  --package-release <n> Linux native package revision (default: 1)",
    "  --artifact <path>     Linux native package verified by verify-linux-package",
    "  --artifact-metadata <path>  Linux package metadata path (default: adjacent file)",
    "  --dpkg-deb <command>  Debian package builder (default: dpkg-deb)",
    "  --rpmbuild <command>  RPM package builder (default: rpmbuild)",
    "  --makepkg <command>   Arch package builder (default: makepkg)",
    "  --source <path>       Required 1024x1024 PNG source for icon generation",
    "  --compression <level> PNG compression level for icon generation (0-9, default: 6)",
    "  --dev-timeout <ms>    Vite readiness timeout (default: 30000)",
    "  --help                Show this help",
  ].join("\n");
}

function optionValue(args, index, name) {
  const value = args[index + 1];
  if (!value || value.startsWith("--")) {
    throw new Error(`${name} requires a value`);
  }
  return value;
}

function resolveExecutable(cwd, value, fallback) {
  const executable = value ?? fallback;
  return executable.includes("/") || executable.includes("\\") || executable.startsWith(".")
    ? resolve(cwd, executable)
    : executable;
}

export function parseInvocation(argv, cwd = process.cwd()) {
  if (argv.length === 0 || argv[0] === "--help" || argv[0] === "-h") {
    return { help: true };
  }

  const command = argv[0];
  if (!commands.has(command)) {
    throw new Error(`unknown command: ${command}`);
  }

  const values = {};
  for (let index = 1; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--help" || argument === "-h") {
      return { help: true };
    }
    if (!argument.startsWith("--")) {
      throw new Error(`unexpected argument: ${argument}`);
    }
    const key = argument.slice(2);
    if (![
      "config",
      "output",
      "package",
      "orbit-build",
      "moon",
      "workspace",
      "plugin-dir",
      "binary",
      "out-dir",
      "runtime-dir",
      "release",
      "package-dir",
      "webview2-bootstrapper",
      "makensis",
      "sign-command",
      "allow-unsigned",
      "installer",
      "installer-metadata",
      "archive",
      "archive-metadata",
      "format",
      "package-release",
      "artifact",
      "artifact-metadata",
      "dpkg-deb",
      "rpmbuild",
      "makepkg",
      "source",
      "compression",
      "dev-timeout",
      "json",
    ].includes(key)) {
      throw new Error(`unknown option: ${argument}`);
    }
    if (["json", "allow-unsigned", "release"].includes(key)) {
      values[key] = true;
    } else {
      values[key] = optionValue(argv, index, argument);
      index += 1;
    }
  }

  const workspace = resolve(cwd, values.workspace ?? ".");
  const config = resolve(workspace, values.config ?? "orbit.conf.json");
  if (command === "migrate-config" && !values.output) {
    throw new Error("migrate-config requires --output <path>");
  }
  const output = resolve(
    workspace,
    values.output ?? `${dirname(config)}/${command === "bindings" ? "orbit-bindings.mjs" : "generated_page.mbt"}`,
  );
  if (command === "migrate-config" && output === config) {
    throw new Error("migrate-config output must differ from --config");
  }
  if (command === "icon" && !values.source) {
    throw new Error("icon requires --source <path>");
  }
  if (command === "verify-package" && !values["package-dir"]) {
    throw new Error("verify-package requires --package-dir <path>");
  }
  if (command === "installer") {
    if (!values["package-dir"]) {
      throw new Error("installer requires --package-dir <path>");
    }
    if (!values["sign-command"] && !values["allow-unsigned"]) {
      throw new Error("installer requires --sign-command <command> or --allow-unsigned");
    }
  }
  if (command === "verify-installer" && !values.installer) {
    throw new Error("verify-installer requires --installer <path>");
  }
  if (command === "archive") {
    if (!values["package-dir"]) {
      throw new Error("archive requires --package-dir <path>");
    }
    if (!values["sign-command"] && !values["allow-unsigned"]) {
      throw new Error("archive requires --sign-command <command> or --allow-unsigned");
    }
  }
  if (command === "verify-archive" && !values.archive) {
    throw new Error("verify-archive requires --archive <path>");
  }
  if (command === "linux-package") {
    if (!values["package-dir"]) {
      throw new Error("linux-package requires --package-dir <path>");
    }
    if (!linuxPackageFormats.has(values.format)) {
      throw new Error("linux-package requires --format deb, rpm, or arch");
    }
    if (!values["sign-command"] && !values["allow-unsigned"]) {
      throw new Error("linux-package requires --sign-command <command> or --allow-unsigned");
    }
  }
  if (command === "verify-linux-package" && !values.artifact) {
    throw new Error("verify-linux-package requires --artifact <path>");
  }
  const packageRelease = values["package-release"] ?? "1";
  if (!/^[1-9][0-9]*$/.test(packageRelease)) {
    throw new Error("--package-release must be a positive integer");
  }
  const compression = Number(values.compression ?? "6");
  if (!Number.isInteger(compression) || compression < 0 || compression > 9) {
    throw new Error("--compression must be an integer between 0 and 9");
  }
  const devTimeout = Number(values["dev-timeout"] ?? "30000");
  if (!Number.isInteger(devTimeout) || devTimeout < 1 || devTimeout > 300000) {
    throw new Error("--dev-timeout must be an integer between 1 and 300000");
  }
  return {
    command,
    workspace,
    config,
    output,
    packagePath: resolve(workspace, values.package ?? dirname(config)),
    orbitBuild: values["orbit-build"] ?? "orbit-build",
    moon: resolveExecutable(workspace, values.moon, "moon"),
    pluginDir: values["plugin-dir"] ? resolve(workspace, values["plugin-dir"]) : undefined,
    binary: values.binary ? resolve(workspace, values.binary) : undefined,
    outDir: resolve(workspace, values["out-dir"] ?? (command === "icon" ? "icons" : ["archive", "linux-package"].includes(command) ? "artifacts" : "dist")),
    source: values.source ? resolve(workspace, values.source) : undefined,
    compression,
    runtimeDir: values["runtime-dir"] ? resolve(workspace, values["runtime-dir"]) : undefined,
    releaseBuild: values.release ?? false,
    packageDir: values["package-dir"] ? resolve(workspace, values["package-dir"]) : undefined,
    webview2Bootstrapper: values["webview2-bootstrapper"]
      ? resolve(workspace, values["webview2-bootstrapper"])
      : undefined,
    makensis: resolveExecutable(workspace, values.makensis, "makensis"),
    makensisProvided: Boolean(values.makensis),
    signCommand: values["sign-command"],
    allowUnsigned: values["allow-unsigned"] ?? false,
    installer: values.installer ? resolve(workspace, values.installer) : undefined,
    installerMetadata: values["installer-metadata"]
      ? resolve(workspace, values["installer-metadata"])
      : undefined,
    archive: values.archive ? resolve(workspace, values.archive) : undefined,
    archiveMetadata: values["archive-metadata"]
      ? resolve(workspace, values["archive-metadata"])
      : undefined,
    format: values.format,
    packageRelease,
    artifact: values.artifact ? resolve(workspace, values.artifact) : undefined,
    artifactMetadata: values["artifact-metadata"]
      ? resolve(workspace, values["artifact-metadata"])
      : undefined,
    dpkgDeb: resolveExecutable(workspace, values["dpkg-deb"], "dpkg-deb"),
    rpmbuild: resolveExecutable(workspace, values.rpmbuild, "rpmbuild"),
    makepkg: resolveExecutable(workspace, values.makepkg, "makepkg"),
    devTimeout,
    json: values.json ?? false,
  };
}

function commandEnvironment(invocation) {
  return invocation.pluginDir
    ? { ...process.env, ORBIT_PLUGIN_DIRECTORY: invocation.pluginDir }
    : process.env;
}

function moonProcess(invocation, args) {
  if (process.platform === "win32" && /\.(cmd|bat)$/i.test(invocation.moon)) {
    return {
      command: process.env.ComSpec ?? "cmd.exe",
      args: ["/d", "/s", "/c", invocation.moon, ...args],
    };
  }
  return { command: invocation.moon, args };
}

function runMoon(invocation, args) {
  const processSpec = moonProcess(invocation, args);
  const result = spawnSync(processSpec.command, processSpec.args, {
    cwd: invocation.workspace,
    stdio: "inherit",
    env: commandEnvironment(invocation),
  });
  if (result.error) {
    throw new Error(`failed to start ${invocation.moon}: ${result.error.message}`);
  }
  if (result.status !== 0) {
    process.exitCode = result.status ?? 1;
    return false;
  }
  return true;
}

export function viteWorkflowCommand(invocation) {
  return [
    "run",
    "--target",
    "native",
    invocation.orbitBuild,
    "vite-workflow",
    invocation.config,
  ];
}

export function packageMetadataCommand(invocation) {
  return [
    "run",
    "--target",
    "native",
    invocation.orbitBuild,
    "package-metadata",
    invocation.config,
  ];
}

export function moonCommands(invocation, viteWorkflow = null) {
  const release = invocation.releaseBuild ? ["--release"] : [];
  const generate = [
    "run",
    "--target",
    "native",
    invocation.orbitBuild,
    invocation.config,
    invocation.output,
  ];
  if (invocation.command === "migrate-config") {
    return [[
      "run",
      "--target",
      "native",
      invocation.orbitBuild,
      "migrate-config",
      invocation.config,
      invocation.output,
    ]];
  }
  if (invocation.command === "bindings") {
    return [[
      "run",
      "--target",
      "native",
      invocation.orbitBuild,
      "bindings",
      invocation.config,
      invocation.output,
    ]];
  }
  if (invocation.command === "icon") {
    return [[
      "run",
      "--target",
      "native",
      invocation.orbitBuild,
      "icon",
      invocation.source,
      invocation.outDir,
      String(invocation.compression),
    ]];
  }
  if (invocation.command === "dev" && viteWorkflow) {
    return [[
      "run",
      "--target",
      "native",
      invocation.orbitBuild,
      "dev",
      invocation.config,
      invocation.output,
    ], ["run", "--target", "native", invocation.packagePath]];
  }
  if (invocation.command === "generate") {
    return [generate];
  }
  if (invocation.command === "build" || invocation.command === "package") {
    return [
      generate,
      ["run", ...release, "--target", "native", "--build-only", invocation.packagePath],
    ];
  }
  if (invocation.command === "diagnose") {
    return [["check", "--target", "native", invocation.packagePath]];
  }
  return [generate, ["run", ...release, "--target", "native", invocation.packagePath]];
}

function loadViteWorkflow(invocation) {
  const processSpec = moonProcess(invocation, viteWorkflowCommand(invocation));
  const result = spawnSync(processSpec.command, processSpec.args, {
    cwd: invocation.workspace,
    encoding: "utf8",
    env: commandEnvironment(invocation),
  });
  if (result.error) {
    throw new Error(`failed to inspect Vite workflow: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error("failed to inspect Vite workflow");
  }
  let workflow;
  try {
    workflow = JSON.parse(result.stdout.trim());
  } catch {
    throw new Error("orbit-build returned an invalid Vite workflow response");
  }
  if (workflow.vite === null) {
    return null;
  }
  if (!workflow.vite || ![
    "dev_command",
    "dev_url",
    "build_command",
    "dist_dir",
  ].every((key) => typeof workflow.vite[key] === "string" && workflow.vite[key].length > 0)) {
    throw new Error("orbit-build returned an incomplete Vite workflow");
  }
  return workflow.vite;
}

function loadPackageMetadata(invocation) {
  const processSpec = moonProcess(invocation, packageMetadataCommand(invocation));
  const result = spawnSync(processSpec.command, processSpec.args, {
    cwd: invocation.workspace,
    encoding: "utf8",
    env: commandEnvironment(invocation),
  });
  if (result.error) {
    throw new Error(`failed to inspect package metadata: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error("failed to inspect package metadata");
  }
  let metadata;
  try {
    metadata = JSON.parse(result.stdout.trim());
  } catch {
    throw new Error("orbit-build returned invalid package metadata");
  }
  const application = metadata?.application;
  if (
    metadata?.schema_version !== 2 ||
    typeof metadata.configuration_fingerprint !== "string" ||
    !application ||
    !["identifier", "name", "version"].every((key) =>
      typeof application[key] === "string" && application[key].length > 0
    ) ||
    !["product_name", "publisher"].every((key) =>
      application[key] === null || typeof application[key] === "string"
    ) ||
    !webviewInstallModes.has(metadata?.windows?.webview_install_mode) ||
    !Array.isArray(metadata.plugins) ||
    !metadata.plugins.every((plugin) =>
      plugin && ["id", "library", "manifest"].every((key) =>
        typeof plugin[key] === "string" && plugin[key].length > 0
      )
    )
  ) {
    throw new Error("orbit-build returned incomplete package metadata");
  }
  verifyCompatibilityProfile(metadata.compatibility, "orbit-build package metadata");
  return metadata;
}

function runWorkflowCommand(invocation, command) {
  const result = spawnSync(command, {
    cwd: dirname(invocation.config),
    env: commandEnvironment(invocation),
    shell: true,
    stdio: "inherit",
  });
  if (result.error) {
    throw new Error(`failed to start Vite command: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(`Vite command failed with exit code ${result.status ?? 1}`);
  }
}

function waitForDevelopmentUrl(url, timeout) {
  const script = [
    "const [url, timeout] = process.argv.slice(1);",
    "const deadline = Date.now() + Number(timeout);",
    "let lastError = 'no response';",
    "while (Date.now() < deadline) {",
    "  try { const response = await fetch(url); if (response.status < 500) process.exit(0); lastError = `HTTP ${response.status}`; }",
    "  catch (error) { lastError = error.message; }",
    "  await new Promise(resolve => setTimeout(resolve, 100));",
    "}",
    "console.error(`Orbit timed out waiting for ${url}: ${lastError}`);",
    "process.exit(1);",
  ].join("\n");
  const result = spawnSync(process.execPath, ["--input-type=module", "--eval", script, url, String(timeout)], {
    stdio: "inherit",
  });
  if (result.status !== 0) {
    throw new Error(`Vite dev URL did not become ready within ${timeout}ms`);
  }
}

function startDevelopmentServer(invocation, command) {
  const server = spawn(command, {
    cwd: dirname(invocation.config),
    env: commandEnvironment(invocation),
    shell: true,
    stdio: "inherit",
  });
  server.once("error", (error) => {
    process.stderr.write(`orbit: Vite dev server failed: ${error.message}\n`);
  });
  return server;
}

function stopDevelopmentServer(server) {
  if (!server?.pid) {
    return;
  }
  if (process.platform === "win32") {
    spawnSync("taskkill", ["/pid", String(server.pid), "/T", "/F"], { stdio: "ignore" });
  } else {
    server.kill("SIGTERM");
  }
}

function packageBuildDirectory(invocation) {
  const packageRelative = relative(invocation.workspace, invocation.packagePath);
  if (
    packageRelative === ".." ||
    packageRelative.startsWith(`..${sep}`) ||
    isAbsolute(packageRelative)
  ) {
    throw new Error("package path must remain within the Moon workspace");
  }
  return resolve(
    invocation.workspace,
    "_build",
    "native",
    invocation.releaseBuild ? "release" : "debug",
    "build",
    packageRelative || basename(invocation.workspace),
  );
}

export function discoverPackageBinary(invocation) {
  const buildDirectory = packageBuildDirectory(invocation);
  if (!existsSync(buildDirectory)) {
    throw new Error(`Moon native build output does not exist: ${buildDirectory}`);
  }
  const extension = process.platform === "win32" ? ".exe" : "";
  const expected = resolve(buildDirectory, `${basename(invocation.packagePath)}${extension}`);
  if (existsSync(expected) && statSync(expected).isFile()) {
    return expected;
  }
  const candidates = readdirSync(buildDirectory, { withFileTypes: true })
    .filter((entry) => entry.isFile() && (
      process.platform === "win32"
        ? entry.name.toLowerCase().endsWith(".exe")
        : !entry.name.includes(".")
    ))
    .map((entry) => resolve(buildDirectory, entry.name));
  if (candidates.length === 1) {
    return candidates[0];
  }
  if (candidates.length === 0) {
    throw new Error(`could not discover a native executable in ${buildDirectory}`);
  }
  throw new Error(`native build output is ambiguous in ${buildDirectory}; pass --binary explicitly`);
}

export function packageDescriptor(metadata, binary, discovered) {
  return {
    format: 3,
    compatibility: metadata.compatibility,
    target: {
      platform: process.platform,
      arch: process.arch,
    },
    configuration: {
      schemaVersion: metadata.schema_version,
      fingerprint: metadata.configuration_fingerprint,
    },
    application: metadata.application,
    bundle: metadata.bundle ?? { icons: [], linux: null },
    windows: metadata.windows,
    build: { profile: metadata.build_profile ?? "debug" },
    executable: `bin/${basename(binary)}`,
    executableDiscovered: discovered,
    plugins: metadata.plugins.length === 0 ? null : "plugins",
    pluginDeclarations: metadata.plugins,
  };
}

function packageFilePath(packageDirectory, relativePath) {
  if (
    relativePath.length === 0 ||
    relativePath === ".." ||
    relativePath.startsWith("../") ||
    relativePath.includes("\\")
  ) {
    throw new Error(`invalid package file path: ${relativePath}`);
  }
  const path = resolve(packageDirectory, relativePath);
  const pathRelative = relative(packageDirectory, path);
  if (
    pathRelative === ".." ||
    pathRelative.startsWith(`..${sep}`) ||
    isAbsolute(pathRelative)
  ) {
    throw new Error(`package file path escapes package directory: ${relativePath}`);
  }
  return path;
}

export function packageIntegrity(packageDirectory) {
  const files = [];
  function collect(directory, prefix = "") {
    const entries = readdirSync(directory, { withFileTypes: true })
      .sort((left, right) => left.name < right.name ? -1 : left.name > right.name ? 1 : 0);
    for (const entry of entries) {
      if (prefix.length === 0 && entry.name === "orbit-package.json") {
        continue;
      }
      const relativePath = prefix.length === 0 ? entry.name : `${prefix}/${entry.name}`;
      const path = resolve(directory, entry.name);
      if (entry.isDirectory()) {
        collect(path, relativePath);
      } else if (entry.isFile()) {
        const content = readFileSync(path);
        files.push({
          path: relativePath,
          size: content.length,
          sha256: createHash("sha256").update(content).digest("hex"),
        });
      } else {
        throw new Error(`package contains unsupported filesystem entry: ${relativePath}`);
      }
    }
  }
  collect(packageDirectory);
  return { algorithm: "sha256", files };
}

export function verifyPackage(packageDirectory) {
  const manifestPath = resolve(packageDirectory, "orbit-package.json");
  if (!existsSync(manifestPath)) {
    throw new Error(`package manifest does not exist: ${manifestPath}`);
  }
  let manifest;
  try {
    manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  } catch {
    throw new Error("package manifest is not valid JSON");
  }
  if (
    manifest?.format !== 3 ||
    manifest?.integrity?.algorithm !== "sha256" ||
    !Array.isArray(manifest.integrity.files)
  ) {
    throw new Error("package manifest does not contain format-3 integrity data");
  }
  verifyCompatibilityProfile(manifest.compatibility, "package manifest");
  if (
    !manifest.target ||
    typeof manifest.target.platform !== "string" ||
    typeof manifest.target.arch !== "string" ||
    !manifest.configuration ||
    manifest.configuration.schemaVersion !== compatibilityProfile.configuration_schema ||
    typeof manifest.configuration.fingerprint !== "string" ||
    manifest.configuration.fingerprint.length === 0 ||
    typeof manifest.executable !== "string" ||
    !manifest.executable.startsWith("bin/") ||
    (manifest.build !== undefined && !new Set(["debug", "release"]).has(manifest.build?.profile))
  ) {
    throw new Error("package manifest is incomplete or incompatible");
  }
  const executable = packageFilePath(packageDirectory, manifest.executable);
  if (!existsSync(executable) || !statSync(executable).isFile()) {
    throw new Error("package executable is missing");
  }
  const expected = manifest.integrity.files;
  const seen = new Set();
  for (const entry of expected) {
    if (
      !entry ||
      typeof entry.path !== "string" ||
      !Number.isInteger(entry.size) ||
      entry.size < 0 ||
      !/^[a-f0-9]{64}$/.test(entry.sha256) ||
      seen.has(entry.path)
    ) {
      throw new Error("package manifest contains an invalid integrity entry");
    }
    seen.add(entry.path);
    const path = packageFilePath(packageDirectory, entry.path);
    if (!existsSync(path) || !statSync(path).isFile()) {
      throw new Error(`package file is missing: ${entry.path}`);
    }
  }
  if (!seen.has(manifest.executable)) {
    throw new Error("package executable is not covered by integrity data");
  }
  const actual = packageIntegrity(packageDirectory);
  if (JSON.stringify(actual.files) !== JSON.stringify(expected)) {
    throw new Error("package integrity verification failed");
  }
  const bundle = manifest.bundle ?? { icons: [], linux: null };
  if (!Array.isArray(bundle.icons) || (bundle.linux !== null && typeof bundle.linux !== "object")) {
    throw new Error("package bundle metadata is incomplete or incompatible");
  }
  const iconPaths = new Set();
  for (const icon of bundle.icons) {
    if (typeof icon !== "string" || !icon.startsWith("icons/") || iconPaths.has(icon)) {
      throw new Error("package bundle icon declaration is invalid");
    }
    iconPaths.add(icon);
    const iconPath = packageFilePath(packageDirectory, icon);
    if (!existsSync(iconPath) || !statSync(iconPath).isFile() || !seen.has(icon)) {
      throw new Error(`package bundle icon is missing: ${icon}`);
    }
  }
  const declarations = manifest.pluginDeclarations;
  if (!Array.isArray(declarations) ||
    (declarations.length === 0 && manifest.plugins !== null) ||
    (declarations.length > 0 && manifest.plugins !== "plugins")) {
    throw new Error("package plugin declarations are incomplete or incompatible");
  }
  const pluginIds = new Set();
  const platform = packagePlatformName(manifest.target.platform);
  for (const declaration of declarations) {
    if (!declaration ||
      typeof declaration.id !== "string" || declaration.id.length === 0 ||
      typeof declaration.library !== "string" || !declaration.library.startsWith("plugins/") ||
      typeof declaration.manifest !== "string" || !declaration.manifest.startsWith("plugins/") ||
      pluginIds.has(declaration.id)) {
      throw new Error("package plugin declaration is invalid");
    }
    pluginIds.add(declaration.id);
    const library = packageFilePath(packageDirectory, declaration.library);
    const sidecarPath = packageFilePath(packageDirectory, declaration.manifest);
    if (!existsSync(library) || !statSync(library).isFile() || !existsSync(sidecarPath) || !statSync(sidecarPath).isFile()) {
      throw new Error(`package plugin payload is missing: ${declaration.id}`);
    }
    let sidecar;
    try {
      sidecar = JSON.parse(readFileSync(sidecarPath, "utf8"));
    } catch {
      throw new Error(`package plugin sidecar is not valid JSON: ${declaration.id}`);
    }
    if (sidecar?.schema_version !== compatibilityProfile.plugin_sidecar_schema ||
      !Number.isInteger(sidecar?.abi_version) ||
      sidecar.abi_version < 1 ||
      sidecar.abi_version > compatibilityProfile.plugin_abi ||
      sidecar?.id !== declaration.id ||
      !Array.isArray(sidecar?.platforms) || !sidecar.platforms.includes(platform)) {
      throw new Error(`package plugin sidecar is incompatible: ${declaration.id}`);
    }
  }
  return manifest;
}

function applicationResourcePath(applicationRoot, resource) {
  const path = resolve(applicationRoot, resource);
  const resourceRelative = relative(applicationRoot, path);
  if (
    resourceRelative === ".." ||
    resourceRelative.startsWith(`..${sep}`) ||
    isAbsolute(resourceRelative)
  ) {
    throw new Error(`package metadata resource escapes application root: ${resource}`);
  }
  return path;
}

function packageApplication(invocation, metadata) {
  const discovered = !invocation.binary;
  const binary = invocation.binary ?? discoverPackageBinary(invocation);
  if (!existsSync(binary) || !statSync(binary).isFile()) {
    throw new Error(`package binary does not exist: ${binary}`);
  }
  mkdirSync(invocation.outDir, { recursive: true });
  const binaryDir = resolve(invocation.outDir, "bin");
  mkdirSync(binaryDir, { recursive: true });
  cpSync(binary, resolve(binaryDir, basename(binary)));
  const appRoot = dirname(invocation.config);
  const plugins = resolve(appRoot, "plugins");
  if (metadata.plugins.length > 0 && !existsSync(plugins)) {
    throw new Error("package declares plugins but the application plugins directory does not exist");
  }
  for (const plugin of metadata.plugins) {
    for (const [field, resource] of [["library", plugin.library], ["manifest", plugin.manifest]]) {
      const path = applicationResourcePath(appRoot, resource);
      if (!existsSync(path) || !statSync(path).isFile()) {
        throw new Error(`declared plugin ${field} does not exist: ${resource}`);
      }
    }
  }
  if (existsSync(plugins)) {
    cpSync(plugins, resolve(invocation.outDir, "plugins"), { recursive: true });
  }
  if (invocation.runtimeDir) {
    if (!existsSync(invocation.runtimeDir)) {
      throw new Error(`WebView runtime directory does not exist: ${invocation.runtimeDir}`);
    }
    cpSync(invocation.runtimeDir, resolve(invocation.outDir, "runtime"), { recursive: true });
  }
  const packagedIcons = [];
  const packagedIconNames = new Set();
  for (const icon of metadata.bundle?.icons ?? []) {
    const source = applicationResourcePath(appRoot, icon);
    if (!existsSync(source) || !statSync(source).isFile()) {
      throw new Error(`declared bundle icon does not exist: ${icon}`);
    }
    const filename = basename(icon);
    if (packagedIconNames.has(filename)) {
      throw new Error(`bundle icons must have unique filenames: ${filename}`);
    }
    packagedIconNames.add(filename);
    const destination = resolve(invocation.outDir, "icons", filename);
    mkdirSync(dirname(destination), { recursive: true });
    cpSync(source, destination);
    packagedIcons.push(`icons/${filename}`);
  }
  const descriptor = {
    ...packageDescriptor(metadata, binary, discovered),
    bundle: {
      icons: packagedIcons,
      linux: metadata.bundle?.linux ?? null,
    },
    build: { profile: invocation.releaseBuild ? "release" : "debug" },
    plugins: existsSync(plugins) ? "plugins" : null,
    runtime: invocation.runtimeDir ? "runtime" : null,
  };
  writeFileSync(resolve(invocation.outDir, "orbit-package.json"), `${JSON.stringify({
    ...descriptor,
    integrity: packageIntegrity(invocation.outDir),
  }, null, 2)}\n`);
}

function sha256File(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function nsisQuoted(value) {
  if (value.includes("\r") || value.includes("\n") || value.includes("\0")) {
    throw new Error("NSIS values must not contain line breaks or null bytes");
  }
  return `"${value.replaceAll("$", "$$").replaceAll('"', "$\\\"")}"`;
}

function shellQuoted(value) {
  if (process.platform === "win32") {
    return `"${value.replaceAll('"', '""')}"`;
  }
  return `'${value.replaceAll("'", "'\\''")}'`;
}

export function installerMetadataPath(installer) {
  return `${installer}.orbit-installer.json`;
}

export function expandSigningCommand(command, values) {
  for (const placeholder of ["installer", "package_dir", "package_manifest"]) {
    if (!command.includes(`{${placeholder}}`)) {
      throw new Error(`sign-command must include {${placeholder}}`);
    }
  }
  return command
    .replaceAll("{installer}", shellQuoted(values.installer))
    .replaceAll("{package_dir}", shellQuoted(values.packageDirectory))
    .replaceAll("{package_manifest}", shellQuoted(values.packageManifest));
}

export function createNsisScript({
  installer,
  packageDirectory,
  bootstrapper,
  application,
  webviewInstallMode = "embed_bootstrapper",
  webview2DownloadUrl = WEBVIEW2_BOOTSTRAPPER_URL,
}) {
  if (!webviewInstallModes.has(webviewInstallMode)) {
    throw new Error(`unsupported WebView2 install mode: ${webviewInstallMode}`);
  }
  const webview2Lines = webview2NsisLines(
    webviewInstallMode,
    bootstrapper,
    webview2DownloadUrl,
  );
  const installDirectory = `$LOCALAPPDATA\\${application.identifier}`;
  const uninstallKey = `Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\${application.identifier}`;
  return [
    "Unicode True",
    "RequestExecutionLevel user",
    `Name ${nsisQuoted(application.product_name ?? application.name)}`,
    `OutFile ${nsisQuoted(installer)}`,
    `InstallDir "${installDirectory}"`,
    "ShowInstDetails show",
    "",
    'Section "Install"',
    ...webview2Lines,
    '  SetOutPath "$INSTDIR"',
    `  File /r ${nsisQuoted(join(packageDirectory, "*"))}`,
    '  WriteUninstaller "$INSTDIR\\Uninstall.exe"',
    `  WriteRegStr HKCU ${nsisQuoted(uninstallKey)} "DisplayName" ${nsisQuoted(application.product_name ?? application.name)}`,
    `  WriteRegStr HKCU ${nsisQuoted(uninstallKey)} "DisplayVersion" ${nsisQuoted(application.version)}`,
    `  WriteRegStr HKCU ${nsisQuoted(uninstallKey)} "UninstallString" '"$INSTDIR\\Uninstall.exe"'`,
    'SectionEnd',
    "",
    'Section "Uninstall"',
    `  DeleteRegKey HKCU ${nsisQuoted(uninstallKey)}`,
    '  RMDir /r "$INSTDIR"',
    'SectionEnd',
    "",
  ].join("\r\n");
}

function webview2NsisLines(mode, installer, downloadUrl) {
  if (mode === "skip") {
    return [];
  }
  const executable = mode === "offline_installer"
    ? "webview2-offline-installer.exe"
    : "webview2-bootstrapper.exe";
  const lines = ["  InitPluginsDir", '  SetOutPath "$PLUGINSDIR"'];
  if (mode === "download_bootstrapper") {
    lines.push(
      `  NSISdl::download /TIMEOUT=30000 ${nsisQuoted(downloadUrl)} "$PLUGINSDIR\\${executable}"`,
      "  Pop $0",
      '  StrCmp $0 "success" +2',
      '  Abort "Evergreen WebView2 Runtime download failed."',
    );
  } else {
    if (typeof installer !== "string" || installer.length === 0) {
      throw new Error(`${mode} requires a WebView2 installer payload`);
    }
    lines.push(`  File /oname=${executable} ${nsisQuoted(installer)}`);
  }
  lines.push(
    `  ExecWait '\"$PLUGINSDIR\\${executable}\" /silent /install' $0`,
    "  StrCmp $0 0 +3",
    "  StrCmp $0 3010 +2",
    '  Abort "Evergreen WebView2 Runtime installation failed."',
  );
  return lines;
}

export function installerDescriptor(packageManifest, installer, signed) {
  const size = statSync(installer).size;
  return {
    format: 2,
    installer: "nsis",
    signed,
    application: packageManifest.application,
    package: {
      format: packageManifest.format,
      compatibility: packageManifest.compatibility,
      target: packageManifest.target,
      configuration: packageManifest.configuration,
      windows: {
        webview_install_mode: packageWebviewInstallMode(packageManifest),
      },
      integrityAlgorithm: packageManifest.integrity.algorithm,
    },
    artifact: {
      file: basename(installer),
      size,
      sha256: sha256File(installer),
    },
  };
}

export function verifyInstaller(installer, metadataPath = installerMetadataPath(installer)) {
  if (!existsSync(installer) || !statSync(installer).isFile()) {
    throw new Error(`installer does not exist: ${installer}`);
  }
  if (!existsSync(metadataPath)) {
    throw new Error(`installer metadata does not exist: ${metadataPath}`);
  }
  let metadata;
  try {
    metadata = JSON.parse(readFileSync(metadataPath, "utf8"));
  } catch {
    throw new Error("installer metadata is not valid JSON");
  }
  if (
    metadata?.format !== 2 ||
    metadata?.installer !== "nsis" ||
    typeof metadata.signed !== "boolean" ||
    !metadata.application ||
    typeof metadata.application.identifier !== "string" ||
    metadata?.package?.format !== 3 ||
    metadata.package?.target?.platform !== "win32" ||
    typeof metadata.package?.target?.arch !== "string" ||
    metadata.package?.configuration?.schemaVersion !== 2 ||
    typeof metadata.package?.configuration?.fingerprint !== "string" ||
    !webviewInstallModes.has(metadata.package?.windows?.webview_install_mode) ||
    metadata.package?.integrityAlgorithm !== "sha256" ||
    metadata?.artifact?.file !== basename(installer) ||
    !Number.isInteger(metadata.artifact?.size) ||
    !/^[a-f0-9]{64}$/.test(metadata.artifact?.sha256)
  ) {
    throw new Error("installer metadata is incomplete or incompatible");
  }
  verifyCompatibilityProfile(metadata.package.compatibility, "installer package metadata");
  if (metadata.artifact.size !== statSync(installer).size || metadata.artifact.sha256 !== sha256File(installer)) {
    throw new Error("installer integrity verification failed");
  }
  return metadata;
}

export function archiveMetadataPath(archive) {
  return `${archive}.orbit-archive.json`;
}

function archivePackageDescriptor(packageManifest) {
  return {
    format: packageManifest.format,
    compatibility: packageManifest.compatibility,
    target: packageManifest.target,
    configuration: packageManifest.configuration,
    integrityAlgorithm: packageManifest.integrity.algorithm,
  };
}

export function archiveDescriptor(packageManifest, archive, signed) {
  const size = statSync(archive).size;
  return {
    format: 1,
    archive: "tar.gz",
    signed,
    application: packageManifest.application,
    package: archivePackageDescriptor(packageManifest),
    artifact: {
      file: basename(archive),
      size,
      sha256: sha256File(archive),
    },
  };
}

export function verifyArchive(archive, metadataPath = archiveMetadataPath(archive)) {
  if (!existsSync(archive) || !statSync(archive).isFile()) {
    throw new Error(`archive does not exist: ${archive}`);
  }
  if (!existsSync(metadataPath)) {
    throw new Error(`archive metadata does not exist: ${metadataPath}`);
  }
  let metadata;
  try {
    metadata = JSON.parse(readFileSync(metadataPath, "utf8"));
  } catch {
    throw new Error("archive metadata is not valid JSON");
  }
  if (
    metadata?.format !== 1 ||
    metadata?.archive !== "tar.gz" ||
    typeof metadata.signed !== "boolean" ||
    !metadata.application ||
    typeof metadata.application.identifier !== "string" ||
    typeof metadata.application.name !== "string" ||
    typeof metadata.application.version !== "string" ||
    metadata?.package?.format !== 3 ||
    metadata.package?.target?.platform !== "linux" ||
    typeof metadata.package?.target?.arch !== "string" ||
    metadata.package?.configuration?.schemaVersion !== 2 ||
    typeof metadata.package?.configuration?.fingerprint !== "string" ||
    metadata.package?.integrityAlgorithm !== "sha256" ||
    metadata?.artifact?.file !== basename(archive) ||
    !Number.isInteger(metadata.artifact?.size) ||
    !/^[a-f0-9]{64}$/.test(metadata.artifact?.sha256)
  ) {
    throw new Error("archive metadata is incomplete or incompatible");
  }
  verifyCompatibilityProfile(metadata.package.compatibility, "archive package metadata");
  if (metadata.artifact.size !== statSync(archive).size || metadata.artifact.sha256 !== sha256File(archive)) {
    throw new Error("archive integrity verification failed");
  }
  return metadata;
}

function safeArchiveSegment(value, label) {
  if (typeof value !== "string" || !/^[A-Za-z0-9._+-]+$/.test(value)) {
    throw new Error(`archive application ${label} must use ASCII letters, digits, dot, dash, underscore, or plus`);
  }
  return value;
}

function pathInside(directory, path) {
  const pathRelative = relative(directory, path);
  return pathRelative.length === 0 || (!pathRelative.startsWith(`..${sep}`) && pathRelative !== ".." && !isAbsolute(pathRelative));
}

function writeTarString(buffer, offset, length, value) {
  const encoded = Buffer.from(value, "utf8");
  if (encoded.length > length) {
    throw new Error(`archive path is too long for ustar: ${value}`);
  }
  encoded.copy(buffer, offset);
}

function writeTarOctal(buffer, offset, length, value) {
  const encoded = value.toString(8);
  if (encoded.length >= length) {
    throw new Error("archive metadata field exceeds ustar limits");
  }
  writeTarString(buffer, offset, length, `${encoded.padStart(length - 1, "0")}\0`);
}

function writeTarPath(header, path) {
  if (Buffer.byteLength(path, "utf8") <= 100) {
    writeTarString(header, 0, 100, path);
    return;
  }
  for (let index = path.length - 1; index > 0; index -= 1) {
    if (path[index] !== "/") continue;
    const prefix = path.slice(0, index);
    const name = path.slice(index + 1);
    if (Buffer.byteLength(prefix, "utf8") <= 155 && Buffer.byteLength(name, "utf8") <= 100) {
      writeTarString(header, 0, 100, name);
      writeTarString(header, 345, 155, prefix);
      return;
    }
  }
  throw new Error(`archive path is too long for ustar: ${path}`);
}

function tarHeader(path, mode, size, type) {
  const header = Buffer.alloc(512);
  writeTarPath(header, path);
  writeTarOctal(header, 100, 8, mode);
  writeTarOctal(header, 108, 8, 0);
  writeTarOctal(header, 116, 8, 0);
  writeTarOctal(header, 124, 12, size);
  writeTarOctal(header, 136, 12, 0);
  header.fill(0x20, 148, 156);
  header[156] = type.charCodeAt(0);
  writeTarString(header, 257, 6, "ustar\0");
  writeTarString(header, 263, 2, "00");
  const checksum = header.reduce((total, byte) => total + byte, 0);
  writeTarOctal(header, 148, 8, checksum);
  return header;
}

function tarEntry(path, mode, type, content = Buffer.alloc(0)) {
  const padding = (512 - (content.length % 512)) % 512;
  return [tarHeader(path, mode, content.length, type), content, Buffer.alloc(padding)];
}

function packageDirectories(files) {
  const directories = new Set();
  for (const file of files) {
    let directory = dirname(file.path).replaceAll("\\", "/");
    while (directory !== "." && directory.length > 0) {
      directories.add(directory);
      directory = dirname(directory).replaceAll("\\", "/");
    }
  }
  return [...directories].sort();
}

function shellSingleQuoted(value) {
  return `'${value.replaceAll("'", "'\\''")}'`;
}

export function createLinuxArchive(packageDirectory, archive, packageManifest) {
  const identifier = safeArchiveSegment(packageManifest.application?.identifier, "identifier");
  const version = safeArchiveSegment(packageManifest.application?.version, "version");
  const root = `${identifier}-${version}`;
  const files = packageIntegrity(packageDirectory).files;
  const executable = packageManifest.executable;
  const launcher = Buffer.from(
    `#!/bin/sh\nset -eu\nroot=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)\ncd "$root/orbit-package"\nexec ./${shellSingleQuoted(executable)} "$@"\n`,
    "utf8",
  );
  const entries = [
    ...tarEntry(`${root}/`, 0o755, "5"),
    ...tarEntry(`${root}/run`, 0o755, "0", launcher),
    ...tarEntry(`${root}/orbit-package/`, 0o755, "5"),
  ];
  for (const directory of packageDirectories(files)) {
    entries.push(...tarEntry(`${root}/orbit-package/${directory}/`, 0o755, "5"));
  }
  for (const file of [
    { path: "orbit-package.json", source: resolve(packageDirectory, "orbit-package.json") },
    ...files.map((entry) => ({ path: entry.path, source: packageFilePath(packageDirectory, entry.path) })),
  ]) {
    const content = readFileSync(file.source);
    const sourceMode = statSync(file.source).mode & 0o777;
    const mode = file.path === executable ? 0o755 : sourceMode;
    entries.push(...tarEntry(`${root}/orbit-package/${file.path}`, mode, "0", content));
  }
  writeFileSync(archive, gzipSync(Buffer.concat([...entries, Buffer.alloc(1024)]), { mtime: 0 }));
}

function runSigningCommand(invocation, installer, packageDirectory) {
  if (!invocation.signCommand) {
    return false;
  }
  const command = expandSigningCommand(invocation.signCommand, {
    installer,
    packageDirectory,
    packageManifest: resolve(packageDirectory, "orbit-package.json"),
  });
  const result = spawnSync(command, {
    cwd: packageDirectory,
    shell: true,
    stdio: "inherit",
  });
  if (result.error) {
    throw new Error(`failed to start sign-command: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(`sign-command failed with exit code ${result.status ?? 1}`);
  }
  return true;
}

export function expandArchiveSigningCommand(command, values) {
  for (const placeholder of ["archive", "package_dir", "package_manifest"]) {
    if (!command.includes(`{${placeholder}}`)) {
      throw new Error(`archive sign-command must include {${placeholder}}`);
    }
  }
  return command
    .replaceAll("{archive}", shellQuoted(values.archive))
    .replaceAll("{package_dir}", shellQuoted(values.packageDirectory))
    .replaceAll("{package_manifest}", shellQuoted(values.packageManifest));
}

function runArchiveSigningCommand(invocation, archive) {
  if (!invocation.signCommand) {
    return false;
  }
  const hashBeforeSigning = sha256File(archive);
  const command = expandArchiveSigningCommand(invocation.signCommand, {
    archive,
    packageDirectory: invocation.packageDir,
    packageManifest: resolve(invocation.packageDir, "orbit-package.json"),
  });
  const result = spawnSync(command, {
    cwd: invocation.packageDir,
    shell: true,
    stdio: "inherit",
  });
  if (result.error) {
    throw new Error(`failed to start archive sign-command: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(`archive sign-command failed with exit code ${result.status ?? 1}`);
  }
  if (sha256File(archive) !== hashBeforeSigning) {
    throw new Error("archive sign-command must not modify the archive; use a detached signature");
  }
  return true;
}

export async function buildLinuxArchive(invocation) {
  const packageManifest = verifyPackage(invocation.packageDir);
  if (packageManifest.target?.platform !== "linux") {
    throw new Error("archive requires a Linux package artifact");
  }
  const identifier = safeArchiveSegment(packageManifest.application?.identifier, "identifier");
  const version = safeArchiveSegment(packageManifest.application?.version, "version");
  const arch = safeArchiveSegment(packageManifest.target?.arch, "architecture");
  if (typeof packageManifest.application?.name !== "string" || packageManifest.application.name.trim().length === 0) {
    throw new Error("archive package manifest has invalid application metadata");
  }
  if (pathInside(invocation.packageDir, invocation.outDir)) {
    throw new Error("archive output directory must not be inside the package directory");
  }
  mkdirSync(invocation.outDir, { recursive: true });
  const archive = resolve(
    invocation.outDir,
    `${identifier}-${version}-linux-${arch}.tar.gz`,
  );
  createLinuxArchive(invocation.packageDir, archive, packageManifest);
  const signed = runArchiveSigningCommand(invocation, archive);
  const metadataPath = archiveMetadataPath(archive);
  writeFileSync(metadataPath, `${JSON.stringify(
    archiveDescriptor(packageManifest, archive, signed),
    null,
    2,
  )}\n`);
  return { archive, metadataPath };
}

const NSIS_VERSION = "3.11";
const NSIS_URL = "https://github.com/tauri-apps/binary-releases/releases/download/nsis-3.11/nsis-3.11.zip";
const NSIS_SHA1 = "ef7ff767e5cbd9edd22add3a32c9b8f4500bb10d";
const NSIS_SHA256 = "c7d27f780ddb6cffb4730138cd1591e841f4b7edb155856901cdf5f214394fa1";
const WEBVIEW2_BOOTSTRAPPER_URL = "https://go.microsoft.com/fwlink/p/?LinkId=2124703";
const WEBVIEW2_OFFLINE_INSTALLER_X64_URL = "https://go.microsoft.com/fwlink/?linkid=2124701";

export function windowsToolCacheDirectory() {
  return join(homedir(), ".orbit", "tools", "windows");
}

function sha1File(path) {
  return createHash("sha1").update(readFileSync(path)).digest("hex");
}

async function downloadFile(url, output, expectedHashes = null) {
  const temporary = `${output}.tmp`;
  rmSync(temporary, { force: true });
  try {
    if (process.platform === "win32") {
      const result = spawnSync("curl.exe", [
        "--fail",
        "--location",
        "--silent",
        "--show-error",
        "--output",
        temporary,
        url,
      ], { stdio: "inherit" });
      if (result.error) {
        throw new Error(`failed to start Windows download client: ${result.error.message}`);
      }
      if (result.status !== 0) {
        throw new Error(`Windows download client failed with exit code ${result.status ?? 1}`);
      }
    } else {
      const response = await fetch(url, { redirect: "follow" });
      if (!response.ok) {
        throw new Error(`download failed with HTTP ${response.status}: ${url}`);
      }
      writeFileSync(temporary, Buffer.from(await response.arrayBuffer()));
    }
    if (
      expectedHashes &&
      (
        sha1File(temporary) !== expectedHashes.sha1 ||
        sha256File(temporary) !== expectedHashes.sha256
      )
    ) {
      throw new Error(`downloaded file failed integrity verification: ${url}`);
    }
    renameSync(temporary, output);
  } catch (error) {
    rmSync(temporary, { force: true });
    throw error;
  }
}

function extractZip(archive, destination) {
  const result = spawnSync("tar", ["-xf", archive, "-C", destination], { stdio: "inherit" });
  if (result.error) {
    throw new Error(`failed to start ZIP extractor tar: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(`ZIP extractor failed with exit code ${result.status ?? 1}`);
  }
}

async function ensureNsisCompiler() {
  const toolRoot = windowsToolCacheDirectory();
  const toolDirectory = join(toolRoot, "nsis", NSIS_VERSION);
  const compiler = join(toolDirectory, "makensis.exe");
  const downloadPlugin = join(toolDirectory, "Plugins", "x86-unicode", "NSISdl.dll");
  if (existsSync(compiler) && existsSync(downloadPlugin)) {
    return compiler;
  }
  mkdirSync(toolRoot, { recursive: true });
  const archive = join(toolRoot, `nsis-${NSIS_VERSION}.zip`);
  const expectedHashes = { sha1: NSIS_SHA1, sha256: NSIS_SHA256 };
  if (
    !existsSync(archive) ||
    sha1File(archive) !== expectedHashes.sha1 ||
    sha256File(archive) !== expectedHashes.sha256
  ) {
    rmSync(archive, { force: true });
    await downloadFile(NSIS_URL, archive, expectedHashes);
  }
  const extracted = mkdtempSync(join(toolRoot, ".nsis-extract-"));
  try {
    extractZip(archive, extracted);
    const source = join(extracted, `nsis-${NSIS_VERSION}`);
    if (!existsSync(join(source, "makensis.exe")) || !existsSync(join(source, "Plugins", "x86-unicode", "NSISdl.dll"))) {
      throw new Error("downloaded NSIS archive does not contain the required compiler and download plugin");
    }
    rmSync(toolDirectory, { recursive: true, force: true });
    mkdirSync(dirname(toolDirectory), { recursive: true });
    renameSync(source, toolDirectory);
  } finally {
    rmSync(extracted, { recursive: true, force: true });
  }
  return compiler;
}

async function resolveWebview2Bootstrapper(invocation) {
  if (invocation.webview2Bootstrapper) {
    if (!existsSync(invocation.webview2Bootstrapper) || !statSync(invocation.webview2Bootstrapper).isFile()) {
      throw new Error(`WebView2 bootstrapper does not exist: ${invocation.webview2Bootstrapper}`);
    }
    return invocation.webview2Bootstrapper;
  }
  const directory = join(windowsToolCacheDirectory(), "webview2");
  const bootstrapper = join(directory, "MicrosoftEdgeWebview2Setup.exe");
  if (!existsSync(bootstrapper)) {
    mkdirSync(directory, { recursive: true });
    await downloadFile(WEBVIEW2_BOOTSTRAPPER_URL, bootstrapper);
  }
  return bootstrapper;
}

async function resolveWebview2OfflineInstaller(invocation) {
  if (invocation.webview2Bootstrapper) {
    if (!existsSync(invocation.webview2Bootstrapper) || !statSync(invocation.webview2Bootstrapper).isFile()) {
      throw new Error(`WebView2 offline installer does not exist: ${invocation.webview2Bootstrapper}`);
    }
    return invocation.webview2Bootstrapper;
  }
  const directory = join(windowsToolCacheDirectory(), "webview2", "offline", "x64");
  const installer = join(directory, "MicrosoftEdgeWebView2RuntimeInstallerX64.exe");
  if (!existsSync(installer)) {
    mkdirSync(directory, { recursive: true });
    await downloadFile(WEBVIEW2_OFFLINE_INSTALLER_X64_URL, installer);
  }
  return installer;
}

function packageWebviewInstallMode(packageManifest) {
  const mode = packageManifest.windows?.webview_install_mode ?? "embed_bootstrapper";
  if (!webviewInstallModes.has(mode)) {
    throw new Error("installer package manifest has an unsupported Windows WebView2 install mode");
  }
  return mode;
}

async function buildWindowsInstaller(invocation) {
  if (process.platform !== "win32") {
    throw new Error("NSIS installer generation is available only on Windows");
  }
  const packageManifest = verifyPackage(invocation.packageDir);
  if (packageManifest.target?.platform !== "win32") {
    throw new Error("installer requires a Windows package artifact");
  }
  if (
    !/^[A-Za-z0-9._-]+$/.test(packageManifest.application?.identifier ?? "") ||
    typeof packageManifest.application?.name !== "string" ||
    packageManifest.application.name.trim().length === 0 ||
    typeof packageManifest.application?.version !== "string" ||
    packageManifest.application.version.trim().length === 0
  ) {
    throw new Error("installer package manifest has invalid application metadata");
  }
  if (packageManifest.runtime !== null) {
    throw new Error("installer does not support --runtime-dir because MoonView uses Evergreen WebView2");
  }
  const webviewInstallMode = packageWebviewInstallMode(packageManifest);
  if (
    invocation.webview2Bootstrapper &&
    (webviewInstallMode === "download_bootstrapper" || webviewInstallMode === "skip")
  ) {
    throw new Error(`--webview2-bootstrapper cannot override ${webviewInstallMode}`);
  }
  const bootstrapper = webviewInstallMode === "embed_bootstrapper"
    ? await resolveWebview2Bootstrapper(invocation)
    : webviewInstallMode === "offline_installer"
      ? await resolveWebview2OfflineInstaller(invocation)
      : undefined;
  const makensis = invocation.makensisProvided
    ? invocation.makensis
    : await ensureNsisCompiler();
  mkdirSync(invocation.outDir, { recursive: true });
  const installer = resolve(
    invocation.outDir,
    `${packageManifest.application.identifier}-${packageManifest.application.version}-setup.exe`,
  );
  const temporaryDirectory = mkdtempSync(join(tmpdir(), "orbit-nsis-"));
  const scriptPath = resolve(temporaryDirectory, "installer.nsi");
  try {
    writeFileSync(scriptPath, createNsisScript({
      installer,
      packageDirectory: invocation.packageDir,
      bootstrapper,
      application: packageManifest.application,
      webviewInstallMode,
    }));
    const result = spawnSync(makensis, [scriptPath], {
      cwd: invocation.workspace,
      stdio: "inherit",
    });
    if (result.error) {
      throw new Error(`failed to start NSIS compiler ${makensis}: ${result.error.message}`);
    }
    if (result.status !== 0) {
      throw new Error(`NSIS compiler failed with exit code ${result.status ?? 1}`);
    }
    if (!existsSync(installer) || !statSync(installer).isFile()) {
      throw new Error("NSIS compiler did not produce the expected installer");
    }
    const signed = runSigningCommand(invocation, installer, invocation.packageDir);
    const metadataPath = installerMetadataPath(installer);
    writeFileSync(metadataPath, `${JSON.stringify(
      installerDescriptor(packageManifest, installer, signed),
      null,
      2,
    )}\n`);
    return { installer, metadataPath };
  } finally {
    rmSync(temporaryDirectory, { recursive: true, force: true });
  }
}

export async function main(argv, environment = { cwd: process.cwd(), stdout: process.stdout }) {
  let invocation;
  try {
    invocation = parseInvocation(argv, environment.cwd);
  } catch (error) {
    environment.stdout.write(`orbit: ${error.message}\n\n${usage()}\n`);
    process.exitCode = 2;
    return;
  }

  if (invocation.help) {
    environment.stdout.write(`${usage()}\n`);
    return;
  }

  if (invocation.command === "verify-package") {
    try {
      const manifest = verifyPackage(invocation.packageDir);
      if (invocation.json) {
        environment.stdout.write(`${JSON.stringify({ code: "ok", command: invocation.command, application: manifest.application.identifier })}\n`);
      }
    } catch (error) {
      if (invocation.json) {
        environment.stdout.write(`${JSON.stringify({ code: "package_verification_failed", message: error.message })}\n`);
      } else {
        environment.stdout.write(`orbit: ${error.message}\n`);
      }
      process.exitCode = 2;
    }
    return;
  }

  if (invocation.command === "verify-installer") {
    try {
      const metadata = verifyInstaller(invocation.installer, invocation.installerMetadata);
      if (invocation.json) {
        environment.stdout.write(`${JSON.stringify({ code: "ok", command: invocation.command, application: metadata.application.identifier })}\n`);
      }
    } catch (error) {
      if (invocation.json) {
        environment.stdout.write(`${JSON.stringify({ code: "installer_verification_failed", message: error.message })}\n`);
      } else {
        environment.stdout.write(`orbit: ${error.message}\n`);
      }
      process.exitCode = 2;
    }
    return;
  }

  if (invocation.command === "verify-archive") {
    try {
      const metadata = verifyArchive(invocation.archive, invocation.archiveMetadata);
      if (invocation.json) {
        environment.stdout.write(`${JSON.stringify({ code: "ok", command: invocation.command, application: metadata.application.identifier })}\n`);
      }
    } catch (error) {
      if (invocation.json) {
        environment.stdout.write(`${JSON.stringify({ code: "archive_verification_failed", message: error.message })}\n`);
      } else {
        environment.stdout.write(`orbit: ${error.message}\n`);
      }
      process.exitCode = 2;
    }
    return;
  }

  if (invocation.command === "verify-linux-package") {
    try {
      const metadata = verifyLinuxPackageArtifact(
        invocation.artifact,
        invocation.artifactMetadata ?? linuxPackageMetadataPath(invocation.artifact),
        compatibilityProfile,
      );
      if (invocation.json) {
        environment.stdout.write(`${JSON.stringify({ code: "ok", command: invocation.command, application: metadata.application.identifier, backend: metadata.backend })}\n`);
      }
    } catch (error) {
      if (invocation.json) {
        environment.stdout.write(`${JSON.stringify({ code: "linux_package_verification_failed", message: error.message })}\n`);
      } else {
        environment.stdout.write(`orbit: ${error.message}\n`);
      }
      process.exitCode = 2;
    }
    return;
  }

  if (invocation.command === "installer") {
    try {
      const result = await buildWindowsInstaller(invocation);
      if (invocation.json) {
        environment.stdout.write(`${JSON.stringify({ code: "ok", command: invocation.command, installer: result.installer })}\n`);
      }
    } catch (error) {
      if (invocation.json) {
        environment.stdout.write(`${JSON.stringify({ code: "installer_failed", message: error.message })}\n`);
      } else {
        environment.stdout.write(`orbit: ${error.message}\n`);
      }
      process.exitCode = 2;
    }
    return;
  }

  if (invocation.command === "archive") {
    try {
      const result = await buildLinuxArchive(invocation);
      if (invocation.json) {
        environment.stdout.write(`${JSON.stringify({ code: "ok", command: invocation.command, archive: result.archive })}\n`);
      }
    } catch (error) {
      if (invocation.json) {
        environment.stdout.write(`${JSON.stringify({ code: "archive_failed", message: error.message })}\n`);
      } else {
        environment.stdout.write(`orbit: ${error.message}\n`);
      }
      process.exitCode = 2;
    }
    return;
  }

  if (invocation.command === "linux-package") {
    try {
      const manifest = verifyPackage(invocation.packageDir);
      if (manifest.build?.profile !== "release") {
        throw new Error("linux-package requires a directory package built with orbit package --release");
      }
      const result = buildLinuxPackage({
        ...invocation,
        release: invocation.packageRelease,
      }, manifest);
      if (invocation.json) {
        environment.stdout.write(`${JSON.stringify({ code: "ok", command: invocation.command, artifact: result.artifact })}\n`);
      }
    } catch (error) {
      if (invocation.json) {
        environment.stdout.write(`${JSON.stringify({ code: "linux_package_failed", message: error.message })}\n`);
      } else {
        environment.stdout.write(`orbit: ${error.message}\n`);
      }
      process.exitCode = 2;
    }
    return;
  }

  let developmentServer;
  try {
    const packageMetadata = invocation.command === "package"
      ? loadPackageMetadata(invocation)
      : null;
    const needsViteWorkflow = ["dev", "build", "run", "package"].includes(invocation.command);
    const viteWorkflow = needsViteWorkflow ? loadViteWorkflow(invocation) : null;
    if (viteWorkflow && invocation.command === "dev") {
      developmentServer = startDevelopmentServer(invocation, viteWorkflow.dev_command);
      waitForDevelopmentUrl(viteWorkflow.dev_url, invocation.devTimeout);
    } else if (viteWorkflow && ["build", "run", "package"].includes(invocation.command)) {
      runWorkflowCommand(invocation, viteWorkflow.build_command);
    }
    if (invocation.command === "icon") {
      mkdirSync(invocation.outDir, { recursive: true });
    }
    for (const command of moonCommands(invocation, viteWorkflow)) {
      if (!runMoon(invocation, command)) {
        return;
      }
    }
    if (invocation.command === "package") {
      packageApplication(invocation, packageMetadata);
    }
  } catch (error) {
    const code = invocation.command === "package" ? "package_failed" : "workflow_failed";
    if (invocation.json) {
      environment.stdout.write(`${JSON.stringify({ code, message: error.message })}\n`);
    } else {
      environment.stdout.write(`orbit: ${error.message}\n`);
    }
    process.exitCode = 2;
    return;
  } finally {
    stopDevelopmentServer(developmentServer);
  }
  if (invocation.json) {
    environment.stdout.write(`${JSON.stringify({ code: "ok", command: invocation.command, config: invocation.config })}\n`);
  }
}
