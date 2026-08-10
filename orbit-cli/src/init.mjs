import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join, resolve } from "node:path";

function normalizedSlug(directory) {
  const slug = basename(directory)
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(slug)) {
    throw new Error("init directory name must contain a 1-64 character ASCII application name");
  }
  return slug;
}

function defaultDisplayName(slug) {
  return slug.split("-")
    .filter(Boolean)
    .map(part => part[0].toUpperCase() + part.slice(1))
    .join(" ");
}

function checkedDisplayName(value) {
  const name = value.trim();
  if (name.length === 0 || name.length > 100 || /[\u0000-\u001f\u007f]/.test(name)) {
    throw new Error("--name must be a non-empty display name of at most 100 characters");
  }
  return name;
}

function checkedIdentifier(value) {
  const identifier = value.trim();
  if (identifier.length > 128 || !identifier.includes(".") ||
      !/^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+$/.test(identifier)) {
    throw new Error("--identifier must be a dotted ASCII application identifier");
  }
  return identifier;
}

function checkedModuleName(value) {
  const moduleName = value.trim();
  const segments = moduleName.split("/");
  if (moduleName.length > 128 || segments.length !== 2 ||
      segments.some(segment =>
        !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(segment) ||
        segment === "." || segment === "..")) {
    throw new Error("--module must use the MoonBit owner/name form");
  }
  return moduleName;
}

function checkedVersion(value, subject) {
  if (!/^[0-9A-Za-z][0-9A-Za-z.+-]{0,127}$/.test(value)) {
    throw new Error(`${subject} template version is invalid`);
  }
  return value;
}

function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function applicationFiles({ slug, name, identifier, moduleName, orbitVersion, cliVersion }) {
  const command = `${slug}.ping`;
  const config = {
    schema_version: 2,
    app: {
      identifier,
      name,
      version: "0.1.0",
      product_name: name,
      windows: [{
        label: "main",
        title: name,
        width: 1024,
        height: 720,
        entry: "assets/index.html",
        visible: true,
        resizable: true,
      }],
    },
    bundle: {
      icons: [],
      windows: { webview_install_mode: "embed_bootstrapper" },
    },
    web: {
      embedded: {
        csp: "default-src 'self'; script-src 'self'; style-src 'self'",
      },
    },
    build: {},
    capabilities: [{
      identifier: "main-window-commands",
      effect: "allow",
      principals: [{ kind: "window", identifier: "main" }],
      scopes: [],
      commands: [command],
    }],
    plugins: [],
  };
  const packageManifest = {
    name: slug,
    private: true,
    scripts: {
      "orbit:generate": "orbit generate",
      "orbit:bindings": "orbit bindings",
      "orbit:run": "orbit run",
      "orbit:dev": "orbit dev",
      "orbit:build": "orbit build",
      "orbit:package": "orbit package --release --out-dir dist",
    },
    devDependencies: {
      "@nanaloveyuki/orbit-cli": cliVersion,
    },
  };
  const displayName = escapeHtml(name);
  return new Map([
    [".gitignore", [
      "_build/",
      ".mooncakes/",
      ".repos/",
      "node_modules/",
      "dist/",
      "artifacts/",
      "*.WebView2/",
      "",
    ].join("\n")],
    ["moon.mod", [
      `name = ${JSON.stringify(moduleName)}`,
      "",
      'version = "0.1.0"',
      "",
      `description = ${JSON.stringify(`${name} desktop application built with Orbit.`)}`,
      "",
      'license = "Apache-2.0"',
      "",
      'preferred_target = "native"',
      "",
      "import {",
      `  "Nanaloveyuki/orbit@${orbitVersion}",`,
      "}",
      "",
    ].join("\n")],
    ["moon.pkg", [
      "import {",
      '  "Nanaloveyuki/orbit/orbit-core" @core,',
      '  "Nanaloveyuki/orbit/orbit-ipc" @ipc,',
      '  "Nanaloveyuki/orbit/orbit-plugin" @plugin,',
      '  "Nanaloveyuki/orbit/orbit-runtime" @runtime,',
      '  "Nanaloveyuki/orbit/orbit-runtime-moonview" @moonview_runtime,',
      "}",
      "",
      'supported_targets = "native"',
      "",
      'pkgtype(kind: "executable")',
      "",
    ].join("\n")],
    ["main.mbt", [
      "///|",
      "fn[T] fail(message : String) -> T {",
      `  abort(${JSON.stringify(`${slug}: `)} + message)`,
      "}",
      "",
      "///|",
      "fn command_registry() -> @ipc.CommandRegistry raise @ipc.IpcError {",
      "  let registry = @ipc.CommandRegistry::new()",
      `  registry.register_json(@ipc.CommandName::new(${JSON.stringify(command)}), _payload => {`,
      '    Ok({ "message": "Orbit IPC is ready." })',
      "  })",
      "  registry",
      "}",
      "",
      "///|",
      "fn main {",
      "  let ipc_registry = command_registry() catch {",
      '    _ => fail("could not register IPC commands")',
      "  }",
      "  let ipc_policy = configured_ipc_policy() catch {",
      '    _ => fail("could not configure IPC permissions")',
      "  }",
      "  let desktop_options = @core.DesktopOptions::new(",
      "    windows=configured_windows(),",
      "    ipc_registry=Some(ipc_registry),",
      "    ipc_policy=Some(ipc_policy),",
      "    plugin_declarations=configured_plugins(),",
      "  ) catch {",
      '    _ => fail("could not create desktop options")',
      "  }",
      "  let factory = @moonview_runtime.MoonViewRuntimeFactory::new()",
      "    as &@runtime.RuntimeFactory",
      "  ignore(",
      "    @core.run(factory, desktop_options) catch {",
      '      _ => fail("desktop application terminated with an error")',
      "    },",
      "  )",
      "}",
      "",
    ].join("\n")],
    ["orbit.conf.json", `${JSON.stringify(config, null, 2)}\n`],
    ["package.json", `${JSON.stringify(packageManifest, null, 2)}\n`],
    ["assets/index.html", [
      "<!doctype html>",
      '<html lang="en">',
      "<head>",
      '  <meta charset="utf-8">',
      '  <meta name="viewport" content="width=device-width, initial-scale=1">',
      `  <title>${displayName}</title>`,
      '  <link rel="stylesheet" href="style.css">',
      "</head>",
      "<body>",
      "  <header>",
      `    <strong>${displayName}</strong>`,
      '    <span id="runtime-status">Orbit desktop</span>',
      "  </header>",
      "  <main>",
      "    <p>MoonBit backend and the native WebView are connected.</p>",
      '    <button id="ping" type="button">Test IPC</button>',
      '    <output id="result" aria-live="polite">Ready</output>',
      "  </main>",
      '  <script src="app.js"></script>',
      "</body>",
      "</html>",
      "",
    ].join("\n")],
    ["assets/app.js", [
      'const button = document.querySelector("#ping");',
      'const result = document.querySelector("#result");',
      "",
      'button.addEventListener("click", async () => {',
      "  button.disabled = true;",
      '  result.textContent = "Calling MoonBit...";',
      "  try {",
      `    const response = await window.__ORBIT__.invoke(${JSON.stringify(command)});`,
      "    result.textContent = response.message;",
      "  } catch (error) {",
      '    result.textContent = `IPC error: ${error.code ?? "unknown"}`;',
      "  } finally {",
      "    button.disabled = false;",
      "  }",
      "});",
      "",
    ].join("\n")],
    ["assets/style.css", [
      ":root {",
      '  font-family: "Segoe UI", system-ui, sans-serif;',
      "  color: #17202a;",
      "  background: #f4f6f8;",
      "}",
      "",
      "* { box-sizing: border-box; }",
      "",
      "body {",
      "  margin: 0;",
      "  min-height: 100vh;",
      "}",
      "",
      "header {",
      "  height: 56px;",
      "  display: flex;",
      "  align-items: center;",
      "  justify-content: space-between;",
      "  padding: 0 24px;",
      "  border-bottom: 1px solid #d5dce3;",
      "  background: #ffffff;",
      "}",
      "",
      "#runtime-status { color: #52606d; }",
      "",
      "main {",
      "  max-width: 720px;",
      "  margin: 72px auto;",
      "  padding: 0 24px;",
      "}",
      "",
      "p {",
      "  color: #52606d;",
      "  line-height: 1.6;",
      "}",
      "",
      "button {",
      "  width: 112px;",
      "  height: 40px;",
      "  border: 1px solid #1769aa;",
      "  background: #1769aa;",
      "  color: #ffffff;",
      "  font: inherit;",
      "  cursor: pointer;",
      "}",
      "",
      "button:hover { background: #12558a; }",
      "button:disabled { cursor: wait; opacity: 0.6; }",
      "",
      "output {",
      "  display: block;",
      "  margin-top: 20px;",
      "  min-height: 24px;",
      "  font-family: ui-monospace, Consolas, monospace;",
      "}",
      "",
    ].join("\n")],
    ["README.md", [
      `# ${name}`,
      "",
      "This application was created with Orbit.",
      "",
      "## Run",
      "",
      "```sh",
      "moon update",
      "npm install",
      "npm run orbit:run",
      "```",
      "",
      "The first run generates `generated_page.mbt`, builds the native executable,",
      "and opens the desktop window. Commit the generated MoonBit source so changes",
      "to embedded resources and capabilities remain reviewable.",
      "",
      "## Common commands",
      "",
      "```sh",
      "npm run orbit:generate",
      "npm run orbit:bindings",
      "npm run orbit:build",
      "npm run orbit:package",
      "```",
      "",
      "Configuration: `orbit.conf.json`",
      "",
    ].join("\n")],
  ]);
}

export function createApplication({
  directory,
  name,
  identifier,
  moduleName,
  orbitVersion,
  cliVersion,
}) {
  const target = resolve(directory);
  if (existsSync(target)) {
    throw new Error(`init target already exists: ${target}`);
  }
  const slug = normalizedSlug(target);
  const applicationName = checkedDisplayName(name ?? defaultDisplayName(slug));
  const applicationIdentifier = checkedIdentifier(identifier ?? `dev.orbit.${slug}`);
  const moonModule = checkedModuleName(moduleName ?? `local/${slug}`);
  if (!orbitVersion || !cliVersion) {
    throw new Error("init requires Orbit and CLI template versions");
  }
  const templateOrbitVersion = checkedVersion(orbitVersion, "Orbit");
  const templateCliVersion = checkedVersion(cliVersion, "CLI");

  const parent = dirname(target);
  mkdirSync(parent, { recursive: true });
  const staging = mkdtempSync(join(parent, ".orbit-init-"));
  try {
    const files = applicationFiles({
      slug,
      name: applicationName,
      identifier: applicationIdentifier,
      moduleName: moonModule,
      orbitVersion: templateOrbitVersion,
      cliVersion: templateCliVersion,
    });
    for (const [relativePath, contents] of files) {
      const destination = join(staging, relativePath);
      mkdirSync(dirname(destination), { recursive: true });
      writeFileSync(destination, contents, { encoding: "utf8", flag: "wx" });
    }
    renameSync(staging, target);
    return {
      directory: target,
      slug,
      name: applicationName,
      identifier: applicationIdentifier,
      module: moonModule,
      files: [...files.keys()],
    };
  } finally {
    if (existsSync(staging)) {
      rmSync(staging, { recursive: true, force: true });
    }
  }
}
