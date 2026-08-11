# Windows Lifecycle Example

This is Orbit's Windows x64 lifecycle reference application. It keeps a
top-level window and Windows tray entry alive while its embedded WebView is
suspended, then recreates the WebView and restores application-owned state when
the window returns.

```powershell
moon run --target native orbit-build examples/windows-lifecycle/orbit.conf.json examples/windows-lifecycle/generated_page.mbt
moon run --target native examples/windows-lifecycle
```

Enter text, select **Save state**, then close the window or select **Suspend
window** from the tray menu. Activating the tray item restores the window and
the value retained by the MoonBit application. The sample does not claim to
serialize arbitrary DOM state.

The tray extension is only activated on Windows. Other targets can compile the
example but are not part of its support contract. See the full manual checklist
in [`../../docs/windows-gui-smoke.md`](../../docs/windows-gui-smoke.md).
