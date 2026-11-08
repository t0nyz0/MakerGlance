import Foundation
import XCTest
@testable import MakerPulseCore

private actor DirectMessageTransport: HTTPTransport {
    enum Step: Sendable { case response(HTTPResult), fail, cancel(HTTPResult) }
    private var steps: [Step]
    var requests: [URLRequest] = []
    init(_ responses: [HTTPResult]) { steps = responses.map(Step.response) }
    init(steps: [Step]) { self.steps = steps }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        guard !steps.isEmpty else { throw URLError(.cannotConnectToHost) }
        switch steps.removeFirst() {
        case .response(let result): return result
        case .fail:
            throw NSError(domain: "SYNTHETIC-PRIVATE-RESPONSE", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "SYNTHETIC-PRIVATE-RESPONSE"])
        case .cancel(let result):
            withUnsafeCurrentTask { $0?.cancel() }
            return result
        }
    }
}

final class DirectMessageServiceTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private func json(_ object: Any, status: Int = 200) -> HTTPResult {
        HTTPResult(data: try! JSONSerialization.data(withJSONObject: object), status: status)
    }
    private func profile(_ id: String = "42") -> HTTPResult { json(["uid": id, "handle": "fixture", "fanCount": 0]) }
    private func grant(_ seconds: Any = 3_600) -> HTTPResult {
        json(["userId": "self", "token": "chat-test-session", "expireIn": seconds])
    }
    private func session(profileID: String = "42", expiry: Double = 3_600) -> DirectMessageCredential {
        DirectMessageCredential(profileID: profileID, userID: "self", token: "chat-test-session", expiresAt: date.addingTimeInterval(expiry))
    }
    private func conversation(_ id: String = "direct-a", kind: Int = 1, minimum: Int64 = 0, maximum: Int64 = 0) -> [String: Any] {
        ["ownerUserID": "self", "conversationID": id, "recvMsgOpt": 0, "conversationType": kind,
            "userID": kind == 1 ? "peer" : "", "groupID": kind == 1 ? "" : "fixture-group", "minSeq": minimum, "maxSeq": maximum]
    }
    private func conversations(_ rows: [[String: Any]]? = nil) -> HTTPResult {
        json(["errCode": 0, "data": ["conversations": rows ?? [conversation()]]])
    }
    private func sequences(maximum: Int64, read: Int64, id: String = "direct-a") -> HTTPResult {
        json(["errCode": 0, "data": ["seqs": [id: ["maxSeq": maximum, "hasReadSeq": read]]]])
    }
    private func message(_ sequence: Int64, incoming: Bool = true) -> [String: Any] {
        ["sendID": incoming ? "peer" : "self", "recvID": incoming ? "self" : "peer",
            "clientMsgID": "client-\(sequence)", "serverMsgID": "server-\(sequence)", "sessionType": 1,
            "contentType": 101, "seq": sequence, "sendTime": Int64(date.timeIntervalSince1970 * 1_000) + sequence,
            "createTime": Int64(date.timeIntervalSince1970 * 1_000) + sequence, "status": 1,
            "content": "SYNTHETIC-PRIVATE-MESSAGE", "senderNickname": "SYNTHETIC-PRIVATE-NAME"]
    }
    private func pull(_ messages: [[String: Any]], id: String = "direct-a", isEnd: Bool = true) -> HTTPResult {
        json(["errCode": 0, "data": ["msgs": [id: ["Msgs": messages, "isEnd": isEnd]], "notificationMsgs": NSNull()]])
    }
    private func known(maximum: Int64) throws -> DirectMessageState? {
        var state = LibraryState(); state.preferences.userID = "42"
        var known: DirectMessageState?
        let row = DirectMessageConversation(conversationID: "direct-a", unreadCount: 0, receiveOption: .normal,
            latestMessage: nil, messages: [], maximumSequence: maximum, readSequence: maximum)
        let batch = try DirectMessageBatch(conversations: [row], conversationTotal: 1, unreadTotal: 0)
        _ = try DirectMessageAnalytics.ingest(batch, profileID: "42", metadata: &known, into: &state, at: date)
        return known
    }
    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    func testExplicitAuthorizationValidatesProfileBeforeSingleNativeTokenGrant() async throws {
        let transport = DirectMessageTransport([profile(), grant()])
        let service = DirectMessageService(transport: transport, minimumInterval: 0)
        let credential = try await service.authorize(bambuToken: "bambu-test-session", profileID: "42", at: date)
        XCTAssertEqual(credential.profileID, "42"); XCTAssertEqual(credential.userID, "self")
        XCTAssertEqual(credential.expiresAt, date.addingTimeInterval(3_600))
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url!.path }, ["/v1/design-user-service/my/profile", "/v1/design-user-service/my/im/token"])
        XCTAssertEqual(requests[1].url?.query, "platformId=4")
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer bambu-test-session" })
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "token") == nil })
        XCTAssertFalse(String(describing: credential).contains("chat-test-session"))
        XCTAssertFalse(String(reflecting: credential).contains("chat-test-session"))
    }
    func testWrongProfileNeverCreatesChatCredential() async {
        let transport = DirectMessageTransport([profile("43"), grant()])
        let service = DirectMessageService(transport: transport, minimumInterval: 0)
        do { _ = try await service.authorize(bambuToken: "bambu-test-session", profileID: "42", at: date); XCTFail("Mismatched account must fail") }
        catch { XCTAssertEqual(error as? DirectMessageServiceError, .accountMismatch) }
        let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
    }
    func testCredentialGrantFailureIsNeverAutomaticallyRetried() async {
        let transport = DirectMessageTransport([profile(), HTTPResult(data: Data(), status: 503), grant()])
        let service = DirectMessageService(transport: transport, minimumInterval: 0)
        do { _ = try await service.authorize(bambuToken: "bambu-test-session", profileID: "42", at: date); XCTFail("Failed grant must fail") }
        catch { XCTAssertEqual(error as? DirectMessageServiceError, .unavailable(503)) }
        let requests = await transport.requests; XCTAssertEqual(requests.count, 2)
    }
    func testMalformedExpiryOrTokenCannotBecomeSavedCredential() async {
        for seconds: Any in [0, -1, 366 * 86_400 + 1, "3600", true] {
            let transport = DirectMessageTransport([profile(), grant(seconds)])
            let service = DirectMessageService(transport: transport, minimumInterval: 0)
            do { _ = try await service.authorize(bambuToken: "bambu-test-session", profileID: "42", at: date); XCTFail("Invalid expiry must fail") }
            catch { XCTAssertEqual(error as? DirectMessageServiceError, .malformed) }
        }
    }
    func testExpiredPollingDoesNotFetchOrMintAnything() async {
        let transport = DirectMessageTransport([])
        let service = DirectMessageService(transport: transport, minimumInterval: 0)
        do { _ = try await service.snapshot(session: session(expiry: 0), known: nil, at: date); XCTFail("Expired credential must require explicit reconnect") }
        catch { XCTAssertEqual(error as? DirectMessageServiceError, .authentication) }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testPollingScopeIsCheckedEvenWithEmptyConversationList() async throws {
        let transport = DirectMessageTransport([conversations([])])
        let service = DirectMessageService(transport: transport, minimumInterval: 0)
        do { _ = try await service.snapshot(session: session(profileID: "43"), known: known(maximum: 1), at: date); XCTFail("Different profiles cannot share baseline") }
        catch { XCTAssertEqual(error as? DirectMessageServiceError, .accountMismatch) }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testInitialSnapshotPullsOnlyUnreadRangeAndNeverMarksRead() async throws {
        let transport = DirectMessageTransport([conversations(), sequences(maximum: 5, read: 3), pull([message(4), message(5, incoming: false)])])
        let service = DirectMessageService(transport: transport, minimumInterval: 0)
        let batch = try await service.snapshot(session: session(), known: nil, at: date)
        XCTAssertEqual(batch.conversationTotal, 1); XCTAssertEqual(batch.unreadTotal, 2)
        XCTAssertEqual(batch.conversations[0].maximumSequence, 5); XCTAssertEqual(batch.conversations[0].readSequence, 3)
        XCTAssertEqual(batch.conversations[0].messages?.map(\.sequence), [4, 5])
        XCTAssertEqual(batch.conversations[0].messages?.map(\.direction), [.incoming, .outgoing])
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url!.path }, ["/v1/im-service/api/conversation/get_all_conversations", "/v1/im-service/api/msg/get_conversations_has_read_and_max_seq", "/v1/im-service/api/msg/pull_msg_by_seq"])
        for request in requests {
            XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.host, "api.bambulab.com"); XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "token"), "chat-test-session")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "operationID"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        }
        let requestBody = try body(requests[2])
        let range = try XCTUnwrap((requestBody["seqRanges"] as? [[String: Any]])?.first)
        XCTAssertEqual(range["begin"] as? Int, 4); XCTAssertEqual(range["end"] as? Int, 5); XCTAssertEqual(range["num"] as? Int, 2)
        let encoded = try JSONEncoder().encode(batch.conversations)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("SYNTHETIC-PRIVATE"))
    }
    func testReadFenceAboveMaximumProducesNoFalseUnreadOrHistoryPull() async throws {
        let transport = DirectMessageTransport([conversations(), sequences(maximum: 5, read: 10)])
        let batch = try await DirectMessageService(transport: transport, minimumInterval: 0).snapshot(session: session(), known: nil, at: date)
        XCTAssertEqual(batch.unreadTotal, 0); XCTAssertEqual(batch.conversations[0].messages, [])
        let requests = await transport.requests; XCTAssertEqual(requests.count, 2)
    }
    func testKnownSequenceFetchesNewMessagesEvenIfOtherClientAlreadyReadThem() async throws {
        let transport = DirectMessageTransport([conversations(), sequences(maximum: 8, read: 8), pull([message(6), message(7), message(8)])])
        let metadata = try known(maximum: 5), before = metadata
        let batch = try await DirectMessageService(transport: transport, minimumInterval: 0).snapshot(session: session(), known: metadata, at: date)
        XCTAssertEqual(metadata, before); XCTAssertEqual(batch.unreadTotal, 0)
        XCTAssertEqual(batch.conversations[0].messages?.count, 3)
        let requests = await transport.requests, requestBody = try body(requests[2])
        XCTAssertEqual(((requestBody["seqRanges"] as? [[String: Any]])?.first)?["begin"] as? Int, 6)
    }
    func testMaximumRegressionDoesNotReplayOldMessages() async throws {
        let transport = DirectMessageTransport([conversations(), sequences(maximum: 3, read: 0)])
        let batch = try await DirectMessageService(transport: transport, minimumInterval: 0).snapshot(session: session(), known: known(maximum: 5), at: date)
        XCTAssertEqual(batch.conversations[0].messages, [])
        let requests = await transport.requests; XCTAssertEqual(requests.count, 2)
    }
    func testExplicitChunksCoverEachRangeWithoutDependingOnLiveIsEnd() async throws {
        let transport = DirectMessageTransport([conversations(), sequences(maximum: 205, read: 0), pull([], isEnd: false), pull([], isEnd: false), pull([])])
        _ = try await DirectMessageService(transport: transport, minimumInterval: 0).snapshot(session: session(), known: nil, at: date)
        let requests = await transport.requests
        let ranges = try requests.dropFirst(2).map { request -> [String: Any] in try XCTUnwrap((body(request)["seqRanges"] as? [[String: Any]])?.first) }
        XCTAssertEqual(ranges.compactMap { $0["begin"] as? Int }, [1, 101, 201])
        XCTAssertEqual(ranges.compactMap { $0["end"] as? Int }, [100, 200, 205])
        XCTAssertEqual(ranges.compactMap { $0["num"] as? Int }, [100, 100, 5])
    }
    func testPerUserMinimumAndMaximumLimitVisibleHistory() async throws {
        let transport = DirectMessageTransport([conversations([conversation(minimum: 3, maximum: 4)]), sequences(maximum: 10, read: 0), pull([message(3), message(4)])])
        let batch = try await DirectMessageService(transport: transport, minimumInterval: 0).snapshot(session: session(), known: nil, at: date)
        XCTAssertEqual(batch.conversations[0].maximumSequence, 10, "Consume global watermark without exposing user-hidden history")
        let requests = await transport.requests
        let range = try XCTUnwrap((body(requests[2])["seqRanges"] as? [[String: Any]])?.first)
        XCTAssertEqual(range["begin"] as? Int, 3); XCTAssertEqual(range["end"] as? Int, 4)
    }
    func testRefreshBudgetRejectsHugeUnreadRangeBeforeHistoryRequests() async {
        let transport = DirectMessageTransport([conversations(), sequences(maximum: 5_001, read: 0)])
        do { _ = try await DirectMessageService(transport: transport, minimumInterval: 0).snapshot(session: session(), known: nil, at: date); XCTFail("Unbounded range must fail") }
        catch { XCTAssertEqual(error as? DirectMessageServiceError, .incomplete) }
        let requests = await transport.requests; XCTAssertEqual(requests.count, 2)
    }
    func testHighestSequenceBoundaryDoesNotOverflow() async throws {
        let transport = DirectMessageTransport([conversations(), sequences(maximum: Int64.max, read: Int64.max - 1), pull([])])
        _ = try await DirectMessageService(transport: transport, minimumInterval: 0).snapshot(session: session(), known: known(maximum: Int64.max - 1), at: date)
        let requests = await transport.requests
        let range = try XCTUnwrap((body(requests[2])["seqRanges"] as? [[String: Any]])?.first)
        XCTAssertEqual(range["begin"] as? Int, Int.max); XCTAssertEqual(range["end"] as? Int, Int.max)
        XCTAssertEqual(range["num"] as? Int, 1)
    }
    func testEmptyConversationListCompletesWithoutInventingSequenceRequest() async throws {
        let transport = DirectMessageTransport([conversations([])])
        let batch = try await DirectMessageService(transport: transport, minimumInterval: 0).snapshot(session: session(), known: nil, at: date)
        XCTAssertEqual(batch.conversationTotal, 0)
        let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
    }
    func testGroupConversationsNeverPullMessageHistory() async throws {
        let transport = DirectMessageTransport([conversations([conversation("group", kind: 2)]), sequences(maximum: 10, read: 0, id: "group")])
        let batch = try await DirectMessageService(transport: transport, minimumInterval: 0).snapshot(session: session(), known: nil, at: date)
        XCTAssertEqual(batch.conversationTotal, 0)
        let requests = await transport.requests; XCTAssertEqual(requests.count, 2)
    }
    func testMissingConversationInSuccessfulPullIsNotComplete() async throws {
        let transport = DirectMessageTransport([conversations(), sequences(maximum: 1, read: 0), json(["errCode": 0, "data": ["msgs": [:]]])])
        do { _ = try await DirectMessageService(transport: transport, minimumInterval: 0).snapshot(session: session(), known: nil, at: date); XCTFail("Skipped RPC lookup cannot establish baseline") }
        catch { XCTAssertNotNil(error as? DirectMessageServiceError) }
    }
    func testNetworkErrorNeverLeaksPrivateDescriptionsOrRetriesAuth() async {
        let transport = DirectMessageTransport(steps: [.fail])
        do { _ = try await DirectMessageService(transport: transport, minimumInterval: 0).snapshot(session: session(), known: nil, at: date); XCTFail("Network failure must propagate") }
        catch {
            XCTAssertEqual(error as? DirectMessageServiceError, .network)
            XCTAssertFalse(error.localizedDescription.contains("SYNTHETIC-PRIVATE"))
        }
        let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
    }
    func testPollingAuthenticationAndThrottleFailuresDoNotMintOrRetry() async {
        for status in [401, 403, 429] {
            let transport = DirectMessageTransport([HTTPResult(data: Data(), status: status, headers: ["retry-after": "0"])])
            do { _ = try await DirectMessageService(transport: transport, minimumInterval: 0).snapshot(session: session(), known: nil, at: date); XCTFail("Denied polling must fail") }
            catch {
                XCTAssertEqual(error as? DirectMessageServiceError, status == 429 ? .unavailable(429) : .authentication)
            }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1); XCTAssertTrue(requests.allSatisfy { $0.url?.path.hasPrefix("/v1/im-service/api/") == true })
        }
    }
    func testCancellationAfterResponseCannotProduceBaseline() async {
        let response = conversations([])
        let transport = DirectMessageTransport(steps: [.cancel(response)])
        let service = DirectMessageService(transport: transport, minimumInterval: 0), credential = session(), currentDate = date
        let task = Task { try await service.snapshot(session: credential, known: nil, at: currentDate) }
        do { _ = try await task.value; XCTFail("Cancelled response cannot establish baseline") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
