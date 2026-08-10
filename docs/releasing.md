# Releasing Orbit And Orbit Applications

Orbit framework releases and application releases are separate workflows. The
framework publishes the Mooncake module and npm CLI. An application uses a
pinned Orbit CLI to build and publish its own executables and installers.

## Orbit Framework Release

The repository `release` environment must contain `NPM_TOKEN`,
`MOONCAKE_USERNAME`, and `MOONCAKE_TOKEN`. Protect that environment with the
required reviewers for the repository.

1. Update `moon.mod` and `orbit-cli/package.json` to the same version.
2. Merge the version change through the normal validation workflow.
3. Create and push the matching protected tag, for example
   `v0.1.0-alpha.2`.

The release workflow verifies the tag, runs MoonBit and Node tests, performs a
Mooncake dry run, packs the npm artifact, creates a draft GitHub Release,
attests the artifacts, publishes npm with provenance, publishes Mooncake, and
only then makes the GitHub Release public. A failure leaves the GitHub Release
as a draft for inspection.

`.moon-version` selects an installer-supported MoonBit channel. CI records the
resolved compiler and build-tool versions with `moon version --all` before
validation so every release retains the exact toolchain identity in its logs.

Mooncake's publish command intentionally runs without `--frozen`: its own
verification extracts the package into a fresh directory and must install the
declared dependencies there. Source validation still runs after `moon update`
and before either registry is modified. Moon CLI can return a non-zero,
platform-dependent exit code after a successful dry-run response; the tested
wrapper accepts such an exit only when the output contains both the `202 Accepted`
status and the explicit no-changes success message.

## Linux Application Packages

Build the directory package in release mode on Linux before selecting a native
format:

```sh
orbit package --config orbit.conf.json --release --out-dir dist
orbit verify-package --package-dir dist
orbit linux-package --package-dir dist --format deb --out-dir artifacts \
  --sign-command 'sign-linux {artifact} {package_dir} {package_manifest}'
orbit verify-linux-package --artifact artifacts/example_1.0.0-1_amd64.deb
```

Run `linux-package` separately in an Ubuntu/Debian, Fedora, or Arch build job
for `deb`, `rpm`, or `arch`. Orbit invokes that distribution's standard
`dpkg-deb`, `rpmbuild`, or `makepkg`; it does not route builds through WSL or
containers automatically. `makepkg` must run as an unprivileged user.

Every artifact has an adjacent `*.orbit-linux-package.json` file containing the
final size and SHA-256, source package compatibility profile, architecture,
format, package revision, and whether the external signing hook ran. The flag
records hook execution; signature trust must still be checked with the signing
system's own verification command before publication.

Application repositories should publish the native artifact, Orbit metadata,
the signing system's detached signature or bundle, and a `SHA256SUMS` file.
Keep GitHub authentication and release creation in the application's CI rather
than placing GitHub API access inside Orbit CLI.
