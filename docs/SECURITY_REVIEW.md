# Security and privacy review

Review date: 2026-11-03. Scope: current source and pending fixes, all reachable private development history, authentication/storage/network paths, public fixtures/media, packaging, documentation and GitHub publication boundaries.

## Historical privacy outcome

The private history's known-pattern scan covered 610 blobs and reported 162 machine-path occurrences. Commit metadata also contains one distinct personal email address. No checked credential pattern or prohibited library/key artifact was found. These checks do not prove the absence of every possible secret.

Current-file cleanup does not remove historical content. The reviewed publication approach preserves the original private repository and creates a fresh source snapshot with one root commit and account-scoped GitHub noreply metadata. The original private history is not part of the public candidate. No rewrite or visibility change was performed.

## Current source boundaries

- First launch selects the user's own creator. A saved library cannot silently change accounts.
- Validated session tokens use macOS Keychain. Database, WAL and SHM permissions are user-only. SQLite history is not app-encrypted.
- API and image redirects preserve HTTPS scheme, host and effective port. Shared cookies/credentials are disabled. Image requests carry no app bearer session; private signed cloud images use memory-only storage.
- Account operations are read-only except explicit sign-in. Notification read/clear actions and preferences stay local. No redemption, withdrawal, publishing or remote message mutation is implemented.
- Account-specific examples used during development have been replaced with fictional publication fixtures. Native demo media has original artwork, sample identities, no connected account and no live balance or inbox data.
- Source scans include new, untracked files. The publication copier rejects unsafe paths, symlinks and sensitive artifact names, and copies no Git history, ignored data or build output.
- The app uses Apple frameworks and system SQLite; it adds no third-party runtime package, analytics SDK, credential importer or developer-operated backend.

## Build and repository controls

Current validation records the complete local Swift and Python test suites, optimized ad-hoc app build, exact bundle inventory, binary machine-path guard, docs/presentation privacy checks and GIF validation. The icon container is generated from the original native artwork and decoded before signing. Public badges identify local evidence and are bound to the current Swift, package, version and build/verification scripts.

The manual public CI workflow has read-only permissions and a verified immutable checkout commit. A separate private branch passed publication preflight: 157 Swift tests, eight Python repository-tool tests, the optimized build and 48 native GUI checks. The native suite uses fictional data, no Keychain session and replayed transport. Existing Actions history and release collections were empty when checked. No account credentials are used in either workflow.

GitHub private vulnerability reporting is enabled for public repositories, so its final enablement/verification belongs to the owner-approved publication action. A safe security-contact issue form accepts no technical vulnerability details. Normal bug forms continue to prohibit account/private data.

## Limits

This is a scoped review, not a penetration test or security certification. Live service/authentication behavior is distinct from synthetic offline tests. Intel, oldest-target execution, Developer ID/notarization and downloaded-install behavior are not established. The private archive remains private until the owner separately changes that decision; it is not the approved public source snapshot.
