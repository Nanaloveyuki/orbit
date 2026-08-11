# Security Policy

Orbit is pre-release software. `0.1.0-alpha.4` may change its public API, but
security defects affecting the documented Windows x64 support surface are still
handled as release blockers.

Do not open a public issue for a vulnerability that could expose application
data, bypass a capability policy, execute untrusted native code, or compromise
the packaging/signing flow. Instead use GitHub's private security advisory flow
for this repository and include a minimal reproduction, affected platform,
Orbit version or commit, and impact assessment.

The maintainers will acknowledge reports, determine whether a fix is required
before the next prerelease, and publish a release note once a fix is available.
