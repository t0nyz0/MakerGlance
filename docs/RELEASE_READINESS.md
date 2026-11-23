# Release readiness

## MakerGlance 3.9.9, build 37

This update collects the model card pill fix, automatic read status on opening the main window or menu bar panel, and the full scrollable tray activity list. [Release notes](RELEASE_NOTES_3.9.9.md).

All 258 Swift tests and eight repository tool tests passed. The installed Apple Silicon app matches the verified build, and the installer recorded its successful launch. The isolated GUI audit could not start in the build session, so the tray interaction and macOS 14 launch remain unverified. [Local source validation](LOCAL_VALIDATION.json).

## MakerGlance 3.9.6, build 34

This build restores original sidebar styling, bounds Models card hit areas, and adds the Dashboard performance-period menu. The pointer correction and period feature have separate local validation records. [Release notes](RELEASE_NOTES_3.9.6.md), [period definitions](PERFORMANCE_PERIODS.md), and [current source validation](LOCAL_VALIDATION.json).

Actual Models filter pointer reliability and the new menu’s native layout, keyboard and VoiceOver behavior remain unverified. The local test evidence covers source, headless regressions and package integrity.

The tested build was installed and reopened. The build manifest records the exact executable hash and identifies the tested source commit separately from the release documentation commit. The release uses ad-hoc signing and targets Apple Silicon on macOS 14 or later. Historical release sections describe their own builds.

## MakerGlance 3.9.5, build 31

Direct-message support is implemented against the verified deployed REST contract, with metadata-only storage and alerts, explicit connection, separate Keychain storage, quiet baselines, sequence deduplication, token-expiry handling and transactional protection against stale saves. See [DM contract](DIRECT_MESSAGES.md), [release notes](RELEASE_NOTES_3.9.5.md) and [current local source validation](LOCAL_VALIDATION.json).

Authorized live checks verified authentication/profile ownership, all three read-only endpoints and unchanged remote read watermarks. Private payloads and credentials are absent from source, fixtures and reports. The published 3.9.5 and 3.9.4 tags and build manifests retain the evidence for those releases.

Current validation passes 243 unit tests, 58 independently rerun DM regressions, optimized build/signature verification and the repository/documentation checks. Live service validation and direct native UI checks of the DM switch/layout also pass.

Validation for this notification update is scoped to direct-message parsing, authentication, history completeness, duplicate alerts, local read/dismissed state, credential privacy and the focused native DM controls. Those checks pass. No further unrelated native-matrix investigation is required for this scoped handoff.

The broader native automation was inconsistent: release runs stopped at My Prints/menu and dashboard pointer assertions, while the focused native controls worked through actual native input. A subsequent instrumented debug run completed all 50 checks. This does not certify the full release layout/text-size matrix or establish the cause of the earlier failures. It remains a residual testing limitation; no DM-related product regression was identified.

3.9.5 build 31 was installed and reopened with owner authorization. The installed executable matches the verified optimized build and passes strict signature verification. The existing Bambu session restored, the direct-message connection completed through Settings, and a live check persisted a quiet conversation baseline. Existing Activity identities/read state, dismissals, seen IDs, preferences and watch rules were preserved. No new unread message was available during the live checks, so a real new-message desktop alert remains unobserved; automated incoming-message and alert regressions pass.

The owner authorized packaging, pushing and publishing 3.9.5 on November 8, 2026, with the existing signing disclosures and live-banner limitation. The release workflow packages the verified executable, records its binary provenance separately from documentation-only commits, and verifies the ZIP, read-only DMG contents, checksums and anonymous public downloads. Local build and installation evidence is retained separately from published source and assets.

## MakerGlance 3.9.4, build 30

The owner authorized publishing this GitHub Release with the Apple Silicon ZIP, DMG, checksums and release notes on November 7, 2026, after being informed that the app is ad-hoc signed and not notarized by Apple.

The application source was verified at commit `7fc5e382e70742b6e76c318bb86b267f5b9fdd36`. Release documentation may advance the release tag without changing the tested executable. The build manifest records the release source commit and binary provenance. Package regeneration updates the embedded download notes and checksums while preserving the verified application bytes.

## Validation

- 185 Swift tests, including 21 inbox regressions also run independently.
- Eight repository-tool tests, current-tree/history privacy guards and documentation checks.
- 48 isolated native checks using fictional data without network or Keychain access.
- Optimized Apple Silicon build, exact bundle inventory, signature and machine-path checks.
- Extracted ZIP and read-only DMG content verification, executable equality and asset checksums.
- Installed version/build and executable verified; application reopened and the live subscriber description checked through its existing authorized session.
- Local repair/reingest checks preserve event IDs, read state, dismissals and seen-ID baselines without replaying historical alerts.

See [local source validation](LOCAL_VALIDATION.json), [release notes](RELEASE_NOTES_3.9.4.md) and [verified inbox schemas](INBOX_EVENT_SCHEMAS.md). Local evidence is not a hosted CI result.

## Distribution limits

The downloads target Apple Silicon and macOS 14 or later. Intel is not included. The oldest supported macOS target and a quarantined downloaded launch have not been exercised.

The app is locally ad-hoc signed, not Developer ID signed or notarized by Apple. macOS may display a developer warning or block a quarantined download. No security-setting change or Gatekeeper bypass is part of the release. [Download and installation notes](DOWNLOADS.md).

The local packaging script creates ZIP/DMG assets, checksums and a manifest; it does not publish. The separate owner-authorized GitHub Release step uploads the reviewed files and is followed by anonymous public download verification. No repository visibility change is needed.

## Source-history boundary

The clean public source repository was established in November 2026. Original development history remains in the private archive. Continue from the clean public repository; never force-push the archived clone or its original refs into the public repository. Private libraries, credentials, account payloads, build caches, diagnostic images and backup bundles stay outside published source and release assets.
