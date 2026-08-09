import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmodSync,
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  statSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";

export const linuxPackageFormats = new Set(["deb", "rpm", "arch"]);

const architectureNames = Object.freeze({
  deb: Object.freeze({ x64: "amd64", arm64: "arm64" }),
  rpm: Object.freeze({ x64: "x86_64", arm64: "aarch64" }),
  arch: Object.freeze({ x64: "x86_64", arm64: "aarch64" }),
});

function sha256File(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function safeLine(value, label, { optional = false } = {}) {
  if (value == null && optional) return null;
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`Linux package ${label} must be a non-empty string`);
  }
  const normalized = value.trim();
  if (/[\0\r\n]/.test(normalized)) {
    throw new Error(`Linux package ${label} must not contain control lines`);
  }
  return normalized;
}

function safeHomepage(value) {
  const homepage = safeLine(value, "homepage", { optional: true });
  if (homepage === null) return null;
  let parsed;
  try {
    parsed = new URL(homepage);
  } catch {
    throw new Error("Linux package homepage must be an HTTP or HTTPS URL");
  }
  if (!new Set(["http:", "https:"]).has(parsed.protocol) || parsed.username || parsed.password) {
    throw new Error("Linux package homepage must be an HTTP or HTTPS URL without credentials");
  }
  return parsed.href;
}

function safePackageName(value) {
  const name = safeLine(value, "package_name");
  if (!/^[a-z0-9][a-z0-9+.-]*$/.test(name)) {
    throw new Error("Linux package package_name must use lowercase ASCII letters, digits, plus, dot or dash");
  }
  return name;
}

function safeIdentifier(value) {
  const identifier = safeLine(value, "application identifier");
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(identifier) || !identifier.includes(".")) {
    throw new Error("Linux package application identifier is not a safe dotted identifier");
  }
  return identifier;
}

function safeRelease(value) {
  const release = String(value ?? "1");
  if (!/^[1-9][0-9]*$/.test(release)) {
    throw new Error("Linux package release must be a positive integer");
  }
  return release;
}

function safeVersion(value, format) {
  const version = safeLine(value, "application version");
  if (!/^[0-9][A-Za-z0-9.+_-]*$/.test(version)) {
    throw new Error("Linux package application version must start with a digit and use ASCII version characters");
  }
  if (format === "deb") return version.replaceAll("_", "+").replace("-", "~");
  if (format === "rpm") return version.replaceAll("-", "~").replaceAll("_", ".");
  return version.replaceAll("-", "_");
}

function safeCategory(value) {
  const category = safeLine(value, "category");
  if (!/^[A-Za-z][A-Za-z0-9-]*$/.test(category)) {
    throw new Error("Linux package category must be one freedesktop category token");
  }
  return category;
}

function safeDependency(value, label) {
  const dependency = safeLine(value, label);
  if (!/^[A-Za-z0-9][A-Za-z0-9+._:@%<>=|()~ -]*$/.test(dependency)) {
    throw new Error(`Linux package ${label} contains unsupported characters`);
  }
  return dependency;
}

function dependencyList(value, label) {
  if (!Array.isArray(value)) {
    throw new Error(`Linux package ${label} must be an array`);
  }
  return value.map((dependency) => safeDependency(dependency, label));
}

function formatConfiguration(linux, format) {
  const configuration = linux?.[format];
  if (!configuration || typeof configuration !== "object" || Array.isArray(configuration)) {
    throw new Error(`Linux package format ${format} is not configured in bundle.linux`);
  }
  if (format === "deb") {
    const section = safeLine(configuration.section, "deb.section");
    const priority = safeLine(configuration.priority, "deb.priority");
    if (!/^[a-z0-9][a-z0-9+.-]*$/.test(section)) {
      throw new Error("Linux package deb.section contains unsupported characters");
    }
    if (!new Set(["required", "important", "standard", "optional", "extra"]).has(priority)) {
      throw new Error("Linux package deb.priority is not a Debian priority");
    }
    return {
      depends: dependencyList(configuration.depends, "deb.depends"),
      section,
      priority,
    };
  }
  if (format === "rpm") {
    return { requires: dependencyList(configuration.requires, "rpm.requires") };
  }
  return { depends: dependencyList(configuration.depends, "arch.depends") };
}

export function linuxArchitecture(format, architecture) {
  const mapped = architectureNames[format]?.[architecture];
  if (!mapped) {
    throw new Error(`Linux package format ${format} does not support architecture ${architecture}`);
  }
  return mapped;
}

export function normalizedLinuxPackage(packageManifest, format, release = "1") {
  if (!linuxPackageFormats.has(format)) {
    throw new Error(`unsupported Linux package format: ${format}`);
  }
  if (packageManifest?.target?.platform !== "linux") {
    throw new Error("linux-package requires a Linux directory package");
  }
  const linux = packageManifest?.bundle?.linux;
  if (!linux || typeof linux !== "object" || Array.isArray(linux)) {
    throw new Error("linux-package requires bundle.linux metadata in the directory package");
  }
  const identifier = safeIdentifier(packageManifest.application?.identifier);
  const architecture = linuxArchitecture(format, packageManifest.target?.arch);
  return {
    format,
    packageName: safePackageName(linux.package_name),
    identifier,
    name: safeLine(packageManifest.application?.product_name ?? packageManifest.application?.name, "application name"),
    sourceVersion: safeLine(packageManifest.application?.version, "application version"),
    version: safeVersion(packageManifest.application?.version, format),
    release: safeRelease(release),
    architecture,
    summary: safeLine(linux.summary, "summary"),
    description: safeLine(linux.description, "description"),
    license: safeLine(linux.license, "license"),
    homepage: safeHomepage(linux.homepage),
    maintainer: safeLine(linux.maintainer, "maintainer", { optional: true }),
    category: safeCategory(linux.category),
    formatConfiguration: formatConfiguration(linux, format),
  };
}

function packagePath(packageDirectory, relativePath) {
  if (
    typeof relativePath !== "string" ||
    relativePath.length === 0 ||
    relativePath === ".." ||
    relativePath.startsWith("../") ||
    relativePath.includes("\\")
  ) {
    throw new Error(`invalid Linux package payload path: ${relativePath}`);
  }
  const path = resolve(packageDirectory, relativePath);
  const pathRelative = relative(packageDirectory, path);
  if (pathRelative === ".." || pathRelative.startsWith(`..${sep}`) || isAbsolute(pathRelative)) {
    throw new Error(`Linux package payload escapes package directory: ${relativePath}`);
  }
  return path;
}

function writeExecutable(path, content) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content);
  chmodSync(path, 0o755);
}

function iconDestination(icon, identifier) {
  const name = basename(icon);
  const png = /^(16|32|48|64|128|256|512|1024)x\1\.png$/.exec(name);
  if (png) {
    return `usr/share/icons/hicolor/${png[1]}x${png[1]}/apps/${identifier}.png`;
  }
  if (name === "icon.svg") {
    return `usr/share/icons/hicolor/scalable/apps/${identifier}.svg`;
  }
  return null;
}

function desktopValue(value) {
  return value.replaceAll("\\", "\\\\");
}

export function createLinuxInstallTree(packageDirectory, root, packageManifest, normalized) {
  if (packageManifest.runtime != null) {
    throw new Error("linux-package does not support a bundled WebView runtime");
  }
  const installedPackage = resolve(root, "usr", "lib", normalized.identifier);
  mkdirSync(installedPackage, { recursive: true });
  cpSync(packageDirectory, installedPackage, { recursive: true });
  chmodSync(packagePath(installedPackage, packageManifest.executable), 0o755);

  const launcher = resolve(root, "usr", "bin", normalized.packageName);
  writeExecutable(
    launcher,
    `#!/bin/sh\nset -eu\nexec /usr/lib/${normalized.identifier}/${packageManifest.executable} "$@"\n`,
  );

  let hasIcon = false;
  for (const icon of packageManifest?.bundle?.icons ?? []) {
    const destination = iconDestination(icon, normalized.identifier);
    if (!destination) continue;
    const source = packagePath(packageDirectory, icon);
    if (!existsSync(source) || !statSync(source).isFile()) {
      throw new Error(`Linux package icon is missing: ${icon}`);
    }
    const target = resolve(root, destination);
    mkdirSync(dirname(target), { recursive: true });
    cpSync(source, target);
    hasIcon = true;
  }

  const desktop = [
    "[Desktop Entry]",
    "Type=Application",
    `Name=${desktopValue(normalized.name)}`,
    `Comment=${desktopValue(normalized.summary)}`,
    `Exec=${normalized.packageName}`,
    ...(hasIcon ? [`Icon=${normalized.identifier}`] : []),
    "Terminal=false",
    `Categories=${normalized.category};`,
    "",
  ].join("\n");
  const desktopPath = resolve(root, "usr", "share", "applications", `${normalized.identifier}.desktop`);
  mkdirSync(dirname(desktopPath), { recursive: true });
  writeFileSync(desktopPath, desktop);
  return { launcher, desktopPath, hasIcon };
}

function directorySize(path) {
  let bytes = 0;
  for (const entry of readdirSync(path, { withFileTypes: true })) {
    const candidate = resolve(path, entry.name);
    if (entry.isDirectory()) bytes += directorySize(candidate);
    else if (entry.isFile()) bytes += statSync(candidate).size;
  }
  return bytes;
}

export function debControl(normalized, installedBytes) {
  if (!normalized.maintainer) {
    throw new Error("Debian packages require bundle.linux.maintainer");
  }
  if (!/^[^<>]+ <[^<>\s]+@[^<>\s]+>$/.test(normalized.maintainer)) {
    throw new Error("Debian package maintainer must use Name <email> form");
  }
  const lines = [
    `Package: ${normalized.packageName}`,
    `Version: ${normalized.version}-${normalized.release}`,
    `Section: ${normalized.formatConfiguration.section}`,
    `Priority: ${normalized.formatConfiguration.priority}`,
    `Architecture: ${normalized.architecture}`,
    `Installed-Size: ${Math.ceil(installedBytes / 1024)}`,
    `Maintainer: ${normalized.maintainer}`,
    ...(normalized.homepage ? [`Homepage: ${normalized.homepage}`] : []),
    ...(normalized.formatConfiguration.depends.length > 0
      ? [`Depends: ${normalized.formatConfiguration.depends.join(", ")}`]
      : []),
    `Description: ${normalized.summary}`,
    ` ${normalized.description}`,
    "",
  ];
  return lines.join("\n");
}

function specText(value) {
  return value.replaceAll("%", "%%");
}

function shellSingleQuoted(value) {
  return `'${value.replaceAll("'", "'\\''")}'`;
}

function installedFilePaths(root) {
  const paths = [];
  function collect(directory, prefix = "") {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const relativePath = prefix ? `${prefix}/${entry.name}` : entry.name;
      const candidate = resolve(directory, entry.name);
      if (entry.isDirectory()) collect(candidate, relativePath);
      else if (entry.isFile()) paths.push(`/${relativePath}`);
    }
  }
  collect(root);
  return paths.sort();
}

export function rpmSpec(normalized, root) {
  const files = installedFilePaths(root).map((path) => specText(path));
  return [
    "%global _build_id_links none",
    "%global __os_install_post %{nil}",
    `Name: ${normalized.packageName}`,
    `Version: ${normalized.version}`,
    `Release: ${normalized.release}`,
    `Summary: ${specText(normalized.summary)}`,
    `License: ${specText(normalized.license)}`,
    ...(normalized.homepage ? [`URL: ${specText(normalized.homepage)}`] : []),
    `BuildArch: ${normalized.architecture}`,
    ...normalized.formatConfiguration.requires.map((dependency) => `Requires: ${specText(dependency)}`),
    "",
    "%description",
    specText(normalized.description),
    "",
    "%install",
    "mkdir -p \"%{buildroot}\"",
    `cp -a ${shellSingleQuoted(root)}/. \"%{buildroot}/\"`,
    "",
    "%files",
    ...files,
    "",
  ].join("\n");
}

function bashArray(values) {
  return `(${values.map((value) => shellSingleQuoted(value)).join(" ")})`;
}

export function archPkgbuild(normalized, root) {
  return [
    `pkgname=${shellSingleQuoted(normalized.packageName)}`,
    `pkgver=${shellSingleQuoted(normalized.version)}`,
    `pkgrel=${normalized.release}`,
    `pkgdesc=${shellSingleQuoted(normalized.summary)}`,
    ...(normalized.homepage ? [`url=${shellSingleQuoted(normalized.homepage)}`] : []),
    `license=${bashArray([normalized.license])}`,
    `arch=${bashArray([normalized.architecture])}`,
    `depends=${bashArray(normalized.formatConfiguration.depends)}`,
    "options=('!strip' '!debug')",
    "",
    "package() {",
    "  mkdir -p \"$pkgdir\"",
    `  cp -a ${shellSingleQuoted(root)}/. \"$pkgdir/\"`,
    "}",
    "",
  ].join("\n");
}

function runTool(command, args, options = {}) {
  const result = spawnSync(command, args, { stdio: "inherit", ...options });
  if (result.error) {
    throw new Error(`failed to start ${command}: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(`${command} failed with exit code ${result.status ?? 1}`);
  }
}

function findSingleArtifact(root, extension) {
  const matches = [];
  function collect(directory) {
    if (!existsSync(directory)) return;
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const candidate = resolve(directory, entry.name);
      if (entry.isDirectory()) collect(candidate);
      else if (entry.isFile() && entry.name.endsWith(extension)) matches.push(candidate);
    }
  }
  collect(root);
  if (matches.length !== 1) {
    throw new Error(`native packager produced ${matches.length} ${extension} artifacts; expected one`);
  }
  return matches[0];
}

function normalizeTimestamps(root) {
  const epoch = new Date(1000);
  function visit(path) {
    if (statSync(path).isDirectory()) {
      for (const entry of readdirSync(path)) visit(resolve(path, entry));
    }
    utimesSync(path, epoch, epoch);
  }
  visit(root);
}

function artifactFilename(normalized) {
  if (normalized.format === "deb") {
    return `${normalized.packageName}_${normalized.version}-${normalized.release}_${normalized.architecture}.deb`;
  }
  if (normalized.format === "rpm") {
    return `${normalized.packageName}-${normalized.version}-${normalized.release}.${normalized.architecture}.rpm`;
  }
  return `${normalized.packageName}-${normalized.version}-${normalized.release}-${normalized.architecture}.pkg.tar.zst`;
}

export function expandLinuxPackageSigningCommand(command, values) {
  for (const placeholder of ["artifact", "package_dir", "package_manifest"]) {
    if (!command.includes(`{${placeholder}}`)) {
      throw new Error(`Linux package sign-command must include {${placeholder}}`);
    }
  }
  const quote = process.platform === "win32"
    ? (value) => `"${value.replaceAll('"', '""')}"`
    : shellSingleQuoted;
  return command
    .replaceAll("{artifact}", quote(values.artifact))
    .replaceAll("{package_dir}", quote(values.packageDirectory))
    .replaceAll("{package_manifest}", quote(values.packageManifest));
}

function runSigningCommand(invocation, artifact) {
  if (!invocation.signCommand) return false;
  const command = expandLinuxPackageSigningCommand(invocation.signCommand, {
    artifact,
    packageDirectory: invocation.packageDir,
    packageManifest: resolve(invocation.packageDir, "orbit-package.json"),
  });
  runTool(command, [], { cwd: invocation.packageDir, shell: true });
  return true;
}

export function linuxPackageMetadataPath(artifact) {
  return `${artifact}.orbit-linux-package.json`;
}

function packageDescriptor(packageManifest) {
  return {
    format: packageManifest.format,
    compatibility: packageManifest.compatibility,
    target: packageManifest.target,
    configuration: packageManifest.configuration,
    integrityAlgorithm: packageManifest.integrity.algorithm,
  };
}

export function linuxPackageDescriptor(packageManifest, normalized, artifact, signingHookExecuted) {
  return {
    format: 1,
    artifact_type: "linux-package",
    backend: normalized.format,
    release: normalized.release,
    architecture: normalized.architecture,
    signing_hook_executed: signingHookExecuted,
    application: packageManifest.application,
    package: packageDescriptor(packageManifest),
    artifact: {
      file: basename(artifact),
      size: statSync(artifact).size,
      sha256: sha256File(artifact),
    },
  };
}

export function verifyLinuxPackageArtifact(
  artifact,
  metadataPath = linuxPackageMetadataPath(artifact),
  compatibilityProfile,
) {
  if (!existsSync(artifact) || !statSync(artifact).isFile()) {
    throw new Error(`Linux package artifact does not exist: ${artifact}`);
  }
  if (!existsSync(metadataPath) || !statSync(metadataPath).isFile()) {
    throw new Error(`Linux package metadata does not exist: ${metadataPath}`);
  }
  let metadata;
  try {
    metadata = JSON.parse(readFileSync(metadataPath, "utf8"));
  } catch {
    throw new Error("Linux package metadata is not valid JSON");
  }
  if (
    metadata?.format !== 1 ||
    metadata?.artifact_type !== "linux-package" ||
    !linuxPackageFormats.has(metadata?.backend) ||
    !/^[1-9][0-9]*$/.test(metadata?.release) ||
    typeof metadata?.architecture !== "string" ||
    typeof metadata?.signing_hook_executed !== "boolean" ||
    metadata?.package?.format !== 3 ||
    metadata?.package?.target?.platform !== "linux" ||
    metadata?.package?.configuration?.schemaVersion !== 2 ||
    metadata?.package?.integrityAlgorithm !== "sha256" ||
    metadata?.artifact?.file !== basename(artifact) ||
    !Number.isInteger(metadata?.artifact?.size) ||
    !/^[a-f0-9]{64}$/.test(metadata?.artifact?.sha256)
  ) {
    throw new Error("Linux package metadata is incomplete or incompatible");
  }
  if (JSON.stringify(metadata.package.compatibility) !== JSON.stringify(compatibilityProfile)) {
    throw new Error("Linux package compatibility profile is incompatible");
  }
  if (metadata.artifact.size !== statSync(artifact).size || metadata.artifact.sha256 !== sha256File(artifact)) {
    throw new Error("Linux package artifact integrity verification failed");
  }
  return metadata;
}

function pathInside(directory, path) {
  const pathRelative = relative(directory, path);
  return pathRelative.length === 0 || (
    !pathRelative.startsWith(`..${sep}`) && pathRelative !== ".." && !isAbsolute(pathRelative)
  );
}

export function buildLinuxPackage(invocation, packageManifest) {
  if (process.platform !== "linux") {
    throw new Error("linux-package must run on Linux with the selected distribution packager installed");
  }
  if (pathInside(invocation.packageDir, invocation.outDir)) {
    throw new Error("Linux package output directory must not be inside the directory package");
  }
  const normalized = normalizedLinuxPackage(packageManifest, invocation.format, invocation.release);
  mkdirSync(invocation.outDir, { recursive: true });
  const artifact = resolve(invocation.outDir, artifactFilename(normalized));
  const fixedArchDirectory = resolve(
    tmpdir(),
    `orbit-makepkg-${normalized.packageName}-${normalized.version}-${normalized.release}-${normalized.architecture}`,
  );
  let temporaryDirectory;
  if (normalized.format === "arch") {
    try {
      mkdirSync(fixedArchDirectory);
    } catch (error) {
      if (error?.code === "EEXIST") {
        throw new Error(`another Arch package build is using ${fixedArchDirectory}`);
      }
      throw error;
    }
    temporaryDirectory = fixedArchDirectory;
  } else {
    temporaryDirectory = mkdtempSync(join(tmpdir(), "orbit-linux-package-"));
  }
  try {
    const root = resolve(temporaryDirectory, "root");
    mkdirSync(root, { recursive: true });
    createLinuxInstallTree(invocation.packageDir, root, packageManifest, normalized);
    normalizeTimestamps(root);

    if (normalized.format === "deb") {
      const controlDirectory = resolve(root, "DEBIAN");
      mkdirSync(controlDirectory, { recursive: true });
      writeFileSync(resolve(controlDirectory, "control"), debControl(normalized, directorySize(root)));
      normalizeTimestamps(controlDirectory);
      runTool(invocation.dpkgDeb, ["--root-owner-group", "--build", root, artifact], {
        env: { ...process.env, SOURCE_DATE_EPOCH: "1" },
      });
    } else if (normalized.format === "rpm") {
      const spec = resolve(temporaryDirectory, "package.spec");
      const output = resolve(temporaryDirectory, "rpm-output");
      mkdirSync(output, { recursive: true });
      writeFileSync(spec, rpmSpec(normalized, root));
      runTool(invocation.rpmbuild, [
        "-bb",
        "--define", `_topdir ${resolve(temporaryDirectory, "rpmbuild")}`,
        "--define", `_rpmdir ${output}`,
        "--define", "_buildhost orbit",
        "--define", "use_source_date_epoch_as_buildtime 1",
        "--define", "clamp_mtime_to_source_date_epoch 1",
        spec,
      ], { env: { ...process.env, SOURCE_DATE_EPOCH: "1" } });
      renameSync(findSingleArtifact(output, ".rpm"), artifact);
    } else {
      const buildDirectory = resolve(temporaryDirectory, "arch");
      const output = resolve(temporaryDirectory, "arch-output");
      mkdirSync(buildDirectory, { recursive: true });
      mkdirSync(output, { recursive: true });
      writeFileSync(resolve(buildDirectory, "PKGBUILD"), archPkgbuild(normalized, root));
      runTool(invocation.makepkg, ["--nodeps", "--force", "--noconfirm", "--cleanbuild"], {
        cwd: buildDirectory,
        env: {
          ...process.env,
          PKGDEST: output,
          SOURCE_DATE_EPOCH: "1",
        },
      });
      renameSync(findSingleArtifact(output, ".pkg.tar.zst"), artifact);
    }

    const signingHookExecuted = runSigningCommand(invocation, artifact);
    const metadataPath = linuxPackageMetadataPath(artifact);
    writeFileSync(metadataPath, `${JSON.stringify(
      linuxPackageDescriptor(packageManifest, normalized, artifact, signingHookExecuted),
      null,
      2,
    )}\n`);
    return { artifact, metadataPath };
  } finally {
    rmSync(temporaryDirectory, { recursive: true, force: true });
  }
}
