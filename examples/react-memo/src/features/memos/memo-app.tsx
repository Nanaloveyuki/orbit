import { useCallback, useEffect, useState } from "react"
import { Plus } from "lucide-react"
import { ModeToggle } from "@/components/mode-toggle"
import { RuntimeStatus } from "@/components/runtime-status"
import { Button } from "@/components/ui/button"
import { MemoEditor } from "./memo-editor"
import { MemoList } from "./memo-list"
import { MemoSidebar } from "./memo-sidebar"
import type { MemoFilter } from "./types"
import { useMemoWorkspace } from "./use-memo-workspace"

export function MemoApp() {
  const { workspace, activeMemo, createMemo, selectMemo, updateMemo, togglePin, deleteMemo } = useMemoWorkspace()
  const [filter, setFilter] = useState<MemoFilter>("All")
  const [search, setSearch] = useState("")
  const [mobilePane, setMobilePane] = useState<"list" | "editor">("list")
  const create = useCallback(() => {
    createMemo(filter === "Work" || filter === "Personal" || filter === "Ideas" ? filter : undefined)
    setMobilePane("editor")
  }, [createMemo, filter])

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "n") {
        event.preventDefault()
        create()
      }
    }
    window.addEventListener("keydown", handleKeyDown)
    return () => window.removeEventListener("keydown", handleKeyDown)
  }, [create])

  return (
    <div className="grid h-dvh min-h-0 grid-rows-[52px_minmax(0,1fr)] overflow-hidden bg-background text-foreground">
      <header className="flex items-center border-b bg-background px-3 sm:px-4">
        <div className="flex items-center gap-2.5">
          <span className="flex size-7 items-center justify-center rounded-md bg-primary text-sm font-semibold text-primary-foreground">O</span>
          <div>
            <h1 className="text-sm font-semibold leading-4">Orbit Memo</h1>
            <RuntimeStatus />
          </div>
        </div>
        <div className="ml-auto flex items-center gap-1">
          <Button size="sm" className="hidden sm:inline-flex lg:hidden" onClick={create}>
            <Plus data-icon="inline-start" />
            New note
          </Button>
          <ModeToggle />
        </div>
      </header>
      <main className="grid min-h-0 grid-cols-1 md:grid-cols-[320px_minmax(0,1fr)] lg:grid-cols-[220px_340px_minmax(0,1fr)]">
        <MemoSidebar memos={workspace.memos} filter={filter} onFilterChange={setFilter} onCreate={create} />
        <MemoList
          memos={workspace.memos}
          activeMemoId={workspace.activeMemoId}
          filter={filter}
          search={search}
          visible={mobilePane === "list"}
          onSearchChange={setSearch}
          onFilterChange={setFilter}
          onCreate={create}
          onSelect={(id) => {
            selectMemo(id)
            setMobilePane("editor")
          }}
        />
        <MemoEditor
          memo={activeMemo}
          visible={mobilePane === "editor"}
          onBack={() => setMobilePane("list")}
          onUpdate={(patch) => activeMemo && updateMemo(activeMemo.id, patch)}
          onTogglePin={() => activeMemo && togglePin(activeMemo.id)}
          onDelete={() => {
            if (activeMemo) deleteMemo(activeMemo.id)
            setMobilePane("list")
          }}
        />
      </main>
    </div>
  )
}
