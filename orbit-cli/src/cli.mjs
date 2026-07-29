import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import { basename, dirname, resolve } from "node:path";
import process from "node:process";

const commands = new Set(["generate", "build", "run", "dev", "diagnose", "package"]);

export function usage() {
  return [
    "Usage: orbit <generate|build|run|diagnose|package> [options]",
    "",
    "Options:",
    "  --config <path>       Configuration file (default: orbit.conf.json)",
    "  --output <path>       Generated MoonBit source (default: generated_page.mbt next to config)",
    "  --package <path>      Moon package to build or run (default: config directory)",
    "  --orbit-build <path>  Moon package for the generator (default: orbit-build)",
    "  --moon <command>      Moon executable (default: moon)",
    "  --workspace <path>    Working directory for Moon (default: current directory)",
    "  --plugin-dir <path>   Development-only plugin root passed as ORBIT_PLUGIN_DIRECTORY",
    "  --json                Emit structured diagnostics for the wrapper",
    "  --binary <path>       Executable copied by package",
    "  --out-dir <path>      Package output directory (default: dist)",
    "  --runtime-dir <path>  Optional WebView runtime files copied by package",
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
  const output = resolve(
    workspace,
    values.output ?? `${dirname(config)}/generated_page.mbt`,
  );
  return {
    command,
    workspace,
    config,
    output,
    packagePath: values.package ?? dirname(config),
    orbitBuild: values["orbit-build"] ?? "orbit-build",
    moon: values.moon ?? "moon",
    pluginDir: values["plugin-dir"] ? resolve(workspace, values["plugin-dir"]) : undefined,
    binary: values.binary ? resolve(workspace, values.binary) : undefined,
    outDir: resolve(workspace, values["out-dir"] ?? "dist"),
    runtimeDir: values["runtime-dir"] ? resolve(workspace, values["runtime-dir"]) : undefined,
    json: values.json ?? false,
  };
}

function runMoon(invocation, args) {
  const result = spawnSync(invocation.moon, args, {
    cwd: invocation.workspace,
    stdio: "inherit",
    env: invocation.pluginDir
      ? { ...process.env, ORBIT_PLUGIN_DIRECTORY: invocation.pluginDir }
      : process.env,
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

export function moonCommands(invocation) {
  const generate = [
    "run",
    "--target",
    "native",
    invocation.orbitBuild,
    invocation.config,
    invocation.output,
  ];
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

function packageApplication(invocation) {
  if (!invocation.binary) {
    throw new Error("package requires --binary <path>");
  }
  if (!existsSync(invocation.binary)) {
    throw new Error(`package binary does not exist: ${invocation.binary}`);
  }
  mkdirSync(invocation.outDir, { recursive: true });
  const binaryDir = resolve(invocation.outDir, "bin");
  mkdirSync(binaryDir, { recursive: true });
  cpSync(invocation.binary, resolve(binaryDir, basename(invocation.binary)));
  const appRoot = dirname(invocation.config);
  const plugins = resolve(appRoot, "plugins");
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
    format: 1,
    orbit: "0.1.0-alpha.1",
    pluginAbi: 1,
    moonview: "0.1.0-beta.3",
    executable: `bin/${basename(invocation.binary)}`,
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

  for (const command of moonCommands(invocation)) {
    if (!runMoon(invocation, command)) {
      return;
    }
  }
  if (invocation.command === "package") {
    try {
      packageApplication(invocation);
    } catch (error) {
      if (invocation.json) {
        environment.stdout.write(`${JSON.stringify({ code: "package_failed", message: error.message })}\n`);
      } else {
        environment.stdout.write(`orbit: ${error.message}\n`);
      }
      process.exitCode = 2;
      return;
    }
  }
  if (invocation.json) {
    environment.stdout.write(`${JSON.stringify({ code: "ok", command: invocation.command, config: invocation.config })}\n`);
  }
}
