import { afterEach, describe, expect, it, vi } from "vitest"
import { getOrbitRuntime } from "./orbit"

afterEach(() => vi.unstubAllGlobals())

describe("Orbit runtime boundary", () => {
  it("allows browser preview without a native bridge", async () => {
    vi.stubGlobal("__ORBIT__", undefined)
    expect(await getOrbitRuntime()).toBeNull()
  })

  it("uses the generated client and validates the response", async () => {
    const runtime = { application: "Memo", version: "1", runtime: "Orbit", storage: "localStorage" }
    const invoke = vi.fn().mockResolvedValue(runtime)
    vi.stubGlobal("__ORBIT__", { invoke })
    expect(await getOrbitRuntime()).toEqual(runtime)
    expect(invoke).toHaveBeenCalledWith("memo.runtime", {}, expect.objectContaining({ timeout: 3000, signal: expect.any(AbortSignal) }))
  })

  it("does not cast malformed host data to application types", async () => {
    vi.stubGlobal("__ORBIT__", { invoke: vi.fn().mockResolvedValue({ runtime: "Orbit" }) })
    await expect(getOrbitRuntime()).rejects.toMatchObject({ code: "invalid_response" })
  })

  it("preserves host failure codes", async () => {
    vi.stubGlobal("__ORBIT__", { invoke: vi.fn().mockRejectedValue({ code: "permission_denied", message: "Denied" }) })
    await expect(getOrbitRuntime()).rejects.toMatchObject({ code: "permission_denied" })
  })
})
