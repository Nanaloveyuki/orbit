import { FileText, Lightbulb, Pin, Plus, UserRound, BriefcaseBusiness } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Separator } from "@/components/ui/separator"
import { cn } from "@/lib/utils"
import type { Memo, MemoFilter } from "./types"

const filters: Array<{ value: MemoFilter; label: string; icon: typeof FileText }> = [
  { value: "All", label: "All notes", icon: FileText },
  { value: "Pinned", label: "Pinned", icon: Pin },
  { value: "Work", label: "Work", icon: BriefcaseBusiness },
  { value: "Personal", label: "Personal", icon: UserRound },
  { value: "Ideas", label: "Ideas", icon: Lightbulb },
]

export function MemoSidebar({
  memos,
  filter,
  onFilterChange,
  onCreate,
}: {
  memos: Memo[]
  filter: MemoFilter
  onFilterChange(filter: MemoFilter): void
  onCreate(): void
}) {
  const count = (value: MemoFilter) => {
    if (value === "All") return memos.length
    if (value === "Pinned") return memos.filter((memo) => memo.pinned).length
    return memos.filter((memo) => memo.category === value).length
  }

  return (
    <aside className="hidden min-h-0 flex-col border-r bg-sidebar text-sidebar-foreground lg:flex">
      <div className="px-4 pb-3 pt-4">
        <Button className="w-full justify-center" onClick={onCreate}>
          <Plus data-icon="inline-start" />
          New note
        </Button>
      </div>
      <Separator />
      <nav className="flex flex-1 flex-col gap-1 px-2 py-3" aria-label="Note filters">
        {filters.map(({ value, label, icon: Icon }) => (
          <button
            key={value}
            type="button"
            className={cn(
              "flex h-9 w-full items-center gap-2 rounded-md px-2.5 text-sm transition-colors hover:bg-sidebar-accent hover:text-sidebar-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sidebar-ring",
              filter === value && "bg-sidebar-accent font-medium text-sidebar-accent-foreground",
            )}
            onClick={() => onFilterChange(value)}
          >
            <Icon className="size-4" />
            <span>{label}</span>
            <span className="ml-auto text-xs tabular-nums text-muted-foreground">{count(value)}</span>
          </button>
        ))}
      </nav>
      <div className="border-t px-4 py-3 text-xs leading-5 text-muted-foreground">
        Notes stay on this device.
      </div>
    </aside>
  )
}
