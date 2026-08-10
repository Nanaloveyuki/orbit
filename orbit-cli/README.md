# Orbit CLI

`@nanaloveyuki/orbit-cli` is the Node.js command-line wrapper for Orbit
applications. It generates MoonBit sources, builds and verifies directory
packages, creates Windows installers and Linux archives, and drives native
Linux package tools.

The package requires Node.js 20 or newer and a compatible MoonBit toolchain.
Commands that compile an application also require the native platform SDKs used
by that application.

```sh
npm install --save-dev @nanaloveyuki/orbit-cli@alpha
npx orbit --help
```

After adding `Nanaloveyuki/orbit` to a MoonBit module, point the CLI at the
published generator package:

```sh
npx orbit dev \
  --orbit-build .mooncakes/Nanaloveyuki/orbit/orbit-build \
  --config orbit.conf.json
npx orbit package \
  --orbit-build .mooncakes/Nanaloveyuki/orbit/orbit-build \
  --config orbit.conf.json \
  --release \
  --out-dir dist
npx orbit verify-package --package-dir dist
```

The Orbit repository itself has a local `orbit-build` package, so its example
commands do not need the explicit `--orbit-build` option.

Production installer, archive, and native-package commands require an external
`--sign-command`. `--allow-unsigned` is only an explicit local-development
opt-out.

- [Orbit overview and runnable example](https://github.com/Nanaloveyuki/orbit)
- [Getting started](https://github.com/Nanaloveyuki/orbit/blob/main/docs/getting-started.md)
- [Configuration](https://github.com/Nanaloveyuki/orbit/blob/main/docs/configuration.md)
- [Packaging and verification](https://github.com/Nanaloveyuki/orbit/blob/main/docs/packaging.md)

License: Apache-2.0.
