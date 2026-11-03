# MakerGlance 3.9 preview

My Prints brings your own Bambu cloud print history into a native, searchable workspace, separate from your models' public print counts.

- Print/model thumbnails, printer and plate names, recorded dates and status.
- Search, printer/status/date filters, newest/oldest and elapsed-time sorting.
- Read-only details with recorded elapsed time separate from slice estimates.
- Local account-scoped task history, stable-ID updates, bounded pagination and preserved saved records after failed imports.
- Recent/unfinished jobs checked during polling; full cloud imports hourly and on Refresh history.
- Private signed thumbnail URLs stay unchanged and images use memory-only requests/cache.
- Release packaging strips compiler machine paths and verifies exact bundle contents.

Stopped records are grouped as **Canceled / failed** where the cloud does not distinguish the cause. Unknown/missing values remain explicit. This is saved history, not live printer telemetry. No printer commands, reprint action, filament-usage guarantees or new print notifications are added.

The preview assets are **Apple Silicon arm64 only**, target macOS 14+, are locally ad-hoc signed and **not notarized**. Quarantined downloads may be blocked by macOS. No public distribution is implied by local package preparation; publication follows the separate repository privacy review.
