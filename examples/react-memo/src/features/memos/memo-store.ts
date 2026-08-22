import type { Memo, MemoCategory, MemoWorkspace } from "./types"

export const MEMO_STORAGE_KEY = "orbit-memo.workspace.v1"

export type MemoAction =
  | { type: "create"; id: string; now: string; category?: MemoCategory }
  | { type: "select"; id: string | null }
  | { type: "update"; id: string; now: string; patch: Partial<Pick<Memo, "title" | "content" | "category">> }
  | { type: "toggle-pin"; id: string; now: string }
  | { type: "delete"; id: string }

export const emptyWorkspace: MemoWorkspace = {
  version: 1,
  memos: [],
  activeMemoId: null,
}

const isCategory = (value: unknown): value is MemoCategory =>
  value === "Work" || value === "Personal" || value === "Ideas"

const isMemo = (value: unknown): value is Memo => {
  if (!value || typeof value !== "object") return false
  const memo = value as Record<string, unknown>
  return (
    typeof memo.id === "string" &&
    typeof memo.title === "string" &&
    typeof memo.content === "string" &&
    isCategory(memo.category) &&
    typeof memo.pinned === "boolean" &&
    typeof memo.createdAt === "string" &&
    typeof memo.updatedAt === "string"
  )
}

export function parseStoredWorkspace(raw: string | null): MemoWorkspace {
  if (!raw) return emptyWorkspace
  try {
    const value = JSON.parse(raw) as Partial<MemoWorkspace>
    if (value.version !== 1 || !Array.isArray(value.memos) || !value.memos.every(isMemo)) {
      return emptyWorkspace
    }
    const activeMemoId =
      typeof value.activeMemoId === "string" && value.memos.some((memo) => memo.id === value.activeMemoId)
        ? value.activeMemoId
        : value.memos[0]?.id ?? null
    return { version: 1, memos: value.memos, activeMemoId }
  } catch {
    return emptyWorkspace
  }
}

export function sortMemos(memos: Memo[]): Memo[] {
  return [...memos].sort((left, right) => {
    if (left.pinned !== right.pinned) return left.pinned ? -1 : 1
    return right.updatedAt.localeCompare(left.updatedAt)
  })
}

export function memoReducer(state: MemoWorkspace, action: MemoAction): MemoWorkspace {
  switch (action.type) {
    case "create": {
      const memo: Memo = {
        id: action.id,
        title: "",
        content: "",
        category: action.category ?? "Ideas",
        pinned: false,
        createdAt: action.now,
        updatedAt: action.now,
      }
      return { ...state, memos: [memo, ...state.memos], activeMemoId: memo.id }
    }
    case "select":
      return { ...state, activeMemoId: action.id }
    case "update":
      return {
        ...state,
        memos: state.memos.map((memo) =>
          memo.id === action.id ? { ...memo, ...action.patch, updatedAt: action.now } : memo,
        ),
      }
    case "toggle-pin":
      return {
        ...state,
        memos: state.memos.map((memo) =>
          memo.id === action.id ? { ...memo, pinned: !memo.pinned, updatedAt: action.now } : memo,
        ),
      }
    case "delete": {
      const memos = state.memos.filter((memo) => memo.id !== action.id)
      const activeMemoId = state.activeMemoId === action.id ? sortMemos(memos)[0]?.id ?? null : state.activeMemoId
      return { ...state, memos, activeMemoId }
    }
  }
}
