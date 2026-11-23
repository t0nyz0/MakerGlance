# MakerGlance downloads

Download the Apple Silicon ZIP or DMG from [GitHub Releases](https://github.com/t0nyz0/MakerGlance/releases/latest). Version 3.9.9, build 37 adds the full activity list to the menu bar, marks existing notifications read when opened, and shows more metric changes on model cards. [3.9.9 release notes](RELEASE_NOTES_3.9.9.md).

The build targets **Apple Silicon (arm64), macOS 14 or later**. Intel is not included. Testing used Apple Silicon on the current macOS; the oldest target has not been exercised.

## Signing and installation

This build is **locally ad-hoc signed, not Developer ID signed or notarized by Apple**. Its local signature checks file integrity; it does not verify the publisher through Apple's Developer ID program. macOS may display a developer warning or block a quarantined downloaded copy. No automatic bypass, security-setting change or Gatekeeper disabling is part of the app or installer. Building from the reviewed source remains an option.

A ZIP contains MakerGlance.app. A DMG contains the same app, an Applications shortcut, the MIT license and these notes. Quit the old app, then replace it in your chosen Applications folder. Your local library and saved credentials carry over. macOS may ask again for separate approval to read the Bambu session and MakerWorld direct message credential.

## Check the download

Compare the downloaded ZIP/DMG with the SHA-256 values in the release's SHA256SUMS.txt. BUILD.json records version, build, architecture, source commit and signing status. These checks detect corruption or mismatched assets; local ad-hoc signing does not establish a verified developer identity.

GitHub **Releases** is the distribution location for the native app. GitHub Packages is not a suitable native .app/DMG package ecosystem for this project, so no unrelated package/container is created.

## Account and monitoring limits

Choose your own creator profile. Private My Prints requires your existing authorized Bambu session; no Studio credentials are imported. Only cloud jobs exposed by the service are available. Offline/LAN-only or expired server history may be absent. Public model print counts remain separate.

Regular/exclusive points and cash fields stay distinct. Local notifications require macOS permission and the app running; this is polling, not server push. Undocumented services may change. This independent app is not affiliated with or endorsed by Bambu Lab or MakerWorld.

Direct messages require a separate explicit connection in Settings after connecting the existing Bambu session. Connecting may sign another MakerWorld chat client out. Message bodies and sender names are not saved or included in alerts. The first sync stays quiet. Expired chat connections require an explicit reconnect. [Direct-message behavior and limits](https://github.com/t0nyz0/MakerGlance/blob/v3.9.6/docs/DIRECT_MESSAGES.md).
