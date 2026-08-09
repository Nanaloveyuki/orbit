import { chmodSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import process from "node:process";
import { compatibilityProfile, packageIntegrity, verifyPackage } from "../src/cli.mjs";
import { buildLinuxPackage, verifyLinuxPackageArtifact } from "../src/linux-packages.mjs";

const [format, workDirectory] = process.argv.slice(2);
if (!format || !workDirectory) {
  throw new Error("usage: node linux-native-fixture.mjs <deb|rpm|arch> <work-directory>");
}

const root = resolve(workDirectory);
rmSync(root, { recursive: true, force: true });
const packageDirectory = resolve(root, "package");
const outputDirectory = resolve(root, "artifacts");
mkdirSync(resolve(packageDirectory, "bin"), { recursive: true });
mkdirSync(resolve(packageDirectory, "icons"), { recursive: true });
writeFileSync(
  resolve(packageDirectory, "bin", "orbit-native-fixture"),
  "#!/bin/sh\nprintf '%s\\n' orbit-native-fixture\n",
);
chmodSync(resolve(packageDirectory, "bin", "orbit-native-fixture"), 0o755);
writeFileSync(resolve(packageDirectory, "icons", "128x128.png"), "fixture icon");

const manifest = {
  format: 3,
  compatibility: { ...compatibilityProfile },
  target: { platform: "linux", arch: "x64" },
  configuration: { schemaVersion: 2, fingerprint: "fixture" },
  application: {
    identifier: "dev.orbit.nativefixture",
    name: "Orbit Native Fixture",
    product_name: "Orbit Native Fixture",
    publisher: "Orbit Project",
    version: "0.1.0",
  },
  bundle: {
    icons: ["icons/128x128.png"],
    linux: {
      package_name: "orbit-native-fixture",
      summary: "Orbit native package fixture",
      description: "Validates Orbit Linux native package construction.",
      license: "Apache-2.0",
      homepage: "https://github.com/Nanaloveyuki/orbit",
      maintainer: "Orbit Project <orbit@example.com>",
      category: "Utility",
      deb: {
        depends: ["libgtk-3-0", "libwebkit2gtk-4.1-0"],
        section: "utils",
        priority: "optional",
      },
      rpm: { requires: ["gtk3", "webkit2gtk4.1"] },
      arch: { depends: ["gtk3", "webkit2gtk-4.1"] },
    },
  },
  windows: { webview_install_mode: "skip" },
  build: { profile: "release" },
  executable: "bin/orbit-native-fixture",
  executableDiscovered: false,
  plugins: null,
  pluginDeclarations: [],
  runtime: null,
};
manifest.integrity = packageIntegrity(packageDirectory);
writeFileSync(
  resolve(packageDirectory, "orbit-package.json"),
  `${JSON.stringify(manifest, null, 2)}\n`,
);
verifyPackage(packageDirectory);

const result = buildLinuxPackage({
  packageDir: packageDirectory,
  outDir: outputDirectory,
  format,
  release: "1",
  signCommand: undefined,
  dpkgDeb: "dpkg-deb",
  rpmbuild: "rpmbuild",
  makepkg: "makepkg",
}, manifest);
verifyLinuxPackageArtifact(result.artifact, result.metadataPath, compatibilityProfile);
writeFileSync(resolve(root, "result.json"), `${JSON.stringify(result)}\n`);
