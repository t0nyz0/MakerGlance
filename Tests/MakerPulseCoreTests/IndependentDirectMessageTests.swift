import Foundation
import XCTest
@testable import MakerPulseCore

private actor IndependentDMErrorTransport: HTTPTransport {
    private var responses: [HTTPResult]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [HTTPResult]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.cannotConnectToHost) }
        return responses.removeFirst()
    }
}

final class IndependentDirectMessageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let secret = "INDEPENDENT-SYNTHETIC-PRIVATE-ERROR"
    private func response(_ object: Any) throws -> HTTPResult {
        HTTPResult(data: try JSONSerialization.data(withJSONObject: object), status: 200)
    }
    private func errorResponse(_ code: Int) throws -> HTTPResult {
        try response(["errCode": code, "errMsg": secret, "errDlt": secret])
    }
    private func isAuthentication(_ error: Error) -> Bool {
        if let service = error as? DirectMessageServiceError { return service == .authentication }
        if let pulse = error as? PulseError, case .authentication = pulse { return true }
        return false
    }
    private func assertRedacted(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(error.localizedDescription.contains(secret), file: file, line: line)
        XCTAssertFalse(String(describing: error).contains(secret), file: file, line: line)
    }

    // Both tools v0.0.5 (the deployed WASM dependency) and compatible server
    // tools v0.0.13 define these exact token codes in errs/code.go:77-84.
    func testHTTP200TokenErrorsRemainAuthenticationAtEveryParserBoundary() throws {
        for code in 1501...1507 {
            let data = try errorResponse(code).data
            let operations: [() throws -> Void] = [
                { _ = try DirectMessageServiceParser.conversations(data, userID: "self") },
                { _ = try DirectMessageServiceParser.sequences(data, conversationIDs: ["conversation"]) },
                { _ = try DirectMessageServiceParser.messages(data, conversationID: "conversation",
                    userID: "self", peerID: "peer", begin: 1, end: 1) }
            ]
            for operation in operations {
                XCTAssertThrowsError(try operation()) { error in
                    XCTAssertTrue(self.isAuthentication(error), "Token error \(code) lost authentication classification")
                    self.assertRedacted(error)
                }
            }
        }
    }

    func testHTTP200TokenFailureAtAnyPollingStageNeverRetriesOrMintsCredential() async throws {
        let conversations = try response(["errCode": 0, "data": ["conversations": [[
            "ownerUserID": "self", "conversationID": "conversation", "conversationType": 1,
            "userID": "peer", "recvMsgOpt": 0, "minSeq": 0, "maxSeq": 0
        ]]]])
        let sequences = try response(["errCode": 0, "data": ["seqs": [
            "conversation": ["maxSeq": 1, "hasReadSeq": 0]
        ]]])
        let credential = DirectMessageCredential(profileID: "42", userID: "self",
            token: "independent-fictional-chat-token", expiresAt: now.addingTimeInterval(3_600))
        let prefix = [conversations, sequences]
        for code in 1501...1507 {
            for stage in 0...2 {
                let transport = IndependentDMErrorTransport(Array(prefix.prefix(stage)) + [try errorResponse(code)])
                let service = DirectMessageService(transport: transport, minimumInterval: 0)
                do {
                    _ = try await service.snapshot(session: credential, known: nil, at: now)
                    XCTFail("Token failure must not yield a complete batch")
                } catch {
                    XCTAssertEqual(error as? DirectMessageServiceError, .authentication)
                    assertRedacted(error)
                }
                let requests = await transport.requests
                XCTAssertEqual(requests.count, stage + 1)
                XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "POST" && $0.url?.path.hasPrefix("/v1/im-service/api/") == true })
                XCTAssertFalse(requests.contains { $0.url?.path.contains("/token") == true })
            }
        }
    }

    func testOtherHTTP200ErrorsDoNotMasqueradeAsAuthenticationOrExposeDetails() async throws {
        let credential = DirectMessageCredential(profileID: "42", userID: "self",
            token: "independent-fictional-chat-token", expiresAt: now.addingTimeInterval(3_600))
        for code in [1001, 1404, 1500, 1508, 9999] {
            let transport = IndependentDMErrorTransport([try errorResponse(code)])
            let service = DirectMessageService(transport: transport, minimumInterval: 0)
            do {
                _ = try await service.snapshot(session: credential, known: nil, at: now)
                XCTFail("Unknown server failure must not yield a batch")
            } catch {
                XCTAssertEqual(error as? DirectMessageServiceError, .malformed)
                assertRedacted(error)
            }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    private func library() -> LibraryState {
        var state = LibraryState()
        state.preferences.userID = "42"
        state.account = AccountState()
        return state
    }
    @discardableResult private func ingestSequences(_ numbers: [Int64], maximum: Int64,
        into state: inout LibraryState, seconds: Double) throws -> [Activity] {
        let messages = numbers.map { number in
            DirectMessageMetadata(clientMessageID: "fixture-client-\(number)", serverMessageID: "fixture-server-\(number)",
                sessionType: 1, direction: .incoming, sentAt: now.addingTimeInterval(Double(number)),
                contentType: 101, sequence: number)
        }
        let conversation = DirectMessageConversation(conversationID: "fixture-conversation", unreadCount: Int(maximum),
            receiveOption: .normal, latestMessage: messages.last, messages: messages,
            maximumSequence: maximum, readSequence: 0)
        let batch = try DirectMessageBatch(conversations: [conversation], conversationTotal: 1, unreadTotal: Int(maximum))
        var metadata = state.account?.directMessages
        let alerts = try DirectMessageAnalytics.ingest(batch, profileID: "42", metadata: &metadata,
            into: &state, at: now.addingTimeInterval(seconds))
        state.account?.directMessages = metadata
        return alerts
    }

    func testStaleCreatorCommitCannotEraseNewerDMBaselineOrRowsAndReplayAlerts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MakerGlanceIndependentDM-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fictional.sqlite")
        let store = try Storage(url: url)
        let initial = library()
        try await store.commit(initial)
        var staleCreator = initial
        let report = CreatorReport(scope: .models, period: CreatorPeriod(days: 1, now: now),
            fetchedAt: now.addingTimeInterval(10), rows: [])
        staleCreator.creatorReport = report
        var direct = initial
        XCTAssertTrue(try ingestSequences([1], maximum: 1, into: &direct, seconds: 1).isEmpty)
        XCTAssertEqual(try ingestSequences([2], maximum: 2, into: &direct, seconds: 2).count, 1)
        direct.activity[0].isRead = true
        try await store.commit(direct)
        // This is the SQLite commit ordering when Creator's pre-DM snapshot
        // resumes after a completed direct-message observation.
        try await store.commit(staleCreator)
        let reopened = try Storage(url: url)
        var restored = try await reopened.load()
        XCTAssertEqual(restored.creatorReport, report)
        XCTAssertEqual(restored.account?.directMessages, direct.account?.directMessages)
        XCTAssertEqual(restored.activity, direct.activity)
        XCTAssertTrue(try ingestSequences([2], maximum: 2, into: &restored, seconds: 3).isEmpty)
        XCTAssertEqual(restored.activity, direct.activity)
    }

    func testLocalControlsPreserveNewDMMetadataAlongsideReadDismissedAndFreshOtherData() throws {
        var current = library()
        _ = try ingestSequences([1], maximum: 1, into: &current, seconds: 1)
        var stale = current
        let firstID = try XCTUnwrap(current.activity.first?.id)
        let alerts = try ingestSequences([2], maximum: 2, into: &current, seconds: 2)
        let dismissedID = try XCTUnwrap(alerts.first?.id)
        for index in current.activity.indices where current.activity[index].id == firstID { current.activity[index].isRead = true }
        current.dismissedActivityIDs = [dismissedID]
        current.activity.removeAll { $0.id == dismissedID }
        current.account?.preferences.directMessageNotifications = false
        let freshOther = Activity(id: "remote:independent-fixture", date: now.addingTimeInterval(4),
            title: "Fictional model update", detail: "Independent synthetic fixture", symbol: "cube")
        stale.activity.append(freshOther)
        XCTAssertTrue(LocalControls.preserve(from: current, in: &stale))
        XCTAssertEqual(stale.account?.directMessages, current.account?.directMessages)
        XCTAssertFalse(stale.account!.preferences.allowsDirectMessageAlerts)
        XCTAssertTrue(stale.activity.first { $0.id == firstID }?.isRead == true)
        XCTAssertNil(stale.activity.first { $0.id == dismissedID })
        XCTAssertTrue(stale.dismissedActivityIDs?.contains(dismissedID) == true)
        XCTAssertEqual(stale.activity.first { $0.id == freshOther.id }, freshOther)
        XCTAssertTrue(try ingestSequences([2], maximum: 2, into: &stale, seconds: 3).isEmpty)
        XCTAssertNil(stale.activity.first { $0.id == dismissedID })
    }

    func testConflictingPersistedAliasRejectsWholeCommitWithoutReplacingSavedHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MakerGlanceIndependentDMConflict-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try Storage(url: directory.appendingPathComponent("fictional.sqlite"))
        var original = library()
        _ = try ingestSequences([1], maximum: 1, into: &original, seconds: 1)
        try await store.commit(original)
        let alias = try XCTUnwrap(original.account?.directMessages?.aliases.keys.first)
        var conflicting = original
        conflicting.account?.directMessages?.aliases[alias] = "direct:conflicting-fictional-identity"
        conflicting.account?.directMessages?.lastSync = now.addingTimeInterval(20)
        conflicting.creatorReport = CreatorReport(scope: .models, period: CreatorPeriod(days: 1, now: now),
            fetchedAt: now.addingTimeInterval(20), rows: [])
        do {
            try await store.commit(conflicting)
            XCTFail("A conflicting alias must reject the entire observation commit")
        } catch {}
        let restored = try await store.load()
        XCTAssertEqual(restored.account?.directMessages, original.account?.directMessages)
        XCTAssertEqual(restored.activity, original.activity)
        XCTAssertNil(restored.creatorReport)
    }
}
