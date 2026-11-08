import XCTest
@testable import MakerPulseCore

final class DirectMessageServiceParserTests: XCTestCase {
    private let time: Int64 = 1_800_000_000_123
    private func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) }
    private func envelope(_ payload: Any, code: Any = 0) -> [String: Any] { ["errCode": code, "data": payload] }
    private func row(_ changes: [String: Any] = [:], removing: [String] = []) -> [String: Any] {
        var row: [String: Any] = ["ownerUserID": "self", "conversationID": "single", "conversationType": 1,
            "userID": "peer", "recvMsgOpt": 0, "minSeq": 0, "maxSeq": 0]
        row.merge(changes) { _, new in new }; for key in removing { row.removeValue(forKey: key) }; return row
    }
    private func message(_ changes: [String: Any] = [:], removing: [String] = []) -> [String: Any] {
        var row: [String: Any] = ["sendID": "peer", "recvID": "self", "clientMsgID": "client", "serverMsgID": "server",
            "sessionType": 1, "contentType": 101, "sendTime": time, "createTime": time, "seq": 10, "status": 1]
        row.merge(changes) { _, new in new }; for key in removing { row.removeValue(forKey: key) }; return row
    }
    private func pull(_ messages: Any, isEnd: Any = true, conversationID: String = "single") -> [String: Any] {
        envelope(["msgs": [conversationID: ["Msgs": messages, "isEnd": isEnd]], "notificationMsgs": NSNull()])
    }
    private func parseMessages(_ object: Any, begin: Int64 = 1, end: Int64 = 20, userID: String = "self", peerID: String = "peer") throws -> DirectMessagePull {
        try DirectMessageServiceParser.messages(data(object), conversationID: "single", userID: userID, peerID: peerID, begin: begin, end: end)
    }

    func testVerifiedConversationFieldsAndGroupMetadata() throws {
        let rows = [row(), row(["conversationID": "group", "conversationType": 2, "userID": "", "recvMsgOpt": 2, "minSeq": 5]),
            row(["conversationID": "work", "conversationType": 3]), row(["conversationID": "notice", "conversationType": 4])]
        let parsed = try DirectMessageServiceParser.conversations(data(envelope(["conversations": rows])), userID: "self")
        XCTAssertEqual(parsed[0], DirectMessageRemoteConversation(id: "single", peerID: "peer", kind: 1,
            receiveOption: .normal, minimumSequence: 0, maximumSequence: 0))
        XCTAssertEqual(parsed[1].kind, 2); XCTAssertEqual(parsed[1].peerID, ""); XCTAssertEqual(parsed[1].receiveOption, .notNotify)
        XCTAssertEqual(parsed[1].minimumSequence, 5); XCTAssertEqual(parsed[1].maximumSequence, 0)
        XCTAssertEqual(parsed.map(\.kind), [1, 2, 3, 4])
    }

    func testConversationOwnershipIdentityAndRequiredFieldsAreStrict() throws {
        for key in ["ownerUserID", "conversationID", "conversationType", "userID", "recvMsgOpt", "minSeq", "maxSeq"] {
            XCTAssertThrowsError(try DirectMessageServiceParser.conversations(data(envelope(["conversations": [row(removing: [key])]])), userID: "self"))
        }
        for changes: [String: Any] in [["ownerUserID": "other"], ["conversationID": ""], ["userID": ""],
            ["conversationType": 0], ["conversationType": 5], ["recvMsgOpt": 3], ["minSeq": -1], ["maxSeq": -1],
            ["minSeq": "0"], ["maxSeq": true], ["minSeq": 1.5], ["userID": "bad\n"]] {
            XCTAssertThrowsError(try DirectMessageServiceParser.conversations(data(envelope(["conversations": [row(changes)]])), userID: "self"))
        }
        XCTAssertThrowsError(try DirectMessageServiceParser.conversations(data(envelope(["conversations": [row(), row()]])), userID: "self"))
        XCTAssertThrowsError(try DirectMessageServiceParser.conversations(data(envelope(["conversations": NSNull()])), userID: "self"))
        XCTAssertEqual(try DirectMessageServiceParser.conversations(data(envelope(["conversations": []])), userID: "self"), [])
    }

    func testSequencesPreserveExactInt64AndReadBeyondCurrentMaximum() throws {
        let large = Int64.max - 1
        let payload = envelope(["seqs": ["single": ["maxSeq": large, "hasReadSeq": Int64.max], "empty": ["maxSeq": 0, "hasReadSeq": 0]]])
        let parsed = try DirectMessageServiceParser.sequences(data(payload), conversationIDs: ["single", "empty"])
        XCTAssertEqual(parsed["single"], DirectMessageSequence(maximum: large, read: Int64.max))
        XCTAssertEqual(parsed["empty"], DirectMessageSequence(maximum: 0, read: 0))
        XCTAssertEqual(try DirectMessageServiceParser.sequences(data(envelope(["seqs": [:]])), conversationIDs: []), [:])
    }

    func testSequencesRejectMissingUnexpectedAndMalformedRows() throws {
        for payload: Any in [[:], ["seqs": NSNull()], ["seqs": []], ["seqs": [:]],
            ["seqs": ["single": ["maxSeq": 1]]], ["seqs": ["single": ["hasReadSeq": 1]]],
            ["seqs": ["single": ["maxSeq": 1, "hasReadSeq": 1], "unexpected": ["maxSeq": 1, "hasReadSeq": 1]]]] {
            XCTAssertThrowsError(try DirectMessageServiceParser.sequences(data(envelope(payload)), conversationIDs: ["single"]))
        }
        for bad: Any in [-1, true, "1", 1.5, NSNull()] {
            for key in ["maxSeq", "hasReadSeq"] {
                var seq: [String: Any] = ["maxSeq": 1, "hasReadSeq": 1]; seq[key] = bad
                XCTAssertThrowsError(try DirectMessageServiceParser.sequences(data(envelope(["seqs": ["single": seq]])), conversationIDs: ["single"]))
            }
        }
    }

    func testLivePullShapePreservesMessageIDsSequenceAndMilliseconds() throws {
        let result = try parseMessages(pull([message()]), begin: 10, end: 10)
        XCTAssertTrue(result.isEnd); XCTAssertEqual(result.messages.count, 1)
        let first = try XCTUnwrap(result.messages.first)
        XCTAssertEqual(first.clientMessageID, "client"); XCTAssertEqual(first.serverMessageID, "server")
        XCTAssertEqual(first.sequence, 10); XCTAssertEqual(first.direction, .incoming)
        XCTAssertEqual(first.contentType, 101); XCTAssertTrue(first.isIncomingDirectMessage)
        XCTAssertEqual(first.sentAt.timeIntervalSince1970, 1_800_000_000.123, accuracy: 0.0001)
    }

    func testDirectionsRequireBothVerifiedParticipants() throws {
        let cases: [([String: Any], DirectMessageDirection)] = [([:], .incoming),
            (["sendID": "self", "recvID": "peer"], .outgoing),
            (["sendID": "stranger", "recvID": "self"], .other),
            (["sendID": "peer", "recvID": "stranger"], .other),
            (["sendID": "self", "recvID": "stranger"], .other)]
        for (fields, expected) in cases {
            XCTAssertEqual(try parseMessages(pull([message(fields)])).messages.first?.direction, expected)
        }
    }

    func testNullAndEmptyMessagesAreValidButRequireConversationAndEndFlag() throws {
        for values: Any in [NSNull(), []] {
            XCTAssertEqual(try parseMessages(pull(values, isEnd: false)), DirectMessagePull(messages: [], isEnd: false))
        }
        for object: Any in [envelope(["msgs": NSNull()]), envelope(["msgs": [:]]), pull([], conversationID: "wrong"),
            envelope(["msgs": ["single": ["isEnd": true]]]), envelope(["msgs": ["single": ["msgs": [], "isEnd": true]]]),
            envelope(["msgs": ["single": ["Msgs": []]]]), pull([], isEnd: 1), pull([], isEnd: NSNull()), pull([:], isEnd: true)] {
            XCTAssertThrowsError(try parseMessages(object))
        }
    }

    func testDeletedTombstonesAndFilteredSequenceGapsDoNotCreateMessages() throws {
        let deleted: [String: Any] = ["seq": 10, "status": 4]
        let result = try parseMessages(pull([deleted, message(["seq": 15])]), begin: 1, end: 20)
        XCTAssertEqual(result.messages.map(\.sequence), [15])
        XCTAssertEqual(try parseMessages(pull([deleted])).messages, [])
        XCTAssertThrowsError(try parseMessages(pull([["status": 4]])))
        XCTAssertThrowsError(try parseMessages(pull([["seq": 21, "status": 4]])))
        XCTAssertThrowsError(try parseMessages(pull([deleted, deleted])))
    }

    func testMessagesRejectDuplicateOrOutOfRangeSequencesAndIdentities() throws {
        for values in [[message(), message()], [message(), message(["seq": 11])],
            [message(["seq": 0])], [message(["seq": 21])], [message(["seq": true])], [message(["seq": "10"])]] {
            XCTAssertThrowsError(try parseMessages(pull(values)))
        }
        let second = message(["seq": 11, "clientMsgID": "second", "serverMsgID": "second-server"])
        XCTAssertEqual(try parseMessages(pull([message(), second])).messages.count, 2)
    }

    func testMessagesRejectPartialMetadataUnknownStatusesAndWrongTimestampUnits() throws {
        for key in ["sendID", "recvID", "sessionType", "contentType", "sendTime", "seq", "status"] {
            XCTAssertThrowsError(try parseMessages(pull([message(removing: [key])])))
        }
        for fields: [String: Any] in [["status": 0], ["status": 2], ["status": 3], ["status": 5], ["status": "1"],
            ["sessionType": 2], ["contentType": 0], ["contentType": "101"], ["sendID": ""], ["recvID": "bad id"],
            ["sendTime": 0], ["sendTime": 1_800_000_000], ["sendTime": "1800000000123"],
            ["sendTime": 253_402_300_800_000 as Int64], ["clientMsgID": "", "serverMsgID": ""], ["clientMsgID": "bad\n"]] {
            XCTAssertThrowsError(try parseMessages(pull([message(fields)])))
        }
        XCTAssertThrowsError(try parseMessages(pull([message(removing: ["clientMsgID", "serverMsgID"])])))
        XCTAssertNoThrow(try parseMessages(pull([message(removing: ["clientMsgID"])])))
        XCTAssertNoThrow(try parseMessages(pull([message(removing: ["serverMsgID"])])))
    }

    func testAllParsersRejectBusinessErrorsAndUnknownEnvelopeShapes() throws {
        for object: Any in [[:], [], ["data": [:]], ["errCode": true, "data": [:]], ["errCode": "0", "data": [:]],
            ["errCode": 0], ["errCode": 1004], ["errCode": 0, "data": NSNull()]] {
            XCTAssertThrowsError(try DirectMessageServiceParser.conversations(data(object), userID: "self"))
            XCTAssertThrowsError(try DirectMessageServiceParser.sequences(data(object), conversationIDs: []))
            XCTAssertThrowsError(try parseMessages(object))
        }
        XCTAssertThrowsError(try DirectMessageServiceParser.conversations(data(envelope(["conversations": []], code: 1004)), userID: "self"))
        XCTAssertThrowsError(try DirectMessageServiceParser.sequences(data(envelope(["seqs": [:]], code: 1004)), conversationIDs: []))
        XCTAssertThrowsError(try parseMessages(envelope(["msgs": ["single": ["Msgs": [], "isEnd": true]]], code: 1004)))
    }

    func testMessageBodyNamesAndAttachmentsAreIgnoredEvenWithUnexpectedTypes() throws {
        let secret = "SYNTHETIC-PRIVATE-CONTENT"
        let fields: [String: Any] = ["content": ["arbitrary": secret], "senderNickname": secret, "senderFaceURL": secret,
            "offlinePushInfo": ["desc": secret], "options": secret, "attachedInfo": secret, "ex": secret, "token": secret]
        let result = try parseMessages(pull([message(fields)]))
        let text = String(decoding: try JSONEncoder().encode(result.messages), as: UTF8.self)
        for value in [secret, "senderNickname", "offlinePushInfo", "attachedInfo", "token", "sendID", "recvID"] {
            XCTAssertFalse(text.contains(value))
        }
        XCTAssertEqual(try JSONDecoder().decode([DirectMessageMetadata].self, from: JSONEncoder().encode(result.messages)), result.messages)
    }

    func testErrorsAreRedactedAndInvalidInputsFailClosed() throws {
        let secret = "SYNTHETIC-PRIVATE-CONTENT"
        let malformed = envelope(["msgs": ["single": ["Msgs": [["seq": secret, "status": 1]], "isEnd": true]]])
        XCTAssertThrowsError(try parseMessages(malformed)) { error in
            XCTAssertFalse(String(describing: error).contains(secret)); XCTAssertFalse(error.localizedDescription.contains(secret))
        }
        for (begin, end) in [(Int64(0), Int64(20)), (10, 9), (-1, 10)] {
            XCTAssertThrowsError(try parseMessages(pull([]), begin: begin, end: end))
        }
        XCTAssertThrowsError(try parseMessages(pull([]), userID: ""))
        XCTAssertThrowsError(try parseMessages(pull([]), peerID: "bad peer"))
    }
}
