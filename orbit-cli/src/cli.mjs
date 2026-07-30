import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import process from "node:process";

const commands = new Set(["generate", "bindings", "build", "run", "dev", "diagnose", "package", "verify-package", "installer", "verify-installer", "migrate-config", "icon"]);

export function usage() {
  return [
    "Usage: orbit <generate|bindings|build|run|diagnose|package|verify-package|installer|verify-installer|migrate-config|icon> [options]",
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
    "  --package-dir <path>  Package directory verified by verify-package",
    "  --webview2-bootstrapper <path>  Local Evergreen WebView2 bootstrapper for installer",
    "  --makensis <command>  NSIS compiler (default: makensis)",
    "  --sign-command <command>  External installer signing command",
    "  --allow-unsigned       Permit an unsigned installer",
    "  --installer <path>    Installer verified by verify-installer",
    "  --installer-metadata <path>  Installer metadata path (default: adjacent file)",
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
      "package-dir",
      "webview2-bootstrapper",
      "makensis",
      "sign-command",
      "allow-unsigned",
      "installer",
      "installer-metadata",
      "source",
      "compression",
      "dev-timeout",
      "json",
    ].includes(key)) {
      throw new Error(`unknown option: ${argument}`);
    }
    if (["json", "allow-unsigned"].includes(key)) {
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
    outDir: resolve(workspace, values["out-dir"] ?? (command === "icon" ? "icons" : "dist")),
    source: values.source ? resolve(workspace, values.source) : undefined,
    compression,
    runtimeDir: values["runtime-dir"] ? resolve(workspace, values["runtime-dir"]) : undefined,
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
      ["run", "--target", "native", "--build-only", invocation.packagePath],
    ];
  }
  if (invocation.command === "diagnose") {
    return [["check", "--target", "native", invocation.packagePath]];
  }
  return [generate, ["run", "--target", "native", invocation.packagePath]];
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
    !Array.isArray(metadata.plugins) ||
    !metadata.plugins.every((plugin) =>
      plugin && ["id", "library", "manifest"].every((key) =>
        typeof plugin[key] === "string" && plugin[key].length > 0
      )
    )
  ) {
    throw new Error("orbit-build returned incomplete package metadata");
  }
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
    "debug",
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
    format: 2,
    orbit: "0.1.0-alpha.1",
    moonview: "0.1.0-beta.3",
    pluginAbi: 1,
    target: {
      platform: process.platform,
      arch: process.arch,
    },
    configuration: {
      schemaVersion: metadata.schema_version,
      fingerprint: metadata.configuration_fingerprint,
    },
    application: metadata.application,
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
    manifest?.format !== 2 ||
    manifest?.integrity?.algorithm !== "sha256" ||
    !Array.isArray(manifest.integrity.files)
  ) {
    throw new Error("package manifest does not contain format-2 integrity data");
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
  const actual = packageIntegrity(packageDirectory);
  if (JSON.stringify(actual.files) !== JSON.stringify(expected)) {
    throw new Error("package integrity verification failed");
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
  const descriptor = {
    ...packageDescriptor(metadata, binary, discovered),
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
}) {
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
    "  InitPluginsDir",
    '  SetOutPath "$PLUGINSDIR"',
    `  File /oname=webview2-bootstrapper.exe ${nsisQuoted(bootstrapper)}`,
    '  ExecWait \'"$PLUGINSDIR\\webview2-bootstrapper.exe" /silent /install\' $0',
    "  StrCmp $0 0 +3",
    "  StrCmp $0 3010 +2",
    '  Abort "Evergreen WebView2 Runtime installation failed."',
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

export function installerDescriptor(packageManifest, installer, signed) {
  const size = statSync(installer).size;
  return {
    format: 1,
    installer: "nsis",
    signed,
    application: packageManifest.application,
    package: {
      format: packageManifest.format,
      orbit: packageManifest.orbit,
      moonview: packageManifest.moonview,
      pluginAbi: packageManifest.pluginAbi,
      target: packageManifest.target,
      configuration: packageManifest.configuration,
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
    metadata?.format !== 1 ||
    metadata?.installer !== "nsis" ||
    typeof metadata.signed !== "boolean" ||
    !metadata.application ||
    typeof metadata.application.identifier !== "string" ||
    metadata?.package?.format !== 2 ||
    metadata.package?.target?.platform !== "win32" ||
    typeof metadata.package?.target?.arch !== "string" ||
    metadata.package?.configuration?.schemaVersion !== 2 ||
    typeof metadata.package?.configuration?.fingerprint !== "string" ||
    metadata.package?.integrityAlgorithm !== "sha256" ||
    metadata?.artifact?.file !== basename(installer) ||
    !Number.isInteger(metadata.artifact?.size) ||
    !/^[a-f0-9]{64}$/.test(metadata.artifact?.sha256)
  ) {
    throw new Error("installer metadata is incomplete or incompatible");
  }
  if (metadata.artifact.size !== statSync(installer).size || metadata.artifact.sha256 !== sha256File(installer)) {
    throw new Error("installer integrity verification failed");
  }
  return metadata;
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

const NSIS_VERSION = "3.11";
const NSIS_URL = "https://github.com/tauri-apps/binary-releases/releases/download/nsis-3.11/nsis-3.11.zip";
const NSIS_SHA1 = "ef7ff767e5cbd9edd22add3a32c9b8f4500bb10d";
const NSIS_SHA256 = "c7d27f780ddb6cffb4730138cd1591e841f4b7edb155856901cdf5f214394fa1";
const WEBVIEW2_BOOTSTRAPPER_URL = "https://go.microsoft.com/fwlink/p/?LinkId=2124703";

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
  if (existsSync(compiler)) {
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
    if (!existsSync(join(source, "makensis.exe"))) {
      throw new Error("downloaded NSIS archive does not contain makensis.exe");
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
  const bootstrapper = await resolveWebview2Bootstrapper(invocation);
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
