# Orbit CLI

`@nanaloveyuki/orbit-cli` is the Node.js command-line wrapper for Orbit
applications. It generates MoonBit sources, builds and verifies directory
packages, creates Windows installers and Linux archives, and drives native
Linux package tools.

The package requires Node.js 20 or newer and a compatible MoonBit toolchain.
Commands that compile an application also require the native platform SDKs used
by that application.

```sh
npx @nanaloveyuki/orbit-cli@alpha init desktop-app \
  --name "Desktop App" \
  --identifier com.example.desktop \
  --module example/desktop-app
cd desktop-app
moon update
npm install
npm run orbit:run
```

`init` refuses to overwrite an existing target. It creates a native MoonBit
application, schema-version 2 configuration, capability-protected IPC example,
frontend assets, and npm scripts.

For an existing Orbit application:

```sh
npx orbit dev --config orbit.conf.json
npx orbit package \
  --config orbit.conf.json \
  --release \
  --out-dir dist
npx orbit verify-package --package-dir dist
```

The CLI uses a workspace-local `orbit-build` package when present, then a
generator materialized by Mooncakes. On a clean first build it reads the pinned
Orbit version from `moon.mod` and runs `moon fetch` into the project-local
`.repos` cache. `--orbit-build` remains an explicit override for custom
repository layouts.

Production installer, archive, and native-package commands require an external
`--sign-command`. `--allow-unsigned` is only an explicit local-development
opt-out.

- [Orbit overview and runnable example](https://github.com/Nanaloveyuki/orbit)
- [Getting started](https://github.com/Nanaloveyuki/orbit/blob/main/docs/getting-started.md)
- [Configuration](https://github.com/Nanaloveyuki/orbit/blob/main/docs/configuration.md)
- [Packaging and verification](https://github.com/Nanaloveyuki/orbit/blob/main/docs/packaging.md)

License: Apache-2.0.
