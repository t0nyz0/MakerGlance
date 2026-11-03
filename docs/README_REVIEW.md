# README functionality and presentation review

Review date: 2026-11-03. Scope: the 3.9.2 source-publication candidate, its README, existing fictional demo media and the evidence supporting its feature descriptions.

## First impression

The opening identifies the product as a native Mac dashboard for MakerWorld creators, explains the questions it answers and shows the actual app before asking readers to open a presentation. A feature table makes model monitoring, trends/reports, activity/alerts, followers, points/wallet, My Prints and desktop controls visible without opening a disclosure section.

Public monitoring and connected private features are distinguished near that table. Build instructions remain explicit about the source-preview status. The account-free fictional demo command is visible in the quick start. Screenshots/GIFs retain their fictional-data labels, image descriptions, reduced-motion alternatives and links to full views.

## Claims checked against the implementation

| README feature | Supporting code and verification |
| --- | --- |
| Model metrics, observed growth, sorting and Cards/Compact | ModelActivity, ModelCheckRecency and WatchedModelSort/selection tests; hosted native range, sorting, layout and pointer regressions |
| Local trends and Creator Center period reports | HistorySeries, DailyGrowth and CreatorReport tests; the README distinguishes observed local dates from server UTC periods |
| Supported activity and local alert preferences | Account/parser and WatchAndPolling tests; Activity and Settings expose category controls, read and clear actions |
| Followers and identified single-follower profile links | Analytics and ActivityLinks tests; native follower search implementation and the previously confirmed typing/clear interaction |
| Separate point, estimate and wallet fields | Wallet, RewardReason and CashEstimateReason tests; incomplete or ambiguous reasons remain unverified |
| Cloud print history and controls | PrintHistory tests and hosted My Prints search/filter/date/sort regressions |
| Menu-bar, appearance, text sizing and window lifecycle | Hosted menu/window routing, persistence, appearance and text-size regressions |

The review does not claim real-time push, individual model print-event alerts, original follower dates, reconstructed missing history, printer control, in-app financial transactions, notarized downloads or guaranteed upstream service access. Private inbox, rewards, reports and cloud jobs require the connected service to expose the relevant data.

The unofficial-project and third-party-rights notices distinguish MakerGlance's MIT-licensed code and original assets from MakerWorld/Bambu Lab branding and creator-owned content. Third-party content remains subject to its own licenses and terms; the notice does not claim that MakerWorld owns creators' designs or that MakerGlance can license third-party material. MakerWorld [confirms that model copyrights belong to their creators](https://forum.bambulab.com/t/the-stolen-model-marketplace-keeps-growing/237722/31).

## QA boundary

The tested application and verification-script source is unchanged by this README pass. The approved source evidence remains 157 Swift tests, eight repository-tool tests and 48 hosted native checks. Final checks cover the prepared snapshot's file integrity, clean history, privacy scan, Markdown structure, navigation anchors, local image/document targets, accessible image labels and source-evidence consistency.

This is source-publication readiness. Live-account endpoints, Intel, oldest-target execution and downloaded-install/notarization remain separate from this review. Public visibility and the archive/import plan still require the owner's final approval.
