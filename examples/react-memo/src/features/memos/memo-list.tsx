import { Filter, Pin, Plus, Search, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Input } from "@/components/ui/input"
import { cn } from "@/lib/utils"
import { CategoryMark } from "./category-mark"
import { sortMemos } from "./memo-store"
import type { Memo, MemoFilter } from "./types"

const filters: MemoFilter[] = ["All", "Pinned", "Work", "Personal", "Ideas"]

function formatUpdated(value: string) {
  const date = new Date(value)
  const today = new Date()
  const sameDay = date.toDateString() === today.toDateString()
  return new Intl.DateTimeFormat("en", sameDay ? { hour: "numeric", minute: "2-digit" } : { month: "short", day: "numeric" }).format(date)
}

function previewText(memo: Memo) {
  return memo.content.trim().replace(/\s+/g, " ") || "No additional text"
}

export function MemoList({
  memos,
  activeMemoId,
  filter,
  search,
  visible,
  onSearchChange,
  onFilterChange,
  onSelect,
  onCreate,
}: {
  memos: Memo[]
  activeMemoId: string | null
  filter: MemoFilter
  search: string
  visible: boolean
  onSearchChange(value: string): void
  onFilterChange(filter: MemoFilter): void
  onSelect(id: string): void
  onCreate(): void
}) {
  const query = search.trim().toLocaleLowerCase()
  const filtered = sortMemos(memos).filter((memo) => {
    const matchesFilter = filter === "All" || (filter === "Pinned" ? memo.pinned : memo.category === filter)
    const matchesQuery = !query || `${memo.title}\n${memo.content}`.toLocaleLowerCase().includes(query)
    return matchesFilter && matchesQuery
  })

  return (
    <section className={cn("min-h-0 flex-col border-r bg-background md:flex", visible ? "flex" : "hidden")} aria-label="Notes">
      <div className="flex h-14 items-center gap-2 border-b px-3">
        <div className="relative min-w-0 flex-1">
          <Search className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={search}
            onChange={(event) => onSearchChange(event.target.value)}
            className="pl-8 pr-8"
            aria-label="Search notes"
            placeholder="Search notes"
          />
          {search ? (
            <button
              type="button"
              className="absolute right-2 top-1/2 -translate-y-1/2 rounded-sm p-0.5 text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              onClick={() => onSearchChange("")}
              aria-label="Clear search"
            >
              <X className="size-3.5" />
            </button>
          ) : null}
        </div>
        <DropdownMenu>
          <DropdownMenuTrigger render={<Button variant="outline" size="icon" aria-label="Choose note filter" />}>
            <Filter />
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-40">
            {filters.map((value) => (
              <DropdownMenuItem key={value} onClick={() => onFilterChange(value)}>
                <span className={cn(value === filter && "font-medium")}>{value}</span>
              </DropdownMenuItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>
        <Button size="icon" onClick={onCreate} aria-label="Create note" className="lg:hidden">
          <Plus />
        </Button>
      </div>
      <div className="flex items-center justify-between border-b px-4 py-2 text-xs text-muted-foreground">
        <span>{filter}</span>
        <span className="tabular-nums">{filtered.length}</span>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto">
        {filtered.length ? (
          <div>
            {filtered.map((memo) => (
              <button
                key={memo.id}
                type="button"
                onClick={() => onSelect(memo.id)}
                className={cn(
                  "group relative block w-full border-b px-4 py-3 text-left transition-colors hover:bg-muted/70 focus-visible:z-10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring",
                  memo.id === activeMemoId && "bg-accent/70",
                )}
              >
                <span className="mb-1 flex min-w-0 items-center gap-2">
                  <CategoryMark category={memo.category} />
                  <span className="min-w-0 flex-1 truncate text-sm font-medium">{memo.title.trim() || "Untitled"}</span>
                  {memo.pinned ? <Pin className="size-3.5 fill-current text-primary" aria-label="Pinned" /> : null}
                  <span className="text-xs tabular-nums text-muted-foreground">{formatUpdated(memo.updatedAt)}</span>
                </span>
                <span className="block truncate text-xs leading-5 text-muted-foreground">{previewText(memo)}</span>
              </button>
            ))}
          </div>
        ) : (
          <div className="flex h-full min-h-56 flex-col items-center justify-center px-8 text-center">
            <p className="text-sm font-medium">{memos.length ? "No matching notes" : "No notes yet"}</p>
            <p className="mt-1 text-xs leading-5 text-muted-foreground">
              {memos.length ? "Try another search or filter." : "Create a note to start writing."}
            </p>
            {!memos.length ? (
              <Button className="mt-4" size="sm" onClick={onCreate}>
                <Plus data-icon="inline-start" />
                New note
              </Button>
            ) : null}
          </div>
        )}
      </div>
    </section>
  )
}
