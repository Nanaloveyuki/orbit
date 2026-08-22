import { ArrowLeft, Check, ChevronDown, Pin, PinOff, Trash2 } from "lucide-react"
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Textarea } from "@/components/ui/textarea"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { cn } from "@/lib/utils"
import { CategoryMark } from "./category-mark"
import { memoCategories, type Memo, type MemoCategory } from "./types"

function formatDate(value: string) {
  return new Intl.DateTimeFormat("en", {
    month: "long",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(value))
}

export function MemoEditor({
  memo,
  visible,
  onBack,
  onUpdate,
  onTogglePin,
  onDelete,
}: {
  memo: Memo | null
  visible: boolean
  onBack(): void
  onUpdate(patch: Partial<Pick<Memo, "title" | "content" | "category">>): void
  onTogglePin(): void
  onDelete(): void
}) {
  if (!memo) {
    return (
      <section className={cn("min-h-0 items-center justify-center bg-editor md:flex", visible ? "flex" : "hidden")} aria-label="Note editor">
        <div className="max-w-xs px-8 text-center">
          <div className="mx-auto mb-4 flex size-10 items-center justify-center rounded-md border bg-background text-muted-foreground">
            <Check className="size-5" />
          </div>
          <p className="text-sm font-medium">Your notes are up to date</p>
          <p className="mt-1 text-xs leading-5 text-muted-foreground">Select a note or create a new one.</p>
        </div>
      </section>
    )
  }

  return (
    <section className={cn("min-h-0 flex-col bg-editor md:flex", visible ? "flex" : "hidden")} aria-label="Note editor">
      <div className="flex h-14 items-center gap-1 border-b bg-background/80 px-3">
        <Button variant="ghost" size="icon" className="md:hidden" onClick={onBack} aria-label="Back to notes">
          <ArrowLeft />
        </Button>
        <DropdownMenu>
          <DropdownMenuTrigger render={<Button variant="ghost" className="gap-2" />}>
            <CategoryMark category={memo.category} />
            {memo.category}
            <ChevronDown className="size-3.5 text-muted-foreground" />
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start" className="w-40">
            {memoCategories.map((category) => (
              <DropdownMenuItem key={category} onClick={() => onUpdate({ category })}>
                <CategoryMark category={category} />
                {category}
              </DropdownMenuItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>
        <Badge variant="outline" className="ml-1 gap-1 text-muted-foreground">
          <Check className="size-3" />
          Saved locally
        </Badge>
        <div className="ml-auto flex items-center gap-1">
          <Tooltip>
            <TooltipTrigger
              render={
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label={memo.pinned ? "Unpin note" : "Pin note"}
                  onClick={onTogglePin}
                />
              }
            >
              {memo.pinned ? <PinOff /> : <Pin />}
            </TooltipTrigger>
            <TooltipContent>{memo.pinned ? "Unpin note" : "Pin note"}</TooltipContent>
          </Tooltip>
          <AlertDialog>
            <AlertDialogTrigger
              render={
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label="Delete note"
                  className="text-muted-foreground hover:text-destructive"
                />
              }
            >
              <Trash2 />
            </AlertDialogTrigger>
            <AlertDialogContent>
              <AlertDialogHeader>
                <AlertDialogTitle>Delete this note?</AlertDialogTitle>
                <AlertDialogDescription>This action cannot be undone.</AlertDialogDescription>
              </AlertDialogHeader>
              <AlertDialogFooter>
                <AlertDialogCancel>Cancel</AlertDialogCancel>
                <AlertDialogAction variant="destructive" onClick={onDelete}>Delete note</AlertDialogAction>
              </AlertDialogFooter>
            </AlertDialogContent>
          </AlertDialog>
        </div>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto">
        <div className="mx-auto flex min-h-full w-full max-w-3xl flex-col px-5 py-6 sm:px-8 sm:py-8">
          <input
            value={memo.title}
            onChange={(event) => onUpdate({ title: event.target.value })}
            aria-label="Note title"
            placeholder="Untitled"
            className="w-full bg-transparent text-3xl font-semibold text-foreground outline-none placeholder:text-muted-foreground/50 sm:text-4xl"
          />
          <p className="mt-2 text-xs tabular-nums text-muted-foreground">Edited {formatDate(memo.updatedAt)}</p>
          <Textarea
            value={memo.content}
            onChange={(event) => onUpdate({ content: event.target.value })}
            aria-label="Note content"
            placeholder="Write something worth keeping..."
            className="mt-6 min-h-80 flex-1 resize-none border-0 bg-transparent px-0 py-0 text-base leading-7 shadow-none focus-visible:ring-0 dark:bg-transparent"
          />
        </div>
      </div>
    </section>
  )
}
