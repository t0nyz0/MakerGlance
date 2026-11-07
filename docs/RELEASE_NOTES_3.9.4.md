# MakerGlance 3.9.4 inbox descriptions

Build 30 identifies more MakerWorld notifications and quietly improves saved descriptions.

- New subscriber notifications use the supplied subscriber and membership tier.
- Print-profile rating reminders, published/added profiles, slicing failures, import results, boost-token receipt/expiry notices, followed-creator community posts, standard/web system messages, copyright review updates and badge awards have explicit descriptions.
- Older generic entries for verified types receive readable titles. Details that were never saved remain unavailable until supplied by MakerWorld.
- Repair and later enrichment preserve server IDs, original dates, read state, dismissals and notification preferences without replaying old alerts. Later model context also repairs existing Activity links.
- A sparse later response preserves previously verified context for the same event. Value-free inbox schema diagnostics help identify future unsupported shapes.

The existing bundle, local library and Keychain identities are retained. This does not mark MakerWorld notifications read, change remote settings or add account permissions. Unknown types remain explicit.

## Downloads and signing

The [3.9.4 GitHub Release](https://github.com/t0nyz0/MakerGlance/releases/tag/v3.9.4) provides Apple Silicon ZIP and DMG downloads, SHA-256 checksums and a build manifest. These builds target macOS 14 or later; Intel is not included.

The app is **ad-hoc signed, not Developer ID signed or notarized by Apple**. macOS may display a developer warning or block a quarantined downloaded copy. The release does not bypass Gatekeeper or change security settings. See [download and installation notes](DOWNLOADS.md).

Validation passed 185 Swift tests, including 21 independently run inbox tests, eight repository-tool tests and 48 isolated native checks, plus bundle/signature/architecture, extracted ZIP and read-only DMG verification. The installed app and live subscriber description were verified separately. The oldest supported macOS target and a quarantined download launch were not tested. Unsupported event types remain explicit. See [verified schemas and validation boundaries](INBOX_EVENT_SCHEMAS.md).
