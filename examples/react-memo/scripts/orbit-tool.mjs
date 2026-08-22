import { existsSync } from "node:fs"
import { dirname, relative, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { spawnSync } from "node:child_process"

const project = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const repository = resolve(project, "../..")
const localBuilder = resolve(repository, "orbit-build/moon.pkg")
const localCli = resolve(repository, "orbit-cli/bin/orbit.mjs")
const command = process.argv[2]
const extraArgs = process.argv.slice(3)

if (!new Set(["dev", "diagnose", "generate", "bindings", "build", "run"]).has(command)) {
  process.stderr.write(
    "usage: node scripts/orbit-tool.mjs <dev|diagnose|generate|bindings|build|run>\n",
  )
  process.exit(2)
}

function run(executable, args, cwd = project) {
  const result = spawnSync(executable, args, {
    cwd,
    stdio: "inherit",
  })
  if (result.error) throw result.error
  if (result.status !== 0) process.exit(result.status ?? 1)
}

function repositoryPath(path) {
  return relative(repository, resolve(project, path)).replaceAll("\\", "/")
}

if (command === "dev" && existsSync(localCli)) {
  run(process.execPath, [localCli, "dev", ...extraArgs])
  process.exit(0)
}

if (command === "dev" || command === "diagnose" || !existsSync(localBuilder)) {
  run("pnpm", ["exec", "orbit", command, ...extraArgs])
  process.exit(0)
}

if (command === "build" || command === "run") {
  run("pnpm", ["build"])
}

const generatorArgs = [
  "-C",
  repository,
  "run",
  "--target",
  "native",
  "orbit-build",
]

if (command === "bindings") generatorArgs.push("bindings")
generatorArgs.push(
  repositoryPath("orbit.conf.json"),
  repositoryPath(command === "bindings" ? "orbit-bindings.mjs" : "generated_page.mbt"),
)
run("moon", generatorArgs)

if (command === "build") run("moon", ["build", "--target", "native"])
if (command === "run") run("moon", ["run", "--target", "native", "."])
