# MakerGlance preview downloads

Release assets are being prepared. Until an approved GitHub Release is published, build from source using the README. Local preparation is not a published download.

The preview build targets **Apple Silicon (arm64), macOS 14 or later**. Intel is not included. Testing used Apple Silicon on the current macOS; the oldest target has not been exercised.

## Signing and installation

This build is **locally ad-hoc signed, not Developer ID signed or notarized**. macOS may block a quarantined downloaded copy. No automatic bypass, security-setting change or Gatekeeper disabling is part of the app or installer. Building from the reviewed source remains an option.

A ZIP contains MakerGlance.app. A DMG contains the same app, an Applications shortcut, the MIT license and these notes. Copy the app to your chosen Applications folder. Updating the existing app preserves its legacy bundle identity, local library and Keychain session. Quit the old app before replacing it.

## Check the download

Compare the downloaded ZIP/DMG with the SHA-256 values in the release's SHA256SUMS.txt. BUILD.json records version, build, architecture, source commit and signing status. These checks detect corruption or mismatched assets; local ad-hoc signing does not establish a verified developer identity.

GitHub **Releases** is the distribution location for the native app. GitHub Packages is not a suitable native .app/DMG package ecosystem for this project, so no unrelated package/container is created.

## Account and monitoring limits

Choose your own creator profile. Private My Prints requires your existing authorized Bambu session; no Studio credentials are imported. Only cloud jobs exposed by the service are available. Offline/LAN-only or expired server history may be absent. Public model print counts remain separate.

Regular/exclusive points and cash fields stay distinct. Local notifications require macOS permission and the app running; this is polling, not server push. Undocumented services may change. This independent app is not affiliated with or endorsed by Bambu Lab or MakerWorld.
