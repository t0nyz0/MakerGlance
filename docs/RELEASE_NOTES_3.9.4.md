# MakerGlance 3.9.4 inbox descriptions

Build 29 identifies more MakerWorld notifications and quietly improves saved descriptions.

- New subscriber notifications use the supplied subscriber and membership tier.
- Print-profile rating reminders, published/added profiles, slicing failures, import results, boost-token receipt/expiry notices, followed-creator community posts, web system messages, copyright review updates and badge awards have explicit descriptions.
- Older generic entries for verified types receive readable titles. Details that were never saved remain unavailable until supplied by MakerWorld.
- Repair and later enrichment preserve server IDs, original dates, read state, dismissals and notification preferences without replaying old alerts. Later model context also repairs existing Activity links.
- A sparse later response preserves previously verified context for the same event. Value-free inbox schema diagnostics help identify future unsupported shapes.

The existing bundle, local library and Keychain identities are retained. This does not mark MakerWorld notifications read, change remote settings or add account permissions. Unknown types remain explicit.

See [verified schemas and validation boundaries](INBOX_EVENT_SCHEMAS.md). Local Apple Silicon ZIP/DMG preparation is separate from publishing a GitHub Release. Builds remain ad-hoc signed and are not notarized.
