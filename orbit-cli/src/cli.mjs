import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import process from "node:process";

const commands = new Set(["generate", "build", "dev"]);

export function usage() {
  return [
    "Usage: orbit <generate|build|dev> [options]",
    "",
    "Options:",
    "  --config <path>       Configuration file (default: orbit.conf.json)",
    "  --output <path>       Generated MoonBit source (default: generated_page.mbt next to config)",
    "  --package <path>      Moon package to build or run (default: config directory)",
    "  --orbit-build <path>  Moon package for the generator (default: orbit-build)",
    "  --moon <command>      Moon executable (default: moon)",
    "  --workspace <path>    Working directory for Moon (default: current directory)",
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
    ].includes(key)) {
      throw new Error(`unknown option: ${argument}`);
    }
    values[key] = optionValue(argv, index, argument);
    index += 1;
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
  };
}

function runMoon(invocation, args) {
  const result = spawnSync(invocation.moon, args, {
    cwd: invocation.workspace,
    stdio: "inherit",
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
  if (invocation.command === "build") {
    return [
      generate,
      ["run", "--target", "native", "--build-only", invocation.packagePath],
    ];
  }
  return [generate, ["run", "--target", "native", invocation.packagePath]];
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
}
