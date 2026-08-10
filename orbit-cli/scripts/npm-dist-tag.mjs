import { resolve } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

export function npmDistTag(version) {
  const match = /^\d+\.\d+\.\d+(?:-([0-9A-Za-z-]+)(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z.-]+)?$/.exec(version);
  if (!match) {
    throw new Error(`invalid release version: ${version}`);
  }
  if (!match[1]) {
    return "latest";
  }
  return /^[A-Za-z][0-9A-Za-z-]*$/.test(match[1]) ? match[1].toLowerCase() : "next";
}

if (process.argv[1] && resolve(fileURLToPath(import.meta.url)) === resolve(process.argv[1])) {
  process.stdout.write(`${npmDistTag(process.argv[2] ?? "")}\n`);
}
