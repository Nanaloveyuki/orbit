import { invoke, isAvailable, OrbitIpcError, type InvokeOptions } from "../../orbit-bindings.mjs"

export interface OrbitRuntimeInfo {
  application: string
  version: string
  runtime: string
  storage: string
}

export async function getOrbitRuntime(options: InvokeOptions = {}): Promise<OrbitRuntimeInfo | null> {
  if (!isAvailable()) return null
  const result = await invoke("memo.runtime", {}, { timeout: 3000, ...options })
  if (!result || typeof result !== "object" ||
      !("application" in result) || typeof result.application !== "string" ||
      !("version" in result) || typeof result.version !== "string" ||
      !("runtime" in result) || typeof result.runtime !== "string" ||
      !("storage" in result) || typeof result.storage !== "string") {
    throw new OrbitIpcError("invalid_response", "Invalid memo.runtime response")
  }
  return { application: result.application, version: result.version, runtime: result.runtime, storage: result.storage }
}
