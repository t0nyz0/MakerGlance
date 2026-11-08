import XCTest
@testable import MakerPulseCore

final class DirectMessageAnalyticsTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_790_000_000)
    private func library() -> LibraryState { var value = LibraryState(); value.preferences.userID = "42"; return value }
    private func conversation(_ id: String = "one", messageID: String = "first", serverID: String? = nil,
        seconds: Double = 0, unread: Int = 1, direction: DirectMessageDirection = .incoming,
        option: DirectMessageReceiveOption = .normal, contentType: Int = 101) -> DirectMessageConversation {
        DirectMessageConversation(conversationID: id, unreadCount: unread, receiveOption: option,
            latestMessage: DirectMessageMetadata(clientMessageID: messageID, serverMessageID: serverID,
                sessionType: 1, direction: direction, sentAt: time.addingTimeInterval(seconds), contentType: contentType))
    }
    private func batch(_ rows: [DirectMessageConversation]) throws -> DirectMessageBatch {
        try DirectMessageBatch(conversations: rows, conversationTotal: rows.count, unreadTotal: rows.reduce(0) { $0 + $1.unreadCount })
    }
    private func ingest(_ rows: [DirectMessageConversation], metadata: inout DirectMessageState?, state: inout LibraryState,
        seconds: Double = 0, enabled: Bool = true) throws -> [Activity] {
        try DirectMessageAnalytics.ingest(batch(rows), profileID: "42", metadata: &metadata, into: &state,
            at: time.addingTimeInterval(seconds), notificationsEnabled: enabled)
    }
    func testFirstSnapshotShowsUnreadExampleWithoutDesktopAlertAndRestartDoesNotReplay() throws {
        var state = library(), metadata: DirectMessageState?
        XCTAssertTrue(try ingest([conversation()], metadata: &metadata, state: &state).isEmpty)
        XCTAssertEqual(state.activity.count, 1); XCTAssertFalse(state.activity[0].isRead)
        metadata = try JSONDecoder().decode(DirectMessageState.self, from: JSONEncoder().encode(metadata!))
        state = try JSONDecoder().decode(LibraryState.self, from: JSONEncoder().encode(state))
        XCTAssertTrue(try ingest([conversation()], metadata: &metadata, state: &state, seconds: 10).isEmpty)
        XCTAssertEqual(state.activity.count, 1)
    }
    func testNewIncomingAlertsOnceAndPreservesExistingReadAndDismissal() throws {
        var state = library(), metadata: DirectMessageState?
        _ = try ingest([conversation()], metadata: &metadata, state: &state)
        state.activity[0].isRead = true
        let old = state.activity[0]
        let next = conversation(messageID: "second", seconds: 10)
        let alerts = try ingest([next], metadata: &metadata, state: &state, seconds: 11)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(state.activity.first { $0.id == old.id }, old)
        state.dismissedActivityIDs = [alerts[0].id]; state.activity.removeAll { $0.id == alerts[0].id }
        XCTAssertTrue(try ingest([next], metadata: &metadata, state: &state, seconds: 12).isEmpty)
        XCTAssertEqual(state.activity, [old])
    }
    func testIdentityAliasesAreConversationScopedAndEnrichmentIsQuiet() throws {
        var state = library(), metadata: DirectMessageState?
        _ = try ingest([conversation()], metadata: &metadata, state: &state)
        XCTAssertTrue(try ingest([conversation(serverID: "remote")], metadata: &metadata, state: &state, seconds: 1).isEmpty)
        XCTAssertEqual(state.activity.count, 1)
        let other = conversation("two", seconds: 2)
        XCTAssertEqual(try ingest([other], metadata: &metadata, state: &state, seconds: 3).count, 1)
        XCTAssertEqual(Set(state.activity.map(\.id)).count, 2)
    }
    func testOutgoingReadControlAndMutedMessagesDoNotProduceDesktopAlertsOrReplay() throws {
        var state = library(), metadata: DirectMessageState?
        _ = try ingest([], metadata: &metadata, state: &state)
        let rows = [conversation("out", seconds: 1, direction: .outgoing),
            conversation("read", seconds: 1, unread: 0),
            conversation("typing", seconds: 1, contentType: 113),
            conversation("recall", seconds: 1, contentType: 2101),
            conversation("blocked", seconds: 1, option: .notReceive),
            conversation("muted", seconds: 1, option: .notNotify)]
        XCTAssertTrue(try ingest(rows, metadata: &metadata, state: &state, seconds: 2).isEmpty)
        XCTAssertEqual(state.activity.count, 1)
        let unmuted = conversation("muted", seconds: 1)
        XCTAssertTrue(try ingest([unmuted], metadata: &metadata, state: &state, seconds: 3).isEmpty)
        XCTAssertEqual(state.activity.count, 1)
    }
    func testOldBackfillAndSameTimestampDoNotAlertAndDisabledEventsAreConsumed() throws {
        var state = library(), metadata: DirectMessageState?
        _ = try ingest([conversation()], metadata: &metadata, state: &state)
        XCTAssertTrue(try ingest([conversation("old", seconds: -10), conversation(messageID: "changed")], metadata: &metadata, state: &state, seconds: 1).isEmpty)
        XCTAssertEqual(state.activity.count, 1)
        let fresh = conversation(messageID: "new", seconds: 2)
        XCTAssertTrue(try ingest([fresh], metadata: &metadata, state: &state, seconds: 3, enabled: false).isEmpty)
        XCTAssertTrue(try ingest([fresh], metadata: &metadata, state: &state, seconds: 4, enabled: true).isEmpty)
        XCTAssertEqual(state.activity.count, 2)
    }
    func testLatestOutgoingWatermarkPreventsOlderIncomingReplay() throws {
        var state = library(), metadata: DirectMessageState?
        _ = try ingest([conversation(direction: .outgoing)], metadata: &metadata, state: &state)
        _ = try ingest([conversation(messageID: "sent", seconds: 20, direction: .outgoing)], metadata: &metadata, state: &state, seconds: 21)
        XCTAssertTrue(try ingest([conversation(messageID: "older", seconds: 10)], metadata: &metadata, state: &state, seconds: 22).isEmpty)
        XCTAssertTrue(state.activity.isEmpty)
    }
    func testMalformedFutureMessageLeavesBothValuesUnchanged() throws {
        var state = library(), metadata: DirectMessageState?
        _ = try ingest([], metadata: &metadata, state: &state)
        let before = metadata, activity = state.activity
        XCTAssertThrowsError(try ingest([conversation("valid", seconds: 1), conversation("future", seconds: 10_000)], metadata: &metadata, state: &state, seconds: 2))
        XCTAssertEqual(metadata, before); XCTAssertEqual(state.activity, activity)
    }
    func testAccountMismatchCannotMixMetadataOrHistory() throws {
        var state = library(), metadata: DirectMessageState?
        _ = try ingest([conversation()], metadata: &metadata, state: &state)
        state.preferences.userID = "43"
        XCTAssertThrowsError(try DirectMessageAnalytics.ingest(batch([]), profileID: "43", metadata: &metadata, into: &state, at: time))
        XCTAssertEqual(state.activity.count, 1)
    }
    func testConflictingAliasesDoNotAlterHistoryOrConsumeValidRows() throws {
        var state = library(), metadata: DirectMessageState?
        _ = try ingest([conversation(serverID: "server-one")], metadata: &metadata, state: &state)
        _ = try ingest([conversation(messageID: "second", serverID: "server-two", seconds: 1)], metadata: &metadata, state: &state, seconds: 2)
        let before = metadata, activity = state.activity
        XCTAssertThrowsError(try ingest([conversation("valid", seconds: 3), conversation(serverID: "server-two", seconds: 3)], metadata: &metadata, state: &state, seconds: 4))
        XCTAssertEqual(metadata, before); XCTAssertEqual(state.activity, activity)
        XCTAssertEqual(try ingest([conversation("valid", seconds: 3)], metadata: &metadata, state: &state, seconds: 4).count, 1)
    }
    func testServerOnlyIdentityLaterGainsClientAliasWithoutChangingActivity() throws {
        var state = library(), metadata: DirectMessageState?
        var row = conversation(serverID: "remote"); row.latestMessage?.clientMessageID = nil
        _ = try ingest([row], metadata: &metadata, state: &state)
        let original = state.activity[0]
        XCTAssertTrue(try ingest([conversation(serverID: "remote")], metadata: &metadata, state: &state, seconds: 1).isEmpty)
        XCTAssertEqual(state.activity, [original])
    }
    func testSparseClientServerBridgeDoesNotCreateConflictingCanonicalIDs() throws {
        for serverFirst in [false, true] {
            var state = library(), metadata: DirectMessageState?
            var first = conversation(serverID: "remote")
            if serverFirst { first.latestMessage?.clientMessageID = nil } else { first.latestMessage?.serverMessageID = nil }
            _ = try ingest([first], metadata: &metadata, state: &state)
            state.activity[0].isRead = true
            let original = state.activity[0]
            var sparse = conversation(serverID: "remote")
            if serverFirst { sparse.latestMessage?.serverMessageID = nil } else { sparse.latestMessage?.clientMessageID = nil }
            XCTAssertTrue(try ingest([sparse], metadata: &metadata, state: &state, seconds: 1).isEmpty)
            XCTAssertTrue(try ingest([conversation(serverID: "remote")], metadata: &metadata, state: &state, seconds: 2).isEmpty)
            XCTAssertEqual(state.activity, [original])
        }
    }
    func testPersistenceContainsNoOpaqueRawIdentifiersOrMessageContent() throws {
        var state = library(), metadata: DirectMessageState?
        _ = try ingest([conversation("private-conversation", messageID: "private-client", serverID: "private-server")], metadata: &metadata, state: &state)
        let data = try JSONEncoder().encode(metadata!)
        let text = String(decoding: data, as: UTF8.self)
        for value in ["private-conversation", "private-client", "private-server", "42", "content", "senderName", "token"] {
            // Numeric profile ID is checked as a JSON string, not a hash substring.
            XCTAssertFalse(text.contains(value == "42" ? "\"42\"" : value))
        }
    }
    func testPendingDeliveryUsesCurrentReadDismissedAndEnrichedRows() {
        var state = library()
        let queued = Activity(id: "direct:test", date: time, title: "Old", detail: "Old", symbol: "bell")
        var updated = queued; updated.title = "Enriched"
        state.activity = [updated]
        XCTAssertEqual(ActivityAlerts.pending([queued, queued], in: state), [updated])
        state.activity[0].isRead = true
        XCTAssertTrue(ActivityAlerts.pending([queued], in: state).isEmpty)
        state.activity[0].isRead = false; state.dismissedActivityIDs = [queued.id]
        XCTAssertTrue(ActivityAlerts.pending([queued], in: state).isEmpty)
        state.dismissedActivityIDs = []; state.activity = []
        XCTAssertTrue(ActivityAlerts.pending([queued], in: state).isEmpty)
    }
}
