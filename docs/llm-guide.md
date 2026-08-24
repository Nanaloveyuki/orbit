# Orbit LLM and Automation Guide

This guide is for an LLM or automation agent that needs to understand, use, or
modify the Orbit repository. It is not application documentation.

## Operating rules

- Read the root README and this guide before editing.
- Use `docs/README.md` to select the document for the requested audience.
- Keep the change limited to the requested package or document.
- Do not copy private conversation text, prompts, credentials, or local paths into
  source files or documentation.
- Preserve unrelated working-tree changes.
- Treat generated files as outputs of their inputs, not as primary source files.

## Repository map

- `orbit-core`: desktop lifecycle, windows, extensions, and application composition.
- `orbit-runtime`: runtime contracts independent of a concrete WebView host.
- `orbit-runtime-moonview`: MoonView runtime implementation.
- `orbit-ipc`: command registry, wire format, principals, and capability policy.
- `orbit-ipc-async`: shared deadlines, cancellation, and async execution.
- `orbit-ipc-http`: optional authenticated HTTP transport.
- `orbit-ipc-moonview`: MoonView page-message adapter.
- `orbit-build`: configuration validation, resource embedding, bindings, and metadata.
- `orbit-cli`: Node.js development, build, diagnostics, packaging, and verification commands.
- `orbit-plugin`: sidecar, dynamic library, and plugin ABI runtime.
- `orbit-android` and `orbit-runtime-android`: Android host and runtime integration.
- `orbit-example`: the smallest end-to-end application.
- `examples/`: runnable application references.

Keep package boundaries intact. Transport-independent contracts must not depend on
concrete Orby or MoonView types. Platform-specific code belongs in the platform
adapter or extension package.

## Choose the workflow

### Application usage

Read the root README and `docs/getting-started.md`. Start from
`orbit-example` or an example under `examples/`. Do not change framework packages
when the request only concerns an application.

### Application editing

Inspect the application's `orbit.conf.json`, `moon.pkg`, frontend source, and
generated files first. The usual loop is:

~~~sh
moon update
npm install
npx orbit generate
npx orbit dev
~~~

For embedded resources, regenerate after changing the configured asset directory.
For Vite applications, verify `dev_url`, `build_command`, and `dist_dir` before
changing CLI code.

### Framework editing

Read the relevant package source, `moon.pkg`, public interface files, and focused
tests before editing. Trace the API from the public facade through the runtime or
adapter boundary. Avoid adding a new abstraction when an existing package owns the
behavior.

For public MoonBit API changes:

1. Update the implementation.
2. Run `moon info` to refresh the generated interface.
3. Review the generated `.mbti` diff.
4. Add or update focused tests.
5. Update the matching user or reference documentation.

### Documentation editing

Classify the requested text before writing:

- User behavior and application commands belong in `README.md` or a user guide.
- Chinese user-facing content belongs in `docs/README-cn.md` or another localized file.
- Package contracts and normative rules belong in `docs/standards/`.
- Repository changes, tests, CI, and release operations belong in maintainer docs.
- LLM workflow rules belong in this file or `AGENTS.md`.

Never use the README as a scratchpad, design diary, prompt archive, release log,
or test transcript.

## Generated files

- `generated_page.mbt` is produced by `orbit-build` from application configuration
  and frontend assets.
- `orbit-bindings.mjs` is produced by the CLI bindings command.
- `pkg.generated.mbti` is produced by MoonBit package metadata generation.
- Build directories, dependency caches, `tmp/`, and local fixture binaries are not
  documentation inputs and should not be committed.

When a generated file changes unexpectedly, compare its source configuration,
package imports, or asset tree before editing the generated output. Use the
owning generator to validate generated source; do not use formatter output as a
replacement for `generated_page.mbt`.

## Validation

Choose the smallest validation that covers the change.

Documentation-only change:

~~~sh
git diff --check
~~~

MoonBit package change:

~~~sh
moon fmt --check
moon check --target native --deny-warn
moon test --target native --deny-warn
~~~

`moon fmt --check` applies to handwritten MoonBit source. For generated files
such as `generated_page.mbt`, rerun `orbit-build` with the same configuration and
compare the generated result instead of formatting the generated file in place.

CLI change:

~~~sh
npm test --prefix orbit-cli
npm pack --dry-run ./orbit-cli
~~~

Cross-package or release-sensitive change:

~~~sh
moon check --target native --deny-warn
moon test --target native --deny-warn
npm test --prefix orbit-cli
~~~

Report commands that could not run and distinguish environment failures from
source failures.

## Troubleshooting

1. Check the exact failing command and target.
2. Check `.moon-version`, `moon.mod`, and the relevant `moon.pkg`.
3. Confirm the required native SDK or system package exists.
4. Reproduce with the smallest focused command.
5. Inspect generated output only after checking its inputs.
6. Record the failure and validation scope in the change description, not in the
   user README.

Common boundaries:

- WebView2 errors are Windows SDK/runtime or MoonView setup issues before they
  are Orbit IPC issues.
- Missing GTK/WebKit libraries are Linux environment failures.
- A denied page command is usually a principal, origin, command-name, or policy
  mismatch.
- A stale embedded page usually means the resource generator was not rerun.
- A broken generated interface usually means the public API or package metadata
  changed without running `moon info`.

## Completion checklist

- The edited document is in the correct audience category.
- Public commands and paths match the current repository.
- Generated files are updated only from their inputs.
- Focused validation has run, or the reason it could not run is recorded.
- No prompt, credential, private path, or unrelated refactor was added.
