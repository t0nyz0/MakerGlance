# Integration and limits

MakerGlance uses undocumented Bambu/MakerWorld routes. This is not an official SDK or a service-level guarantee. Account access, schemas, caps and availability can change; incomplete responses preserve the last verified state.

## Data definitions

| Metric | Source used by the client |
| --- | --- |
| Profile likes | `likeCount` |
| Profile design downloads / prints | `MWCount.myDesignDownloadCount` / `MWCount.myDesignPrintCount` |
| Profile boosts / saves / followers | `boostGained` / `collectionCount` / `fanCount` |
| Model totals | `likeCount`, `downloadCount`, `printCount`, `boostCnt`, `collectionCount` |

The separate top-level profile `downloadCount` is retained as raw source data, not substituted for design downloads. `favoritesCount` is not the aggregate collection-save count. Missing fields remain unavailable. A v1 migration preserves earlier raw observations without fabricating design-download history.

## Read-only routes

Public profile, published-design and fan pages use the design-user/design services. Authentication offers the existing user-initiated email-code/MFA and own-session flows. Private messages, point progress/history, cash estimate, wallet summary/income and Creator Center period data require a valid session.

The app does not mark server messages read, mutate remote notification preferences, redeem points, withdraw or transfer money, or publish/delete models. Sign-in requests are the only implemented account mutation category.

Private inbox coverage is limited to the exposed categories and returned history. Stable event IDs are remembered locally. Quiet initial imports prevent historical alert storms. Model count alerts and feed boosts are merged only where matching server identifiers/counts support it.

## Histories and dates

- Local snapshots begin when observation starts. Today is a local calendar day with explicit partial coverage; the other activity windows are rolling.
- Latest-check markers compare successful comparable observations. Failed/omitted fields preserve comparison state, and initial baselines do not create growth.
- Creator Center can supply period tables and server daily history where a session can access the web data. Those dates are UTC+0. HTML page data is discovered without hardcoding an ephemeral Next.js build ID. Login redirects or challenges are errors, not zero activity.
- First-observed follower dates belong to this app's observations. They never claim an original relationship timestamp. Existing baseline dates stay unknown.
- Collection saves are aggregate counts. No individual collection identity/event is promised.

## Rewards and notifications

Regular/exclusive points, the cash-redemption estimate and wallet balances remain distinct, with original currency and decimal-safe arithmetic. Missing observations retain the previous value/date with stale labeling. A reason is linked to a balance change only when actual transaction identity, time and exact reconciliation support it. Ledger rows without server IDs use account-scoped semantic fingerprints and occurrence counts. Model/donor metadata is independent of server IDs. A reason can match an observed balance window when all relevant entries reconcile exactly; it is never presented as a server transaction-ID link. Metadata enrichment preserves those identities. Missing or ambiguous matches remain pending with readable ledger details.

Point-change notifications wait for a ledger match for up to 30 minutes; a pending change then notifies once. Later backfills quietly enrich that same local activity without replaying it. Pending notification state survives restart, and changes older than a day are not replayed. Cash notifications retain their wallet-specific matching behavior.

Notifications are local, coalesced polling results requiring macOS authorization. They stop while the app is quit or the Mac sleeps. Profile milestones include exposed counts; model alert controls currently cover boosts, likes, downloads and aggregate saves. Visual print growth does not imply individual print-event notifications.

Requests use bounded pagination, deduplication, pacing and transient backoff. Numeric/profile totals are not benchmark or throughput guarantees. Live-service verification is separate from offline tests and demo screenshots.

## My Prints

My Prints reads `GET /v1/user-service/my/tasks?offset=…&limit=20` through the existing app session and global Bambu API client. This is independently implemented Swift, without Studio/plugin code or credential extraction. The route is an undocumented cloud service, not a guaranteed supported public API. [Studio’s published interface](https://github.com/bambulab/BambuStudio/blob/master/src/slic3r/Utils/NetworkAgent.hpp) exposes a user-tasks query; no AGPL implementation is copied into this project.

Task IDs are scoped to the configured account. Complete imports, actual-count offsets, duplicate removal, repeat-page detection and changing-total checks prevent partial crawls from replacing saved history. Recent checks continue through known unfinished jobs; full crawls run hourly and on explicit refresh. Saved records absent from a later full crawl remain local and are labeled as saved copies. Unknown task statuses are explicit; stopped codes are grouped as canceled/failed rather than claiming a specific cause. A UI filter never mutates server or local job data.

Names, covers, printer/plate context and timestamps are shown only when supplied. Completed elapsed time is derived from start/end; `costTime` remains a slice estimate. Filament fields are not presented as measured usage. Private signed covers use only the exact verified Bambu cloud bucket, keep the original query unchanged, and use a memory-only image session/cache. No app bearer session is sent to the image host.

My Prints does not increment public model print metrics, send printer commands, reprint, or emit initial-import alerts. This is polled history, not live device telemetry. Access, retention, offline/LAN job coverage and regional-session behavior can vary. The current native integration was verified on a global-region account; a China-region login/API is not silently selected or newly provisioned.
