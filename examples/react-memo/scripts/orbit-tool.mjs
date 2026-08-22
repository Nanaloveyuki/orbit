import { existsSync, rmSync, writeFileSync } from "node:fs"
import { dirname, relative, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { spawnSync } from "node:child_process"

const project = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const repository = resolve(project, "../..")
const localBuilder = resolve(repository, "orbit-build/moon.pkg")
const localCli = resolve(repository, "orbit-cli/bin/orbit.mjs")
const command = process.argv[2]
const extraArgs = process.argv.slice(3)

if (!new Set(["dev", "diagnose", "generate", "bindings", "build", "run", "android"]).has(command)) {
  process.stderr.write(
    "usage: node scripts/orbit-tool.mjs <dev|diagnose|generate|bindings|build|run|android>\n",
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

function androidExecutable(name) {
  const suffix = process.platform === "win32" ? ".exe" : ""
  const sdk = process.env.ANDROID_SDK_ROOT || process.env.ANDROID_HOME ||
    (process.env.LOCALAPPDATA ? resolve(process.env.LOCALAPPDATA, "Android", "Sdk") : undefined)
  if (sdk) {
    const executable = resolve(sdk, "platform-tools", `${name}${suffix}`)
    if (existsSync(executable)) return executable
  }
  return `${name}${suffix}`
}

if (command === "android") {
  const mode = extraArgs[0] && !extraArgs[0].startsWith("--") ? extraArgs.shift() : "dev"
  if (!new Set(["dev", "build", "test"]).has(mode)) {
    process.stderr.write("usage: pnpm run orbit android <dev|build|test> [--device <serial>]\n")
    process.exit(2)
  }
  const deviceIndex = extraArgs.indexOf("--device")
  const device = deviceIndex >= 0 ? extraArgs[deviceIndex + 1] : undefined
  if (deviceIndex >= 0 && !device) {
    process.stderr.write("--device requires an adb serial\n")
    process.exit(2)
  }

  const workspace = resolve(project, "moon.work")
  const ownsWorkspace = existsSync(localBuilder) && !existsSync(workspace)
  if (ownsWorkspace) {
    writeFileSync(workspace, 'members = [".", "../.."]\n', { flag: "wx" })
    process.on("exit", () => rmSync(workspace, { force: true }))
  }

  run("pnpm", ["build"])
  if (existsSync(localBuilder)) {
    run("moon", [
      "-C",
      repository,
      "run",
      "--target",
      "native",
      "orbit-build",
      "--",
      "android",
      repositoryPath("orbit.conf.json"),
      repositoryPath("android/generated_page.mbt"),
    ])
  } else {
    run("pnpm", [
      "exec",
      "orbit",
      "generate",
      "--android",
      "--config",
      "orbit.conf.json",
      "--output",
      "android/generated_page.mbt",
    ])
  }

  const androidRoot = resolve(project, "android")
  const wrapper = resolve(androidRoot, process.platform === "win32" ? "gradlew.bat" : "gradlew")
  const gradle = process.env.ORBIT_GRADLE || (existsSync(wrapper) ? wrapper : "gradle")
  const gradleTasks = [":app:assembleDebug"]
  if (mode === "test") gradleTasks.push(":app:assembleDebugAndroidTest")
  const gradleArgs = ["--no-daemon", "--console=plain", ...gradleTasks]
  if (process.platform === "win32") {
    run(process.env.ComSpec || "cmd.exe", ["/d", "/s", "/c", gradle, ...gradleArgs], androidRoot)
  } else {
    run(gradle, gradleArgs, androidRoot)
  }
  if (mode === "build") process.exit(0)

  const adb = androidExecutable("adb")
  const target = device ? ["-s", device] : []
  run(adb, [...target, "install", "-r", "-t", resolve(androidRoot, "app/build/outputs/apk/debug/app-debug.apk")])
  if (mode === "test") {
    run(adb, [...target, "install", "-r", "-t", resolve(androidRoot, "app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk")])
    run(adb, [
      ...target,
      "shell",
      "am",
      "instrument",
      "-w",
      "-r",
      "-e",
      "class",
      "dev.orbit.reactmemo.OrbitMemoInstrumentedTest",
      "dev.orbit.reactmemo.test/androidx.test.runner.AndroidJUnitRunner",
    ])
    process.exit(0)
  }
  run(adb, [...target, "shell", "am", "force-stop", "dev.orbit.reactmemo"])
  run(adb, [...target, "shell", "am", "start", "-W", "-n", "dev.orbit.reactmemo/.MainActivity"])
  process.exit(0)
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
