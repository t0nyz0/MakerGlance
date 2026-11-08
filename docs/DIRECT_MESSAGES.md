# Direct-message integration investigation

Status: development work, **not connected, installed or released**. Ordinary MakerWorld direct messages are not supported by the released 3.9.4 application. The new standalone parser and analytics have no active API, UI or library-persistence caller. They must remain disconnected until MakerWorld's deployed response and authentication behavior are verified.

## Confirmed cause

`MakerWorldAPI.accountEvents()` reads only the six `/v1/user-service/my/messages` categories: comments, models, system, device, community and crowdfunding. Ordinary direct messages use a separate OpenIM chat connection in MakerWorld's own client. They cannot be added by assigning another label to an unknown inbox event. Crowdfunding message sessions are also a different service.

MakerWorld's public [message-page JavaScript](https://makerworld.com/_next/static/chunks/pages/my/message-0a1218e823f87ee9.js) configures `/v1/im-service/api` and `/v1/im-service/msg`, requests chat authentication with `platformId: 5`, then calls OpenIM login with a user ID, token and platform ID. The conversation list uses `getConversationListSplit`; its latest-message summary contains stable message IDs and unread counts.

The same client calls `markConversationMessageAsRead` when a conversation is selected and `markMessagesAsReadByMsgID` when messages enter the viewport. Opening the user's unread example in that interface would therefore change remote read state. This investigation did not open or render it.

The public [_app JavaScript](https://makerworld.com/_next/static/chunks/pages/_app-115368d5c13c9720.js) resolves the token helper to GET `/my/im/token` under `design-user-service`, giving `/v1/design-user-service/my/im/token?platformId=5` before the website proxy prefix. The chat API host is runtime configuration; the public script alone does not verify an active API origin or deployed HTTP contract.

## Authentication side effect and current blockers

Upstream OpenIM [token creation](https://github.com/openimsdk/open-im-server/blob/9502a1a15fe63f6342fb1e2d8068346a82f278d8/pkg/common/storage/controller/auth.go#L88) can invalidate another client token, before any websocket login. Policies at lines 135–264 include same-platform eviction and policies that may evict Web when a PC/native client authenticates. [Websocket login](https://github.com/openimsdk/open-im-server/blob/9502a1a15fe63f6342fb1e2d8068346a82f278d8/internal/msggateway/ws_server.go#L333) has additional eviction handling. Requesting native macOS platform 4 is not proof that the browser session will be preserved. MakerWorld's deployed policy remains unknown.

The user has been asked whether a connection test may potentially sign out browser chat. That permission is pending. No IM token was requested, no websocket was opened and no read-marking operation was issued. A no-prompt read of MakerGlance's own Keychain item returned macOS authentication failure (`-25293`); no credential was displayed or exported. Normal Keychain consent may also be required. Browser credential stores must not be used as a workaround.

## Prepared implementation

`DirectMessage.swift` implements a strict, metadata-only parser for the public upstream OpenIM sorted-conversation response. It discards participant IDs after direction classification and never retains names, message bodies, attachment URLs, credentials or raw payloads. Error strings are fixed and contain no response values. The [upstream protocol](https://github.com/openimsdk/protocol/blob/1a91e17bd182dd97e0229c0798f5428dfa2cd2ed/conversation/conversation.proto#L62) supplies the fields; this is not a captured MakerWorld response.

`DirectMessageAnalytics.swift` prepares:

- Strict full pagination with stable totals, unique conversations, aggregate unread reconciliation, bounded page counts and cancellation propagation. Incomplete snapshots cannot establish a baseline.
- A quiet initial snapshot. Currently unread incoming direct messages can appear locally without replaying desktop alerts.
- Conversation-scoped client/server identity aliases and timestamp watermarks. Stored identity keys are hashes. Sparse older/equal-time observations do not establish competing canonical identities; an explicit later alias bridge can enrich the original identity.
- Filtering of outgoing, group/system, read, typing, recall and unsupported content types. Remote muted conversations do not create desktop alerts. Only verified user-message types 101–105 are eligible.
- Atomic staging before mutation, account isolation and preservation of existing local read/dismissed entries. Re-enabling notifications cannot replay already consumed observations.

No new `EventKind` values were introduced. The old released decoder therefore has no new persisted enum value to encounter. No direct-message state has been added to the live library.

`ActivityAlerts.pending` also fixes an existing delivery race: after refresh work suspends, the delivery stage now checks the current activity row and its read/dismissed state, using current enriched metadata. A local mark-read action wins over a previously queued banner.

The candidate upstream HTTP operation is POST `/conversation/get_sorted_conversation_list` with an owner token, `userID` and `pagination.pageNumber/showNumber`. The [server handler](https://github.com/openimsdk/open-im-server/blob/9502a1a15fe63f6342fb1e2d8068346a82f278d8/internal/rpc/conversation/conversation.go#L137) reads latest messages and read sequences without marking them read. [Owner-token verification](https://github.com/openimsdk/open-im-server/blob/9502a1a15fe63f6342fb1e2d8068346a82f278d8/pkg/authverify/token.go#L70) permits a matching user. **Its availability, authorization and exact JSON on MakerWorld remain unverified.**

## Remaining implementation and verification

1. Resolve explicit consent for the potential chat-client sign-out and use the normal macOS consent path for the existing app session.
2. Validate that session against the monitored profile. Test only the verified token wrapper and read-only conversation operation; retain a report of field names/types and aggregate results, never private content or credentials. Do not guess additional endpoints after a mismatch.
3. Confirm the real unread example, runtime host, response casing, time semantics, token expiry and pagination. The upstream handler assigns `LatestMsgRecvTime` from message send time; MakerWorld must be checked before displaying that as the original message date.
4. Add an explicit chat connection with a meaningful session-side-effect explanation. Store any approved chat credential separately in Keychain, avoid silent token creation/renewal, and require reconnect on expiry. Do not silently interfere with browser chat during background polling.
5. Wire optional backward-compatible state into the atomic library commit, local notification controls, connection status and polling. Recheck pending preferences/read/dismissal immediately before desktop delivery.
6. Run independent QA against the deployed contract, restart/rollback and the real unread example without reading it remotely. Then version, build, install/reopen and package a new release according to the normal release workflow. No package from this development work is ready for distribution.

Latest-conversation summaries cannot reconstruct all messages received between polls. The prepared conservative watermark policy also suppresses distinct messages with identical timestamps. Complete per-message coverage would require a separately verified read-only history/sequence contract; the application must not claim it from this endpoint alone.

## Reproducible public-source evidence

Only public static code was inspected from the local Firefox HTTP cache. No browser session navigation or credential-store extraction was used.

- Message-page gzip SHA256: `06e3b7293e2efc72566716d97d2c10f81a5990151bad9426480faac4c2aadbef`. Decoded offsets: list call approximately 28738; API/WS configuration approximately 33700; conversation read marking approximately 44145; viewport read marking approximately 73175.
- `_app` first gzip member SHA256: `6429cba2880eeffd7df019ccc3078f97d02ff27fbe9586d02c7667e5cf295099`; decoded SHA256: `ce1d6a18a470f9f3a6906dc4b939f544b9a5436a41395d725123a31e73a6368b`. Decoded offsets: helper module 49451; `/my/im/token` 54207; service export 73627; service wrapper 75564.

Synthetic parser, analytics, pagination, privacy and delivery-race tests accompany the implementation. They establish local behavior against the documented contract; they do not establish live MakerWorld compatibility.

Local validation: 217 unit tests passed, including 32 new tests independently rerun with XCTest; the production build and strict ad-hoc signature verification passed. Repository/history scanning, documentation checks, validation badges and all eight repository-tool tests passed. No live account test or native DM interface test was performed. The validation app retains the development branch's unchanged 3.9.4/build 30 version and must not be confused with a new release package.
