# MakerWorld direct-message integration

Available in MakerGlance 3.9.5/build 31. Direct messages require a separate explicit connection in Settings; upgrading alone does not create a chat credential.

## Why direct messages were missing

The account inbox reads six categories from `/v1/user-service/my/messages`. Ordinary direct messages use MakerWorld’s separate OpenIM service, so assigning labels to unknown inbox event types cannot make DMs appear.

MakerWorld’s public [message-page client](https://makerworld.com/_next/static/chunks/pages/my/message-0a1218e823f87ee9.js) configures `/v1/im-service/api` and `/v1/im-service/msg`. Its public [WASM SDK](https://public-cdn.bblmw.com/im/wasm/openIM.wasm) embeds `github.com/OpenIMSDK/protocol v0.0.14`. The SDK display string alone does not establish an exact server release.

Authorized live verification confirmed the native API origin `https://api.bambulab.com`, the authentication wrapper and all three read operations below. An incoming message supplied the expected stable IDs, sender/recipient, type, sequence and millisecond timestamp. Before/after remote read watermarks were identical. No private message body, participant identity or credential was retained in reports or fixtures.

## Connection and storage

Connect the existing Bambu session, then choose **Settings → Direct messages → Connect direct messages**. The monitored profile is validated before the explicit platform-4 chat-token request. Connecting may sign another MakerWorld chat client out; the interface explains that effect before connecting. Normal macOS Keychain approval may be required.

Chat credentials are stored separately in Keychain. Polling and startup reuse the saved credential; neither silently requests a fresh token. Expiry, invalidation or a kicked token requires an explicit reconnect. Removing a connection preserves Activity history.

History requests necessarily receive transient message response data. Whitelist decoding discards content, names, attachments, participant IDs and other unused fields. SQLite stores generic Activity rows, hashed identities, timestamps and sequence watermarks. Alerts contain no message text or sender name. Opening a desktop notification opens local Activity; the user can choose to open MakerWorld messages from Settings.

## Verified read-only contract

| Operation | JSON request | Relevant response |
| --- | --- | --- |
| GET `/v1/design-user-service/my/im/token?platformId=4` | Existing validated Bambu bearer session; explicit connection only | `userId`, `token`, `expireIn` |
| POST `/v1/im-service/api/conversation/get_all_conversations` | `ownerUserID` | `data.conversations` with owner, peer, type, receive option and visibility fences |
| POST `/v1/im-service/api/msg/get_conversations_has_read_and_max_seq` | `userID`, `conversationIDs` | `data.seqs` containing numeric `maxSeq` and `hasReadSeq` |
| POST `/v1/im-service/api/msg/pull_msg_by_seq` | `userID`, `seqRanges[{conversationID,begin,end,num}]`, `order:0` | `data.msgs[conversationID].Msgs` and Boolean `isEnd` |

IM queries carry `token` and `operationID` headers, without the Bambu bearer credential. They use the existing ephemeral HTTPS transport and same-origin redirect restrictions. No websocket, chat SDK dependency, send, mark-read or remote preference operation is used.

Exact protocol fields appear in [conversation.proto](https://github.com/openimsdk/protocol/blob/v0.0.14/conversation/conversation.proto#L20), [sequence metadata](https://github.com/openimsdk/protocol/blob/v0.0.14/msg/msg.proto#L183) and [message history](https://github.com/openimsdk/protocol/blob/v0.0.14/sdkws/sdkws.proto#L143). The compatible [server route](https://github.com/openimsdk/open-im-server/blob/ff9b2582291d29c500e45d0ffbe92b837b5e199e/internal/api/route.go#L169) and [history handler](https://github.com/openimsdk/open-im-server/blob/ff9b2582291d29c500e45d0ffbe92b837b5e199e/internal/rpc/msg/sync_msg.go#L31) read messages without changing read state. HTTP 200 token errors 1501–1507 are recognized using the [deployed tools definitions](https://github.com/openimsdk/tools/blob/v0.0.5/errs/code.go#L77).

The newer upstream sorted-conversation endpoint returned 404 on MakerWorld and is not used. An unread sequence delta alone can briefly include an outgoing send, so every displayed message must prove single-conversation incoming direction and supported user content type from actual metadata.

## Baselines, completeness and alerts

The first successful sync imports currently unread incoming messages quietly and records every direct-conversation sequence watermark. Subsequent refreshes fetch bounded explicit sequence ranges, including multiple messages between polls. Only new incoming user messages of supported types 101–105 can alert; outgoing, unrelated participants, typing, recall, unsupported controls and deleted messages do not.

Stable identities are scoped to the monitored profile and conversation. Sequence-backed Activity IDs stay deterministic across restart, sparse ID enrichment and an older application round trip. Already-read messages fetched after another client read them can appear locally as read without an alert. Later remote reads do not change an existing local read/dismissed decision. Remote muted conversations remain visible but do not generate desktop alerts. Disabled alerts consume observations so enabling them cannot replay old messages.

Every requested conversation and sequence map must be present. Deleted-history gaps and explicit `Msgs:null` are supported according to the verified contract; a missing conversation is a failed refresh, even when the envelope says success. Requests use at most 100 sequences per range, 5,000 sequences per refresh and 5,000 conversations. Over-budget, malformed, failed or cancelled refreshes do not commit a partial baseline.

The DM ledger and rows are also protected at the SQLite transaction boundary. A stale Creator/public/control save cannot erase a newer DM baseline. Local read and dismissed states win over pending delivery, and conflicting identity maps reject the transaction. Equal-time messages have a stable display order.

## Public-source provenance

- Message-page gzip SHA256: `06e3b7293e2efc72566716d97d2c10f81a5990151bad9426480faac4c2aadbef`. It configures chat near decoded offset 33700 and marks messages read when conversations/messages are selected or viewed. The investigation did not navigate that interface.
- Public WASM: 27,820,783 bytes, SHA256 `2be2a16208ca8cada59c0950473d9e172714514926f1db8b010d89befa27632a`. Embedded protocol version appears near byte 18723218; get-all and sequence routes near bytes 17837371 and 17857966.
- The `_app` helper resolves GET `/my/im/token` under `design-user-service`. Its decoded SHA256 is `ce1d6a18a470f9f3a6906dc4b939f544b9a5436a41395d725123a31e73a6368b`.

Only public static code and authorized API calls supplied integration evidence. No browser credential store, credential export, browser navigation or server read-marking operation was used. Synthetic unit/regression tests and independent QA cover the production contract without including captured private payloads.
