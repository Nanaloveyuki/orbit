# Releasing Orbit

This document is for Orbit maintainers publishing the Mooncakes module, npm
CLI, and GitHub Release. Application packaging is documented separately in
[`packaging.md`](packaging.md).

## Orbit Framework Release

The repository `release` environment must contain `MOONCAKE_USERNAME` and
`MOONCAKE_TOKEN`. Protect that environment with the required reviewers for the
repository. Configure npm trusted publishing for `@nanaloveyuki/orbit-cli`
with GitHub owner `Nanaloveyuki`, repository `orbit`, workflow `release.yml`,
environment `release`, and the `npm publish` action. The workflow uses GitHub
OIDC and must not receive an npm write token.

1. Update `moon.mod` and `orbit-cli/package.json` to the same version.
2. Merge the version change through the normal validation workflow.
3. Create and push the matching protected tag, for example
   `v0.1.0-alpha.4`.

The release workflow verifies the tag, runs MoonBit and Node tests, performs a
Mooncake dry run, packs the npm artifact, creates a draft GitHub Release,
attests the artifacts, publishes npm with provenance, publishes Mooncake, and
only then makes the GitHub Release public. A failure leaves the GitHub Release
as a draft for inspection. npm prereleases use their first prerelease identifier
as the dist-tag (`alpha.1` uses `alpha`); stable versions use `latest`.

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

Application repositories should pin the Orbit CLI version, publish the native
artifact together with Orbit metadata, include the signing system's detached
signature or bundle and a `SHA256SUMS` file, and keep GitHub authentication in
their own CI rather than placing GitHub API access inside Orbit CLI.
