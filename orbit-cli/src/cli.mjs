import { spawn, spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, isAbsolute, relative, resolve, sep } from "node:path";
import process from "node:process";

const commands = new Set(["generate", "bindings", "build", "run", "dev", "diagnose", "package", "migrate-config", "icon"]);

export function usage() {
  return [
    "Usage: orbit <generate|bindings|build|run|diagnose|package|migrate-config|icon> [options]",
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
      "source",
      "compression",
      "dev-timeout",
      "json",
    ].includes(key)) {
      throw new Error(`unknown option: ${argument}`);
    }
    if (key === "json") {
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
  writeFileSync(resolve(invocation.outDir, "orbit-package.json"), `${JSON.stringify({
    ...packageDescriptor(metadata, binary, discovered),
    plugins: existsSync(plugins) ? "plugins" : null,
    runtime: invocation.runtimeDir ? "runtime" : null,
  }, null, 2)}\n`);
}

export function main(argv, environment = { cwd: process.cwd(), stdout: process.stdout }) {
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
