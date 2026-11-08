import XCTest
@testable import MakerPulseCore

final class DirectMessageParserTests: XCTestCase {
    private let milliseconds: Int64 = 1_800_000_000_123
    private func message(_ changes: [String: Any] = [:], removing: [String] = []) -> [String: Any] {
        var value: [String: Any] = ["clientMsgID": "client-1", "serverMsgID": "server-1", "sessionType": 1,
            "sendID": "peer", "recvID": "self", "LatestMsgRecvTime": milliseconds, "contentType": 101]
        value.merge(changes) { _, new in new }
        for key in removing { value.removeValue(forKey: key) }
        return value
    }
    private func conversation(_ changes: [String: Any] = [:], removing: [String] = []) -> [String: Any] {
        var value: [String: Any] = ["conversationID": "si_peer_self", "recvMsgOpt": 0, "unreadCount": 2, "IsPinned": false, "msgInfo": message()]
        value.merge(changes) { _, new in new }
        for key in removing { value.removeValue(forKey: key) }
        return value
    }
    private func envelope(rows: [[String: Any]]? = nil, total: Any = 1, unread: Any = 2) -> [String: Any] {
        ["errCode": 0, "data": ["conversationTotal": total, "unreadTotal": unread, "conversationElems": rows ?? [conversation()]]]
    }
    private func parse(_ object: Any, currentUserID: String = "self") throws -> DirectMessagePage {
        try DirectMessageParser.page(JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]), currentUserID: currentUserID)
    }

    func testParsesExactUpstreamMetadataAndMilliseconds() throws {
        let page = try parse(envelope())
        XCTAssertEqual(page.conversationTotal, 1); XCTAssertEqual(page.unreadTotal, 2)
        let row = try XCTUnwrap(page.conversations.first), metadata = try XCTUnwrap(row.latestMessage)
        XCTAssertEqual(row.conversationID, "si_peer_self"); XCTAssertEqual(row.unreadCount, 2)
        XCTAssertEqual(row.receiveOption, .normal)
        XCTAssertEqual(metadata.clientMessageID, "client-1"); XCTAssertEqual(metadata.serverMessageID, "server-1")
        XCTAssertEqual(metadata.identityKeys, ["client:client-1", "server:server-1"])
        XCTAssertEqual(metadata.sentAt.timeIntervalSince1970, 1_800_000_000.123, accuracy: 0.0001)
        XCTAssertEqual(metadata.contentType, 101); XCTAssertTrue(metadata.isIncomingDirectMessage)
    }

    func testDirectionAndSingleSessionFilteringDoNotRetainParticipants() throws {
        for (fields, expected, incoming) in [
            (["sendID": "self", "recvID": "peer"] as [String: Any], DirectMessageDirection.outgoing, false),
            (["sendID": "someone", "recvID": "else"], .other, false),
            (["sessionType": 2], .incoming, false),
            (["sessionType": 3], .incoming, false),
            (["sessionType": 4], .incoming, false)
        ] {
            let metadata = try XCTUnwrap(parse(envelope(rows: [conversation(["msgInfo": message(fields)])])).conversations.first?.latestMessage)
            XCTAssertEqual(metadata.direction, expected); XCTAssertEqual(metadata.isIncomingDirectMessage, incoming)
        }
    }

    func testMissingOrNullMessageIsValidWithoutCreatingMessageIdentity() throws {
        for row in [conversation(removing: ["msgInfo"]), conversation(["msgInfo": NSNull()])] {
            let page = try parse(envelope(rows: [row]))
            XCTAssertNil(page.conversations.first?.latestMessage)
        }
    }

    func testStableMessageIdentityRequiresAtLeastOneSuppliedID() throws {
        for (field, expected) in [("clientMsgID", "server:server-1"), ("serverMsgID", "client:client-1")] {
            let metadata = try XCTUnwrap(parse(envelope(rows: [conversation(["msgInfo": message(removing: [field])])])).conversations.first?.latestMessage)
            XCTAssertEqual(metadata.identityKeys, [expected])
        }
        XCTAssertThrowsError(try parse(envelope(rows: [conversation(["msgInfo": message(removing: ["clientMsgID", "serverMsgID"])])])))
        XCTAssertThrowsError(try parse(envelope(rows: [conversation(["msgInfo": message(["clientMsgID": "", "serverMsgID": ""])])])))
        XCTAssertThrowsError(try parse(envelope(rows: [conversation(["msgInfo": message(["clientMsgID": " bad "])])])))
        XCTAssertThrowsError(try parse(envelope(rows: [conversation(["msgInfo": message(["clientMsgID": 42])])])))
    }

    func testSuccessfulEmptyAndPaginatedResponses() throws {
        let empty = try parse(envelope(rows: [], total: 0, unread: 0))
        XCTAssertEqual(empty, DirectMessagePage(conversationTotal: 0, unreadTotal: 0, conversations: []))
        let partial = try parse(envelope(total: 50, unread: 100))
        XCTAssertEqual(partial.conversationTotal, 50); XCTAssertEqual(partial.conversations.count, 1)
        XCTAssertNoThrow(try parse(envelope(rows: [], total: 50, unread: 100)))
    }

    func testRejectsErrorAndUnknownEnvelopeShapes() {
        for object: Any in [[:], [], ["hits": []], ["errCode": 0], ["errCode": 0, "data": NSNull()],
            ["errCode": 0, "data": ["conversationTotal": 0, "unreadTotal": 0]],
            ["errCode": 1004, "errMsg": "private error"],
            ["errCode": true, "data": [:]], ["errCode": "0", "data": [:]]] {
            XCTAssertThrowsError(try parse(object))
        }
        var failed = envelope(); failed["errCode"] = 1004
        XCTAssertThrowsError(try parse(failed))
    }

    func testRejectsMalformedCountsAndInconsistentTotals() {
        for count: Any in [-1, true, "1", 1.25, NSNull(), Int64(Int32.max) + 1] {
            XCTAssertThrowsError(try parse(envelope(total: count)))
            XCTAssertThrowsError(try parse(envelope(unread: count)))
            XCTAssertThrowsError(try parse(envelope(rows: [conversation(["unreadCount": count])], unread: 100)))
        }
        XCTAssertThrowsError(try parse(envelope(total: 0)))
        XCTAssertThrowsError(try parse(envelope(unread: 1)))
        XCTAssertThrowsError(try parse(envelope(rows: [], total: 0, unread: 1)))
        XCTAssertThrowsError(try parse(envelope(rows: [conversation(), conversation(["conversationID": "other"])], total: 2, unread: 3)))
    }

    func testRejectsIncompleteOrDuplicatedConversationRows() {
        for key in ["conversationID", "recvMsgOpt", "unreadCount"] {
            XCTAssertThrowsError(try parse(envelope(rows: [conversation(removing: [key])])))
        }
        for id in ["", " space", "has\nnewline", String(repeating: "x", count: 513)] {
            XCTAssertThrowsError(try parse(envelope(rows: [conversation(["conversationID": id])])))
        }
        XCTAssertThrowsError(try parse(envelope(rows: [conversation(), conversation()], total: 2, unread: 4)))
        for option: Any in [-1, 3, true, "0"] {
            XCTAssertThrowsError(try parse(envelope(rows: [conversation(["recvMsgOpt": option])])))
        }
    }

    func testRejectsPartialMessageAndIncorrectTimestampFields() {
        for key in ["sessionType", "sendID", "recvID", "LatestMsgRecvTime", "contentType"] {
            XCTAssertThrowsError(try parse(envelope(rows: [conversation(["msgInfo": message(removing: [key])])])))
        }
        let badMessages: [[String: Any]] = [[:], message(["latestMsgRecvTime": milliseconds], removing: ["LatestMsgRecvTime"]),
            message(["LatestMsgRecvTime": 1_800_000_000]), message(["LatestMsgRecvTime": 0]),
            message(["LatestMsgRecvTime": -1]), message(["LatestMsgRecvTime": "1800000000123"]),
            message(["LatestMsgRecvTime": 1_800_000_000_123.5]), message(["LatestMsgRecvTime": 253_402_300_800_000 as Int64]),
            message(["sessionType": 0]), message(["sessionType": 5]), message(["sessionType": true]),
            message(["contentType": 0]), message(["contentType": -1]), message(["contentType": "101"]),
            message(["sendID": ""]), message(["recvID": "\n"])]
        for fields in badMessages { XCTAssertThrowsError(try parse(envelope(rows: [conversation(["msgInfo": fields])]))) }
        XCTAssertThrowsError(try parse(envelope(rows: [conversation(["msgInfo": []])])))
    }

    func testRetainsMutedOptionsAndNonTextTypesAsMetadata() throws {
        for option in [DirectMessageReceiveOption.notReceive, .notNotify] {
            let page = try parse(envelope(rows: [conversation(["recvMsgOpt": option.rawValue, "msgInfo": message(["contentType": 105])])]))
            XCTAssertEqual(page.conversations.first?.receiveOption, option)
            XCTAssertEqual(page.conversations.first?.latestMessage?.contentType, 105)
        }
    }

    func testPrivateValuesAreDiscardedFromMetadataAndSerialization() throws {
        let secret = "SYNTHETIC-PRIVATE-VALUE"
        var value = message(["senderName": secret, "faceURL": secret, "content": secret, "ex": secret,
            "textElem": ["content": secret], "fileElem": ["fileName": secret, "sourceURL": secret], "token": secret])
        value["sendID"] = "synthetic-participant"
        var payload = envelope(rows: [conversation(["msgInfo": value, "showName": secret, "latestMsg": secret])])
        payload["token"] = secret; payload["errMsg"] = secret
        let page = try parse(payload)
        let serialized = try JSONEncoder().encode(page.conversations)
        let text = try XCTUnwrap(String(data: serialized, encoding: .utf8))
        for prohibited in [secret, "synthetic-participant", "senderName", "faceURL", "content\"", "fileElem", "token", "sendID", "recvID"] {
            XCTAssertFalse(text.contains(prohibited), "Private field retained: \(prohibited)")
        }
        XCTAssertEqual(try JSONDecoder().decode([DirectMessageConversation].self, from: serialized), page.conversations)
    }

    func testMalformedErrorsNeverIncludeResponseValues() throws {
        let secret = "SYNTHETIC-PRIVATE-VALUE"
        let data = try JSONSerialization.data(withJSONObject: ["errCode": secret, "token": secret])
        XCTAssertThrowsError(try DirectMessageParser.page(data, currentUserID: "self")) { error in
            XCTAssertFalse(String(describing: error).contains(secret))
            XCTAssertFalse(error.localizedDescription.contains(secret))
        }
        for id in ["", "bad id", "bad\n", String(repeating: "x", count: 513)] {
            XCTAssertThrowsError(try parse(envelope(), currentUserID: id))
        }
    }
}
