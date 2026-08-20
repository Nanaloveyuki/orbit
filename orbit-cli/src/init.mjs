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
    [".moon-version", "0.1.20260819\n"],
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
    [".github/workflows/windows-release.yml", [
      "name: Windows release",
      "",
      "on:",
      "  push:",
      "    tags: [\"v*\"]",
      "",
      "permissions:",
      "  contents: write",
      "  attestations: write",
      "  id-token: write",
      "",
      "jobs:",
      "  package:",
      "    runs-on: windows-latest",
      "    environment: release",
      "    steps:",
      "      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262",
      "        with:",
      "          fetch-depth: 0",
      "      - uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020",
      "        with:",
      "          node-version: 24",
      "      - name: Install MoonBit",
      "        shell: pwsh",
      "        run: |",
      "          $env:MOONBIT_INSTALL_VERSION = (Get-Content .moon-version -Raw).Trim()",
      "          Set-ExecutionPolicy RemoteSigned -Scope CurrentUser",
      "          irm https://cli.moonbitlang.com/install/powershell.ps1 | iex",
      "          \"$HOME\\.moon\\bin\" | Out-File -FilePath $env:GITHUB_PATH -Append",
      "      - name: Verify release inputs",
      "        shell: pwsh",
      "        run: |",
      "          $version = node -e \"const c=require('./orbit.conf.json'); process.stdout.write(c.app.version)\"",
      "          if ($env:GITHUB_REF_NAME -ne \"v$version\") {",
      "            throw \"Git tag $env:GITHUB_REF_NAME does not match orbit.conf.json version $version\"",
      "          }",
      "          moon version --all",
      "      - name: Install locked Node dependencies",
      "        run: npm ci",
      "      - name: Build and verify directory package",
      "        shell: pwsh",
      "        run: |",
      "          moon update",
      "          npx orbit package --release --out-dir dist",
      "          npx orbit verify-package --package-dir dist",
      "      - name: Build and verify signed installer",
      "        shell: pwsh",
      "        env:",
      "          ORBIT_WINDOWS_SIGN_COMMAND: ${{ secrets.ORBIT_WINDOWS_SIGN_COMMAND }}",
      "        run: |",
      "          if ([string]::IsNullOrWhiteSpace($env:ORBIT_WINDOWS_SIGN_COMMAND)) {",
      "            throw \"ORBIT_WINDOWS_SIGN_COMMAND must be configured for signed releases\"",
      "          }",
      "          npx orbit installer --package-dir dist --sign-command $env:ORBIT_WINDOWS_SIGN_COMMAND",
      "          $installer = (Get-ChildItem dist -Filter *-setup.exe | Select-Object -First 1).FullName",
      "          if (!$installer) { throw \"Orbit did not produce an installer\" }",
      "          npx orbit verify-installer --installer $installer",
      "          $signature = Get-AuthenticodeSignature -FilePath $installer",
      "          if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {",
      "            throw \"Installer Authenticode signature is not valid: $($signature.Status)\"",
      "          }",
      "          if (!$signature.SignerCertificate) { throw \"Installer has no signing certificate\" }",
      "          Get-ChildItem dist -File | Get-FileHash -Algorithm SHA256 | ForEach-Object {",
      "            \"$($_.Hash.ToLowerInvariant()) *$($_.Path.Substring((Resolve-Path dist).Path.Length + 1))\"",
      "          } | Set-Content -Encoding ascii dist/SHA256SUMS.txt",
      "      - name: Attest installer",
      "        uses: actions/attest-build-provenance@96b4a1ef7235a096b17240c259729fdd70c83d45",
      "        with:",
      "          subject-path: |",
      "            dist/*-setup.exe",
      "            dist/*.orbit-installer.json",
      "            dist/SHA256SUMS.txt",
      "      - name: Publish GitHub release",
      "        env:",
      "          GH_TOKEN: ${{ github.token }}",
      "        shell: pwsh",
      "        run: |",
      "          gh release create $env:GITHUB_REF_NAME --verify-tag --generate-notes dist/*-setup.exe dist/*.orbit-installer.json dist/SHA256SUMS.txt",
      "",
    ].join("\n")],
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
      "## Windows release",
      "",
      "Commit `package-lock.json` before releasing. The generated workflow in",
      "`.github/workflows/windows-release.yml` builds a signed installer only for a",
      "tag matching `orbit.conf.json` and verifies both the Orbit manifest and the",
      "Windows Authenticode signature. Configure the signing command and perform the",
      "manual acceptance steps in [`docs/windows-release.md`](docs/windows-release.md).",
      "",
      "Configuration: `orbit.conf.json`",
      "",
    ].join("\n")],
    ["docs/windows-release.md", [
      "# Windows Release",
      "",
      "`.github/workflows/windows-release.yml` is intentionally fail-closed. It runs",
      "only for a Git tag whose name is exactly `v` plus `app.version` in",
      "`orbit.conf.json`, builds a release directory package, builds an NSIS installer,",
      "verifies the Orbit descriptors, then verifies the installer Authenticode",
      "signature before publishing a GitHub Release.",
      "",
      "## One-Time Setup",
      "",
      "1. Run `npm install` locally and commit the resulting `package-lock.json`; the",
      "   workflow uses `npm ci` and will fail when the lockfile is absent or stale.",
      "2. Pin the MoonBit toolchain in `.moon-version`. Update it deliberately and",
      "   record `moon version --all` in the release pull request.",
      "3. Protect the `release` GitHub environment and add any certificate-provisioning",
      "   action required by the chosen signing provider before the installer step.",
      "4. Store `ORBIT_WINDOWS_SIGN_COMMAND` as an environment secret. It must include",
      "   `{installer}`, `{package_dir}`, and `{package_manifest}`. For example, after",
      "   securely provisioning a certificate to the runner:",
      "",
      "```text",
      "signtool sign /fd SHA256 /td SHA256 /tr https://timestamp.example {installer} {package_dir} {package_manifest}",
      "```",
      "",
      "The command is an application-maintainer controlled release secret. Do not accept",
      "it from pull requests or use `--allow-unsigned` for a release tag.",
      "",
      "## Release Checklist",
      "",
      "1. Update `app.version`, regenerate `generated_page.mbt`, and commit the config,",
      "   generated source, dependency lockfile, and application changes together.",
      "2. From a clean checkout, run `npm ci`, `moon update`, `npx orbit package --release`,",
      "   and `npx orbit verify-package --package-dir dist`.",
      "3. Run the Windows GUI acceptance flow for the application: install the signed",
      "   installer, launch it, exercise its critical workflow, close it, and uninstall it.",
      "4. Push the matching signed tag, for example `v0.1.0`. The workflow uploads the",
      "   installer, its `.orbit-installer.json` descriptor, and `SHA256SUMS.txt` to the",
      "   generated GitHub Release.",
      "5. Download the published installer as a normal user. Confirm the Windows publisher",
      "   dialog is trusted, re-run the application acceptance flow, and retain the CI run",
      "   URL with the release record.",
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
