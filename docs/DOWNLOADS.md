# MakerGlance downloads

Download the Apple Silicon ZIP or DMG from the [MakerGlance 3.9.6 GitHub Release](https://github.com/t0nyz0/MakerGlance/releases/tag/v3.9.6). This release is version 3.9.6, build 34. The Performance menu shows snapshot net changes for rolling windows and returned daily totals for the prior UTC calendar month. It labels partial coverage per metric. [Release notes](https://github.com/t0nyz0/MakerGlance/blob/v3.9.6/docs/RELEASE_NOTES_3.9.6.md) · [Period definitions](https://github.com/t0nyz0/MakerGlance/blob/v3.9.6/docs/PERFORMANCE_PERIODS.md).

The build targets **Apple Silicon (arm64), macOS 14 or later**. Intel is not included. Testing used Apple Silicon on the current macOS; the oldest target has not been exercised.

## Signing and installation

This build is **locally ad-hoc signed, not Developer ID signed or notarized by Apple**. Its local signature checks file integrity; it does not verify the publisher through Apple's Developer ID program. macOS may display a developer warning or block a quarantined downloaded copy. No automatic bypass, security-setting change or Gatekeeper disabling is part of the app or installer. Building from the reviewed source remains an option.

A ZIP contains MakerGlance.app. A DMG contains the same app, an Applications shortcut, the MIT license and these notes. Copy the app to your chosen Applications folder. Updating the existing app preserves its legacy bundle identity, local library and Keychain session. Quit the old app before replacing it.

## Check the download

Compare the downloaded ZIP/DMG with the SHA-256 values in the release's SHA256SUMS.txt. BUILD.json records version, build, architecture, source commit and signing status. These checks detect corruption or mismatched assets; local ad-hoc signing does not establish a verified developer identity.

GitHub **Releases** is the distribution location for the native app. GitHub Packages is not a suitable native .app/DMG package ecosystem for this project, so no unrelated package/container is created.

## Account and monitoring limits

Choose your own creator profile. Private My Prints requires your existing authorized Bambu session; no Studio credentials are imported. Only cloud jobs exposed by the service are available. Offline/LAN-only or expired server history may be absent. Public model print counts remain separate.

Regular/exclusive points and cash fields stay distinct. Local notifications require macOS permission and the app running; this is polling, not server push. Undocumented services may change. This independent app is not affiliated with or endorsed by Bambu Lab or MakerWorld.

Direct messages require a separate explicit connection in Settings after connecting the existing Bambu session. Connecting may sign another MakerWorld chat client out. Message bodies and sender names are not saved or included in alerts. The first sync stays quiet. Expired chat connections require an explicit reconnect. [Direct-message behavior and limits](https://github.com/t0nyz0/MakerGlance/blob/v3.9.6/docs/DIRECT_MESSAGES.md).
