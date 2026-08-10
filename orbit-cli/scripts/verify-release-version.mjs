import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import process from "node:process";

const repository = resolve(process.argv[2] ?? ".");
const tag = process.argv[3] ?? process.env.GITHUB_REF_NAME;
if (!tag) {
  throw new Error("release tag is required");
}

const moonManifest = readFileSync(resolve(repository, "moon.mod"), "utf8");
const moonVersion = /^version\s*=\s*"([^"]+)"/m.exec(moonManifest)?.[1];
const npmManifest = JSON.parse(readFileSync(resolve(repository, "orbit-cli", "package.json"), "utf8"));
if (!moonVersion || typeof npmManifest.version !== "string") {
  throw new Error("could not read Orbit release versions");
}
if (npmManifest.repository?.url !== "https://github.com/Nanaloveyuki/orbit.git") {
  throw new Error("npm repository URL must identify https://github.com/Nanaloveyuki/orbit.git");
}
if (moonVersion !== npmManifest.version) {
  throw new Error(`MoonBit version ${moonVersion} does not match npm version ${npmManifest.version}`);
}
if (tag !== `v${moonVersion}`) {
  throw new Error(`release tag ${tag} must equal v${moonVersion}`);
}
process.stdout.write(`${moonVersion}\n`);
