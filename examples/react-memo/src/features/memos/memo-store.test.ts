import { describe, expect, it } from "vitest"
import { emptyWorkspace, memoReducer, parseStoredWorkspace, sortMemos } from "./memo-store"
import type { Memo } from "./types"

const memo = (id: string, updatedAt: string, pinned = false): Memo => ({
  id,
  title: id,
  content: "",
  category: "Ideas",
  pinned,
  createdAt: updatedAt,
  updatedAt,
})

describe("memoReducer", () => {
  it("creates, updates, pins, and deletes a memo", () => {
    const created = memoReducer(emptyWorkspace, {
      type: "create",
      id: "memo-1",
      now: "2026-08-22T08:00:00.000Z",
      category: "Work",
    })
    expect(created.activeMemoId).toBe("memo-1")
    expect(created.memos[0]).toMatchObject({ category: "Work", title: "" })

    const updated = memoReducer(created, {
      type: "update",
      id: "memo-1",
      now: "2026-08-22T08:05:00.000Z",
      patch: { title: "Release checklist" },
    })
    expect(updated.memos[0].title).toBe("Release checklist")

    const pinned = memoReducer(updated, {
      type: "toggle-pin",
      id: "memo-1",
      now: "2026-08-22T08:06:00.000Z",
    })
    expect(pinned.memos[0].pinned).toBe(true)

    expect(memoReducer(pinned, { type: "delete", id: "memo-1" })).toEqual(emptyWorkspace)
  })
})

describe("workspace persistence", () => {
  it("rejects corrupt or unsupported data", () => {
    expect(parseStoredWorkspace("not json")).toEqual(emptyWorkspace)
    expect(parseStoredWorkspace('{"version":2,"memos":[]}')).toEqual(emptyWorkspace)
  })

  it("sorts pinned and recently updated memos first without mutating input", () => {
    const input = [memo("old", "2026-08-20T08:00:00.000Z"), memo("pinned", "2026-08-19T08:00:00.000Z", true), memo("new", "2026-08-22T08:00:00.000Z")]
    expect(sortMemos(input).map((item) => item.id)).toEqual(["pinned", "new", "old"])
    expect(input.map((item) => item.id)).toEqual(["old", "pinned", "new"])
  })
})
