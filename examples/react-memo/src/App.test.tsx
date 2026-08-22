import { afterEach, describe, expect, it } from "vitest"
import { cleanup, render, screen, waitFor, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import App from "./App"

afterEach(() => {
  cleanup()
  window.localStorage.clear()
})

describe("Orbit Memo", () => {
  it("creates, edits, pins, and restores a note", async () => {
    const user = userEvent.setup()
    const firstRender = render(<App />)

    const sidebar = screen.getByRole("complementary")
    await user.click(within(sidebar).getByRole("button", { name: "New note" }))
    await user.type(screen.getByLabelText("Note title"), "Release notes")
    await user.type(screen.getByLabelText("Note content"), "Verify the embedded React application.")
    await user.click(screen.getByRole("button", { name: "Pin note" }))

    expect(screen.getByRole("button", { name: "Unpin note" })).toBeInTheDocument()
    await waitFor(() => expect(window.localStorage.getItem("orbit-memo.workspace.v1")).toContain("Release notes"))

    firstRender.unmount()
    render(<App />)

    expect(screen.getByLabelText("Note title")).toHaveValue("Release notes")
    expect(screen.getByLabelText("Note content")).toHaveValue("Verify the embedded React application.")
  })
})
