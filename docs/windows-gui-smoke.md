# Windows GUI Acceptance

Run this checklist on a Windows x64 machine before publishing an Orbit release.
The framework CI exercises compilation, package construction, and plugin
integration; these steps cover Windows shell and WebView behavior that cannot
be asserted reliably in a headless runner.

## Build

```powershell
moon run --target native orbit-build examples/windows-lifecycle/orbit.conf.json examples/windows-lifecycle/generated_page.mbt
moon run --target native examples/windows-lifecycle
```

The example starts with a native window and a visible `Orbit Lifecycle Example`
page.

## Lifecycle And Tray

1. Enter text in the state field and confirm the status reports it was saved.
2. Close the window. It must disappear while the `Orbit Lifecycle Example` tray icon
   remains available.
3. Click the tray icon. The window must reappear with the saved text restored.
4. Right-click the tray icon, select `Suspend window`, then activate the tray
   icon again. The window must return and restore the same text.
5. Right-click and select `Exit`. The window and tray icon must both disappear.
6. While the example is running, restart Explorer from Task Manager. Its tray
   icon must return after Explorer restarts.

## Windows Integrations

1. Use `Choose file` and `Print page`.
2. Confirm cancellation returns to the page without an error and successful
   file operations never expose an absolute native path.
3. Package the example, validate the directory package, generate an unsigned
   local installer, install it, launch it, repeat the lifecycle steps, then
   uninstall it:

```powershell
npm --prefix orbit-cli run test
node orbit-cli/bin/orbit.mjs package --release --config examples/windows-lifecycle/orbit.conf.json --package examples/windows-lifecycle --out-dir dist
node orbit-cli/bin/orbit.mjs verify-package --package-dir dist
node orbit-cli/bin/orbit.mjs installer --package-dir dist --allow-unsigned
```

Record the Windows version, WebView2 Runtime version, Orbit commit, and any
failed step in the release issue or pull request.
