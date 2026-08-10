import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

export function acceptsMooncakeDryRunResult(status, output) {
  return status === 0 || (
    Number.isInteger(status) &&
    output.includes("Server status: 202 Accepted") &&
    output.includes("Dry run completed successfully. No changes were made.")
  );
}

function main() {
  const result = spawnSync("moon", ["publish", "--dry-run"], { encoding: "utf8" });
  process.stdout.write(result.stdout ?? "");
  process.stderr.write(result.stderr ?? "");
  if (result.error) {
    throw result.error;
  }
  const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
  if (!acceptsMooncakeDryRunResult(result.status, output)) {
    process.exitCode = result.status ?? 1;
  }
}

if (process.argv[1] && resolve(fileURLToPath(import.meta.url)) === resolve(process.argv[1])) {
  main();
}
