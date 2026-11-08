# MakerGlance 3.9.5 direct-message notifications

Unreleased source, build 31. The current downloadable packages remain 3.9.4 until a separate verified release step.

- Connect MakerWorld direct messages from Settings using the existing Bambu session. Connecting may sign another chat client out; normal Keychain approval may be required.
- See generic incoming-message updates in Activity and enable their desktop alerts separately. Message bodies and sender names are not saved or included in alerts.
- Keep the initial sync quiet. Stable sequence/identity baselines prevent replay after restart, sparse metadata, mute changes or re-enabling alerts.
- Reuse the saved chat credential until it expires or is invalidated, then reconnect explicitly. Polling never creates a fresh chat token automatically.
- Preserve local read/dismissed status and remote read state. Stale report saves cannot roll back the DM ledger, and marking a queued update read suppresses its banner.

The implementation uses verified read-only native REST requests without adding a chat SDK or websocket dependency. [Contract, privacy and limits](DIRECT_MESSAGES.md).

This source still targets Apple Silicon and macOS 14 or later. Local validation builds are ad-hoc signed, not Developer ID signed or notarized by Apple. A packaged 3.9.5 release has not been published.
