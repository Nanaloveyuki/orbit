import { useEffect, useMemo, useReducer } from "react"
import { MEMO_STORAGE_KEY, memoReducer, parseStoredWorkspace } from "./memo-store"
import type { Memo, MemoCategory } from "./types"

const createId = () =>
  globalThis.crypto?.randomUUID?.() ?? `memo-${Date.now()}-${Math.random().toString(16).slice(2)}`

export function useMemoWorkspace() {
  const [workspace, dispatch] = useReducer(
    memoReducer,
    undefined,
    () => parseStoredWorkspace(window.localStorage.getItem(MEMO_STORAGE_KEY)),
  )

  useEffect(() => {
    window.localStorage.setItem(MEMO_STORAGE_KEY, JSON.stringify(workspace))
  }, [workspace])

  const activeMemo = useMemo(
    () => workspace.memos.find((memo) => memo.id === workspace.activeMemoId) ?? null,
    [workspace.activeMemoId, workspace.memos],
  )

  return {
    workspace,
    activeMemo,
    createMemo(category?: MemoCategory) {
      dispatch({ type: "create", id: createId(), now: new Date().toISOString(), category })
    },
    selectMemo(id: string | null) {
      dispatch({ type: "select", id })
    },
    updateMemo(
      id: string,
      patch: Partial<Pick<Memo, "title" | "content" | "category">>,
    ) {
      dispatch({ type: "update", id, now: new Date().toISOString(), patch })
    },
    togglePin(id: string) {
      dispatch({ type: "toggle-pin", id, now: new Date().toISOString() })
    },
    deleteMemo(id: string) {
      dispatch({ type: "delete", id })
    },
  }
}
