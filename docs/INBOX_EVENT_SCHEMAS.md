# Verified inbox event fields

The inbox parser independently implements the following observed MakerWorld web schemas. The service is undocumented; this is bounded coverage rather than a claim to support every notification type.

The field relationships were checked on November 7, 2026 against MakerWorld's own public notification renderer, available in an existing local browser cache. No browser navigation, browser credential access, notification read action or account mutation was needed. The public scripts were inspected as source and were not executed or incorporated into this repository.

Primary references:

- [Current notification renderer](https://makerworld.com/_next/static/chunks/41623-70e23858eb71225c.js), SHA-256 `02f4035657070ea0b46b3b4101eb17bf0a45cf1c301f40f2a6e15a7d1e54892b`.
- [Earlier notification renderer](https://makerworld.com/_next/static/chunks/61073-026bddcf4fe0dd7d.js), SHA-256 `e6c71ff9bdb21f6136d097962b65619e707797c0b305ec5bacdef462f1662237`.

The web renderer selects numeric types and reads these payload fields. MakerGlance uses its own concise English summaries, with supplied names and context when present. It does not reproduce a remote template without its required data.

| Type | Payload | Verified context |
| --- | --- | --- |
| 101 | `draftSliceFailed` | `draftInfo.instanceTitle`, `draftInfo.designTitle`; slicing failure |
| 104 | `instancePublished` | `instanceInfo.title`; published print profile |
| 106 | `instanceAddToDesign` | `instanceInfo.title`, `designInfo.title`, envelope `from`; includes a donated-profile variant |
| 107 | `draftImportFinished` | `draftImportInfo.successNum`, `draftImportInfo.failedNum`; import completion does not imply every import succeeded |
| 254 | `instanceRatingRemind` | `instanceInfo.title`, `designInfo.title`, `designInfo.id`; rating reminder in the Models category |
| 368 | `auditSystem` | `content`, `contentDetail`, `opDesc`; review links lead to the copyright service |
| 401 | `system` | `systemInfo.title`, `systemInfo.newContent`; standard system-message variant |
| 412 | `systemForWeb` | `systemInfo.title`, `systemInfo.newContent`; web system-message variant |
| 501 | `pointBoostingRightGet` | `expireAt`; boost-token receipt, distinct from a model receiving boosts |
| 502 | `pointBoostingRightExpireRemind` | `expireAt`; boost-token expiry reminder |
| 604 | `communityPostFollowingLatest` | `user.name`, `user.handle`, `user` identity; post by a followed creator |
| 811 | `newSubscriberForCreator` | `userInfo.name`, `userInfo.handle`, `membershipLevelInfo.title`; new subscriber in the System category |
| 815 | `newBadgeReceived` | `badgeTitle`, optional `sparkAward.milestone`; badge award |

Shared user and model IDs/covers follow the existing user/design objects. Missing values remain absent. Unknown types continue to show their numeric type and feed category. Adjacent type numbers are not evidence for another event's meaning.

## Saved-history repair

Before starting polling, the app repairs generic saved titles for these verified types. It cannot reconstruct names, membership tiers, expiry dates or models that an older parser discarded. Missing details are described explicitly; a subsequent response with the same server ID quietly enriches that existing event.

The repair does not create Activity entries, change IDs, read state, dismissals, notification preferences or seen-ID sets, or emit notifications. Existing dismissed entries remain dismissed. Supplied model IDs are also added to existing Activity when later verified. A bounded dictionary of sanitized display fields is saved with new parsed events. A sparse later response merges those fields for the same ID/type and preserves already verified context, including across restart. This stores selected display metadata, not raw payloads.

The local connection report records bounded inbox type and field-name summaries for the newest page of each feed category. It excludes field values, message IDs, names, message bodies and credentials. It does not retain raw inbox payloads.

## Validation boundaries

Synthetic fixtures exercise the verified shapes, missing fields, conflicting payloads, HTML cleanup, length limits, quiet repair, restart persistence, preferences, dismissals, enrichment, sparse refetch and baseline/deduplication. They use fictional identities and do not prove availability of every live-service variant. Public cached code establishes the schema used by that renderer; it is not a guarantee against future upstream changes.
