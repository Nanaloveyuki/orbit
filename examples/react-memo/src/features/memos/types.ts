export const memoCategories = ["Work", "Personal", "Ideas"] as const

export type MemoCategory = (typeof memoCategories)[number]
export type MemoFilter = "All" | "Pinned" | MemoCategory

export interface Memo {
  id: string
  title: string
  content: string
  category: MemoCategory
  pinned: boolean
  createdAt: string
  updatedAt: string
}

export interface MemoWorkspace {
  version: 1
  memos: Memo[]
  activeMemoId: string | null
}
