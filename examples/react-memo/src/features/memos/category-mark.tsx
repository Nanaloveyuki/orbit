import { cn } from "@/lib/utils"
import type { MemoCategory } from "./types"

const categoryColors: Record<MemoCategory, string> = {
  Work: "bg-emerald-500",
  Personal: "bg-amber-500",
  Ideas: "bg-sky-500",
}

export function CategoryMark({ category, className }: { category: MemoCategory; className?: string }) {
  return <span className={cn("size-2 rounded-full", categoryColors[category], className)} aria-hidden="true" />
}
