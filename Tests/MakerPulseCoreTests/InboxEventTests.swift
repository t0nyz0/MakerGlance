import XCTest
@testable import MakerPulseCore

final class InboxEventTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func parse(_ json: String, group: EventKind? = .system) throws -> [AccountEvent] {
        try AccountParser.events(Data(json.utf8), group: group).items
    }
    private func old(_ type: String, id: String = "sample-event") -> AccountEvent {
        AccountEvent(id: id, kind: .system, rawType: type, title: "MakerWorld update (\(type))",
            detail: "MakerWorld event type \(type). Details are unavailable for this event type.", occurredAt: now,
            presentation: ActivityPresentation(kind: .system, originalTimestamp: true))
    }
    private func saved(_ events: [AccountEvent]) -> LibraryState {
        var state = LibraryState(); state.account = AccountState()
        state.account?.eventsImported = true
        state.account?.events = events
        state.account?.seenEventIDs = Set(events.map(\.id))
        state.activity = events.map { Activity(id: "remote:" + $0.id, date: $0.occurredAt ?? now, title: $0.title, detail: $0.detail, symbol: $0.kind.symbol, presentation: $0.presentation) }
        return state
    }

    func testSubscriberUsesNestedIdentityAndTierRatherThanEnvelopeSender() throws {
        let event = try XCTUnwrap(parse(#"{"hits":[{"id":"sample-event","type":811,"from":{"name":"System","uid":999},"createTime":"2026-11-07T21:48:24Z","newSubscriberForCreator":{"userInfo":{"uid":42,"name":"Sample member","handle":"samplemember","avatar":"https://cdn.bblmw.com/member.jpg"},"membershipLevelInfo":{"title":"Standard","creatorInfo":{"name":"Creator"}}}}]}"#).first)
        XCTAssertEqual(event.title, "New subscriber"); XCTAssertEqual(event.kind, .system)
        XCTAssertEqual(event.detail, "Sample member subscribed to your Standard membership tier.")
        XCTAssertEqual(event.presentation?.actorID, "42"); XCTAssertEqual(event.presentation?.actorHandle, "samplemember")
        XCTAssertFalse(event.detail.contains("System")); XCTAssertFalse(event.detail.contains("Creator"))
        XCTAssertEqual(event.occurredAt, ISO8601DateFormatter().date(from: "2026-11-07T21:48:24Z"))
        XCTAssertNil(event.modelID); XCTAssertNil(event.metricCorrelationID)
    }
    func testSubscriberMissingFieldsDoNotInventIdentityTierOrTimestamp() throws {
        let rows = try parse(#"{"hits":[{"id":1,"type":"811"},{"id":2,"type":811,"newSubscriberForCreator":{"userInfo":{"name":"Sample"}}},{"id":3,"type":811,"newSubscriberForCreator":{"membershipLevelInfo":{"title":"Standard"}}}]}"#)
        XCTAssertTrue(rows[0].detail.contains("unavailable")); XCTAssertNil(rows[0].presentation?.actorName)
        XCTAssertNil(rows[0].occurredAt); XCTAssertEqual(rows[0].presentation?.originalTimestamp, false)
        XCTAssertTrue(rows[1].detail.contains("Tier details are unavailable"))
        XCTAssertTrue(rows[2].detail.contains("Subscriber details are unavailable"))
    }
    func testSubscriberPartialRefetchMergesFieldsAfterRestartWithoutReplay() throws {
        let full = try parse(#"{"hits":[{"id":"sample-event","type":811,"createTime":"2026-11-07T21:48:24Z","newSubscriberForCreator":{"userInfo":{"uid":42,"name":"Sample member"},"membershipLevelInfo":{"title":"Standard"}}}]}"#)
        for fragment in [#""userInfo":{"name":"Updated member"}"#, #""membershipLevelInfo":{"title":"Updated tier"}"#] {
            var state = saved(full)
            state = try JSONDecoder().decode(LibraryState.self, from: JSONEncoder().encode(state))
            let sparse = try parse("{\"hits\":[{\"id\":\"sample-event\",\"type\":811,\"newSubscriberForCreator\":{\(fragment)}}]}")
            XCTAssertTrue(AccountAnalytics.ingestEvents(sparse, into: &state, at: now).isEmpty)
            XCTAssertFalse(state.activity[0].detail.contains("unavailable"))
            XCTAssertEqual(state.activity.count, 1); XCTAssertFalse(state.activity[0].isRead)
            if fragment.contains("userInfo") { XCTAssertEqual(state.activity[0].detail, "Updated member subscribed to your Standard membership tier.") }
            else { XCTAssertEqual(state.activity[0].detail, "Sample member subscribed to your Updated tier membership tier.") }
            XCTAssertEqual(state.activity[0].presentation?.actorID, "42")
        }
    }
    func testKnownTypeDoesNotReadAnUnrelatedPayload() throws {
        let event = try XCTUnwrap(parse(#"{"hits":[{"id":1,"type":811,"from":{"name":"Wrong identity"},"designCommented":{"content":"Wrong message"}}]}"#).first)
        XCTAssertEqual(event.title, "New subscriber"); XCTAssertFalse(event.detail.contains("Wrong"))
        XCTAssertNil(event.presentation?.actorName)
    }
    func testRatingReminderExtractsProfileAndModelWithModelCategory() throws {
        let event = try XCTUnwrap(parse(#"{"hits":[{"id":1,"type":254,"instanceRatingRemind":{"instanceInfo":{"id":8,"title":"Fast profile"},"designInfo":{"id":7,"title":"Sample model","cover":"https://cdn.bblmw.com/model.jpg"}}}]}"#).first)
        XCTAssertEqual(event.kind, .model); XCTAssertEqual(event.modelID, "7")
        XCTAssertTrue(event.detail.contains("Fast profile")); XCTAssertTrue(event.detail.contains("Sample model"))
        XCTAssertNil(event.metricCorrelationID)
    }
    func testBoostTokenMessagesStayDistinctFromModelBoostsAndKeepSuppliedExpiry() throws {
        let rows = try parse(#"{"hits":[{"id":1,"type":501,"pointBoostingRightGet":{"expireAt":"2026-12-01T12:00:00Z"}},{"id":2,"type":502,"pointBoostingRightExpireRemind":{"expireAt":"2026-12-02T12:00:00Z"}}]}"#)
        XCTAssertEqual(rows.map(\.kind), [.system, .system])
        XCTAssertEqual(rows[0].title, "Boost tokens received"); XCTAssertEqual(rows[1].title, "Boost token expiry reminder")
        XCTAssertTrue(rows[0].detail.contains("2026-12-01T12:00:00Z")); XCTAssertTrue(rows[1].detail.contains("2026-12-02T12:00:00Z"))
        XCTAssertTrue(rows.allSatisfy { $0.metricCorrelationID == nil && $0.modelID == nil })
    }
    func testCommunityUsesPayloadUserAndDoesNotInferModelIdentity() throws {
        let event = try XCTUnwrap(parse(#"{"hits":[{"id":1,"type":604,"communityPostFollowingLatest":{"user":{"uid":42,"name":"Sample maker","handle":"sample"},"post":{"id":7}}}]}"#).first)
        XCTAssertEqual(event.kind, .community); XCTAssertEqual(event.presentation?.actorID, "42")
        XCTAssertTrue(event.detail.contains("Sample maker")); XCTAssertNil(event.modelID)
    }
    func testSystemMessageTitleAndRichTextAreReadableAndBounded() throws {
        let event = try XCTUnwrap(parse(#"{"hits":[{"id":1,"type":412,"systemForWeb":{"systemInfo":{"title":"<b>Announcement</b>","newContent":"<p>Hello &amp; welcome</p><script>hidden()</script><p>Next line</p>"}}}]}"#).first)
        XCTAssertEqual(event.title, "Announcement"); XCTAssertEqual(event.detail, "Hello & welcome Next line")
        let long = try JSONSerialization.data(withJSONObject: ["hits": [["id": 2, "type": 412, "systemForWeb": ["systemInfo": ["title": String(repeating: "x", count: 1000), "newContent": String(repeating: "y", count: 5000)]]]]])
        let bounded = try XCTUnwrap(AccountParser.events(long).items.first)
        XCTAssertEqual(bounded.title.count, 300); XCTAssertEqual(bounded.detail.count, 2000)
    }
    func testBadgeImportAndReviewReadOnlySuppliedFields() throws {
        let rows = try parse(#"{"hits":[{"id":1,"type":815,"newBadgeReceived":{"badgeTitle":"Sample badge","sparkAward":{"milestone":100}}},{"id":2,"type":107,"draftImportFinished":{"draftImportInfo":{"successNum":0,"failedNum":2}}},{"id":3,"type":368,"auditSystem":{"content":"Review update","contentDetail":"Details","opDesc":"Action explanation"}}]}"#)
        XCTAssertEqual(rows[0].detail, "Badge received: Sample badge · Print milestone: 100")
        XCTAssertEqual(rows[1].detail, "Imported: 0 · Failed: 2")
        XCTAssertEqual(rows[2].detail, "Review update · Details · Action explanation")
    }
    func testPopulatedProfilePublishingSlicingAndDonationShapes() throws {
        let rows = try parse(#"{"hits":[{"id":1,"type":101,"draftSliceFailed":{"draftInfo":{"instanceTitle":"Draft profile","designTitle":"Draft model"}}},{"id":2,"type":104,"instancePublished":{"instanceInfo":{"title":"Published profile"}}},{"id":3,"type":106,"from":{"uid":42,"name":"Sample donor"},"instanceAddToDesign":{"donatedByInfo":{"donatedByUid":42},"instanceInfo":{"title":"Donated profile"},"designInfo":{"id":7,"title":"Sample model"}}}]}"#)
        XCTAssertEqual(rows[0].detail, "Draft model · Draft profile")
        XCTAssertEqual(rows[1].detail, "Published profile")
        XCTAssertEqual(rows[2].detail, "Sample donor · Sample model · Donated profile")
        XCTAssertEqual(rows[2].presentation?.actorID, "42"); XCTAssertEqual(rows[2].modelID, "7")
        XCTAssertTrue(rows.allSatisfy { $0.kind == .model })
    }
    func testPartialBadgeAndRatingContextPreserveEarlierFields() throws {
        let full = try parse(#"{"hits":[{"id":"badge","type":815,"createTime":"2026-11-07T21:48:24Z","newBadgeReceived":{"badgeTitle":"Sample badge","sparkAward":{"milestone":100}}},{"id":"rating","type":254,"createTime":"2026-11-07T21:48:24Z","instanceRatingRemind":{"instanceInfo":{"title":"Sample profile"},"designInfo":{"id":7,"title":"Sample model"}}}]}"#)
        var state = saved(full)
        let sparse = try parse(#"{"hits":[{"id":"badge","type":815,"newBadgeReceived":{"sparkAward":{"milestone":200}}},{"id":"rating","type":254,"instanceRatingRemind":{"designInfo":{"title":"Updated model"}}}]}"#)
        XCTAssertTrue(AccountAnalytics.ingestEvents(sparse, into: &state, at: now).isEmpty)
        XCTAssertEqual(state.activity[0].detail, "Badge received: Sample badge · Print milestone: 200")
        XCTAssertEqual(state.activity[1].detail, "Updated model · Sample profile")
        XCTAssertEqual(state.activity[1].modelID, "7")
    }
    func testPresentationContentSharesTheFinalCombinedDetailBound() throws {
        let value = String(repeating: "x", count: 1800)
        let data = try JSONSerialization.data(withJSONObject: ["hits": [["id": 1, "type": 368, "auditSystem": ["content": value, "contentDetail": value, "opDesc": value]]]])
        let event = try XCTUnwrap(AccountParser.events(data).items.first)
        XCTAssertEqual(event.detail.count, 2000); XCTAssertEqual(event.presentation?.content, event.detail)
    }
    func testAllSupportedNumericFallbacksHaveExplicitKindsAndDoNotReadPrivateValues() throws {
        for definition in InboxEventParser.definitions {
            let data = try JSONSerialization.data(withJSONObject: ["hits": [["id": "fictional", "type": definition.type]]])
            let event = try XCTUnwrap(AccountParser.events(data).items.first)
            XCTAssertEqual(event.title, definition.title); XCTAssertEqual(event.detail, definition.summary)
            XCTAssertEqual(event.kind, definition.kind); XCTAssertNil(event.presentation?.actorID)
        }
    }
    func testUnsupportedTypesKeepHonestFallbackAndFeedCategory() throws {
        let event = try XCTUnwrap(parse(#"{"hits":[{"id":1,"type":99999,"futurePayload":{"userInfo":{"name":"Do not guess"}}}]}"#, group: .crowdfunding).first)
        XCTAssertEqual(event.kind, .crowdfunding); XCTAssertEqual(event.title, "MakerWorld update (99999)")
        XCTAssertTrue(event.detail.contains("unavailable")); XCTAssertNil(event.presentation?.actorName)
        XCTAssertNil(InboxEventParser.upgrade(event))
    }
    func testLocalRepairPreservesIdentityControlsAndActivityMembershipAcrossRestart() throws {
        var state = saved([old("811"), old("254", id: "dismissed"), old("99999", id: "unsupported")])
        state.activity[0].isRead = false; state.activity[2].isRead = true
        state.activity.removeAll { $0.id == "remote:dismissed" }; state.dismissedActivityIDs = ["remote:dismissed"]
        state.account?.preferences.eventNotifications = [.system]
        let before = state
        XCTAssertEqual(AccountAnalytics.repairEventDescriptions(in: &state), 2)
        XCTAssertEqual(state.activity.map(\.id), before.activity.map(\.id))
        XCTAssertEqual(state.activity.map(\.isRead), before.activity.map(\.isRead))
        XCTAssertEqual(state.account?.seenEventIDs, before.account?.seenEventIDs)
        XCTAssertEqual(state.dismissedActivityIDs, before.dismissedActivityIDs)
        XCTAssertEqual(state.account?.eventsImported, before.account?.eventsImported)
        XCTAssertEqual(state.account?.preferences, before.account?.preferences)
        XCTAssertEqual(state.activity[0].date, now); XCTAssertEqual(state.activity[0].title, "New subscriber")
        state = try JSONDecoder().decode(LibraryState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(AccountAnalytics.repairEventDescriptions(in: &state), 0)
        XCTAssertTrue(AccountAnalytics.ingestEvents(state.account!.events, into: &state, at: now).isEmpty)
        XCTAssertEqual(state.activity.count, 2)
    }
    func testHistoricalRepairDoesNotGuessSubscriberAndPreservesAlreadyRichDescriptions() {
        var event = old("811"); event.title = "New subscriber"; event.detail = "Previously verified detail"
        var state = saved([event, old("811", id: "old")])
        XCTAssertEqual(AccountAnalytics.repairEventDescriptions(in: &state), 1)
        XCTAssertEqual(state.account?.events[0].detail, "Previously verified detail")
        XCTAssertNil(state.account?.events[1].presentation?.actorID)
        XCTAssertTrue(state.account!.events[1].detail.contains("unavailable"))
    }
    func testFullPayloadQuietlyEnrichesRepairedUnreadEventAndModelLinks() throws {
        var state = saved([old("254")]); AccountAnalytics.repairEventDescriptions(in: &state)
        let rows = try parse(#"{"hits":[{"id":"sample-event","type":254,"instanceRatingRemind":{"designInfo":{"id":7,"title":"Sample model"},"instanceInfo":{"title":"Sample profile"}}}]}"#)
        XCTAssertTrue(AccountAnalytics.ingestEvents(rows, into: &state, at: now).isEmpty)
        XCTAssertEqual(state.activity.count, 1); XCTAssertFalse(state.activity[0].isRead)
        XCTAssertEqual(state.activity[0].modelID, "7"); XCTAssertTrue(state.activity[0].detail.contains("Sample profile"))
    }
    func testSparseRefetchDoesNotErasePreviouslyVerifiedDetails() throws {
        let rich = try parse(#"{"hits":[{"id":"sample-event","type":412,"createTime":"2026-11-07T21:48:24Z","systemForWeb":{"systemInfo":{"title":"Announcement","newContent":"Verified body"}}}]}"#)
        var state = saved(rich)
        let sparse = try parse(#"{"hits":[{"id":"sample-event","type":412}]}"#)
        XCTAssertTrue(AccountAnalytics.ingestEvents(sparse, into: &state, at: now).isEmpty)
        XCTAssertEqual(state.activity[0].title, "Announcement"); XCTAssertEqual(state.activity[0].detail, "Verified body")
        XCTAssertEqual(state.account?.events[0].presentation?.content, "Verified body")
        XCTAssertEqual(state.activity[0].date, rich[0].occurredAt)
    }
    func testNewSubscriberAlertIsQuietForBaselineAndDeliveredOnceWhenEnabled() throws {
        let rows = try parse(#"{"hits":[{"id":"sample-event","type":811}]}"#)
        var baseline = LibraryState(); XCTAssertTrue(AccountAnalytics.ingestEvents(rows, into: &baseline, at: now).isEmpty)
        var state = saved([])
        XCTAssertEqual(AccountAnalytics.ingestEvents(rows, into: &state, at: now).count, 1)
        XCTAssertTrue(AccountAnalytics.ingestEvents(rows, into: &state, at: now).isEmpty)
        var disabled = saved([]); disabled.account?.preferences.eventNotifications = []
        XCTAssertTrue(AccountAnalytics.ingestEvents(rows, into: &disabled, at: now).isEmpty)
        disabled.account?.preferences.eventNotifications = [.system]
        XCTAssertTrue(AccountAnalytics.ingestEvents(rows, into: &disabled, at: now).isEmpty)
    }
    func testInboxDiagnosticsRecordShapesAcrossTypesWithoutValuesOrUnknownTypeText() {
        let data = Data(#"{"hits":[{"id":123456789,"type":811,"newSubscriberForCreator":{"userInfo":{"name":"PRIVATE_PERSON"},"membershipLevelInfo":{"title":"PRIVATE_TIER"}}},{"id":2,"type":254,"instanceRatingRemind":{}},{"id":3,"type":"PRIVATE_TOKEN"}]}"#.utf8)
        let text = SchemaDiagnostics.describeInbox(data)
        XCTAssertTrue(text.contains("811:")); XCTAssertTrue(text.contains("254:")); XCTAssertTrue(text.contains("newSubscriberForCreator.userInfo"))
        for value in ["123456789", "PRIVATE_PERSON", "PRIVATE_TIER", "PRIVATE_TOKEN"] { XCTAssertFalse(text.contains(value)) }
    }
}
