# Automatic updates — planned approach

Open LAN Scanner does **not** ship an in-app updater in `0.1.0`.

## Recommendation

Use **[Sparkle](https://sparkle-project.org/)** when:

1. Releases are consistently **Developer ID signed** and **notarized**.
2. You can host an `appcast.xml` on HTTPS (GitHub Releases CDN or a static site).
3. An EdDSA Sparkle key pair is generated and the **private** key is stored only in a secure secret store (never in git).

## Bounded follow-up

- [ ] Add Sparkle package dependency and `SUFeedURL` / public key Info.plist keys
- [ ] Generate and document EdDSA key handling in `Docs/MAINTAINERS.md`
- [ ] Publish appcast from the release workflow
- [ ] Verify update from `0.x` → next patch on a clean Mac

Until then, document “download the latest release from GitHub” in the README.
