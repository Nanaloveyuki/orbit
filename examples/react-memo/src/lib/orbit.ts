export interface OrbitRuntimeInfo {
  application: string
  version: string
  runtime: string
  storage: string
}

interface OrbitBridge {
  invoke(command: string, payload?: unknown, options?: { timeout?: number }): Promise<unknown>
}

declare global {
  interface Window {
    __ORBIT__?: OrbitBridge
  }
}

export async function getOrbitRuntime(): Promise<OrbitRuntimeInfo | null> {
  if (!window.__ORBIT__) return null
  const result = await window.__ORBIT__.invoke("memo.runtime", {}, { timeout: 3000 })
  if (!result || typeof result !== "object") return null
  return result as OrbitRuntimeInfo
}
