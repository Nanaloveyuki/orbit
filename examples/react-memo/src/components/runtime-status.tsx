import { useEffect, useState } from "react"
import { getOrbitRuntime } from "@/lib/orbit"

type RuntimeState = "checking" | "native" | "browser"

export function RuntimeStatus() {
  const [state, setState] = useState<RuntimeState>("checking")

  useEffect(() => {
    let active = true
    getOrbitRuntime()
      .then((runtime) => {
        if (active) setState(runtime?.runtime === "Orbit" ? "native" : "browser")
      })
      .catch(() => {
        if (active) setState("browser")
      })
    return () => {
      active = false
    }
  }, [])

  const label = state === "checking" ? "Connecting" : state === "native" ? "Orbit native" : "Browser preview"

  return (
    <div className="flex items-center gap-2 text-xs text-muted-foreground" aria-live="polite">
      <span
        className={state === "native" ? "size-1.5 rounded-full bg-emerald-500" : "size-1.5 rounded-full bg-amber-500"}
      />
      <span>{label}</span>
    </div>
  )
}
