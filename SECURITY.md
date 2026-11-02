# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| `0.1.x` | Yes |
| pre-0.1 local builds | Best-effort only |

Open LAN Scanner is an early (`0.x`) open-source project. Security fixes are applied to the latest release line when feasible.

## What this app does with network data

- Scans only the address ranges you enter.
- Stores preferences and favorites locally on your Mac.
- Does not include telemetry or automatic upload of scan results.
- Optional OUI dataset updates are explicit and user-initiated.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Use **GitHub Security Advisories** on this repository:

1. Open the repository on GitHub.
2. Go to **Security → Advisories → Report a vulnerability**.
3. Include steps to reproduce, affected versions, and impact.

If Security Advisories are unavailable for your account type, open a private report via GitHub’s private vulnerability reporting UI for this repo when enabled by the maintainer.

Do not include secrets, private keys, or live network dumps that contain sensitive hostnames or credentials in public channels.

## Scope notes

- Discovery probes can be noisy on a LAN; that is expected behavior, not by itself a vulnerability.
- Unsigned or ad-hoc builds from CI are not notarized; Gatekeeper warnings for those artifacts are expected.
- Privilege escalation requiring a signed helper tool is out of scope until such a helper is intentionally introduced and documented.
