# MakerGlance 3.9.5 direct-message notifications

Build 31 for Apple Silicon (arm64), macOS 14 or later.

**Signing: ad-hoc signed, not Developer ID signed or notarized by Apple.** macOS may display a developer warning or block a quarantined download. No security-setting change or Gatekeeper bypass is part of this release.

- Connect MakerWorld direct messages from Settings using the existing Bambu session. Connecting may sign another chat client out; normal Keychain approval may be required.
- See generic incoming-message updates in Activity and enable their desktop alerts separately. Message bodies and sender names are not saved or included in alerts.
- Keep the initial sync quiet. Stable sequence/identity baselines prevent replay after restart, sparse metadata, mute changes or re-enabling alerts.
- Reuse the saved chat credential until it expires or is invalidated, then reconnect explicitly. Polling never creates a fresh chat token automatically.
- Preserve local read/dismissed status and remote read state. Stale report saves cannot roll back the DM ledger, and marking a queued update read suppresses its banner.

The implementation uses verified read-only native REST requests without adding a chat SDK or websocket dependency. [Contract, privacy and limits](DIRECT_MESSAGES.md).

## Verification and limits

Passed 243 Swift unit tests, including 58 direct-message regressions also run independently, plus eight repository-tool tests and focused native checks of the direct-message controls. The optimized build was installed and reopened; the live connection and quiet baseline were verified while preserving existing history, read state, dismissals and preferences.

No genuinely unread message was available during live checks, so an actual new-message desktop banner remains unobserved. Synthetic incoming-message, deduplication and alert regressions pass. Broader native automation was inconsistent; the full release layout/text-size matrix is not certified. No direct-message product regression was identified.

Intel is not included. The oldest supported macOS target and a quarantined downloaded launch were not tested. MakerWorld services are undocumented and may change or require reconnecting. [Download and signing notes](DOWNLOADS.md).
