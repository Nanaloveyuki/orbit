# Orbit CLI

`@nanaloveyuki/orbit-cli` is the Node.js command-line wrapper for Orbit
applications. It generates MoonBit sources, builds and verifies directory
packages, creates Windows installers and Linux archives, and drives native
Linux package tools.

The package requires Node.js 20 or newer and a compatible MoonBit toolchain.
Commands that compile an application also require the native platform SDKs used
by that application.

```sh
npx @nanaloveyuki/orbit-cli build --config orbit.conf.json
npx @nanaloveyuki/orbit-cli package --config orbit.conf.json --release --out-dir dist
npx @nanaloveyuki/orbit-cli linux-package --package-dir dist --format deb --allow-unsigned
```

Production installer, archive, and native-package commands require an external
`--sign-command`. `--allow-unsigned` is only an explicit local-development
opt-out. See the repository [README](https://github.com/Nanaloveyuki/orbit) and
[`docs/releasing.md`](https://github.com/Nanaloveyuki/orbit/blob/main/docs/releasing.md)
for configuration, artifact verification, and release workflows.

License: Apache-2.0.
