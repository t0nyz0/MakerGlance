import Foundation

public struct DirectMessageRemoteConversation: Equatable, Sendable {
    public var id: String
    public var peerID: String
    public var kind: Int
    public var receiveOption: DirectMessageReceiveOption
    public var minimumSequence: Int64
    public var maximumSequence: Int64

    public init(id: String, peerID: String, kind: Int, receiveOption: DirectMessageReceiveOption,
        minimumSequence: Int64, maximumSequence: Int64) {
        self.id = id; self.peerID = peerID; self.kind = kind; self.receiveOption = receiveOption
        self.minimumSequence = minimumSequence; self.maximumSequence = maximumSequence
    }
}

public struct DirectMessageSequence: Equatable, Sendable {
    public var maximum: Int64
    public var read: Int64
    public init(maximum: Int64, read: Int64) { self.maximum = maximum; self.read = read }
}

public struct DirectMessagePull: Equatable, Sendable {
    public var messages: [DirectMessageMetadata]
    public var isEnd: Bool
    public init(messages: [DirectMessageMetadata], isEnd: Bool) { self.messages = messages; self.isEnd = isEnd }
}

/// Metadata-only decoding for MakerWorld's verified OpenIM REST response shapes.
/// The deployed WASM embeds openimsdk/protocol v0.0.14. Its generated JSON names
/// include capital `Msgs`; unrelated fields (including content) are not decoded.
public enum DirectMessageServiceParser {
    public static func conversations(_ data: Data, userID: String) throws -> [DirectMessageRemoteConversation] {
        try redacted {
            guard validID(userID) else { throw InvalidResponse.value }
            let response: WireConversations = try payload(data)
            var seen = Set<String>()
            return try response.conversations.map { row in
                guard row.ownerUserID == userID, validID(row.conversationID),
                    seen.insert(row.conversationID).inserted, (1...4).contains(row.conversationType),
                    let receiveOption = DirectMessageReceiveOption(rawValue: row.recvMsgOpt),
                    row.minSeq >= 0, row.maxSeq >= 0,
                    row.userID.isEmpty ? row.conversationType != 1 : validID(row.userID)
                else { throw InvalidResponse.value }
                // minSeq/maxSeq are conversation visibility fences. A zero max
                // is not an assertion that the conversation has no messages.
                return DirectMessageRemoteConversation(id: row.conversationID, peerID: row.userID,
                    kind: row.conversationType, receiveOption: receiveOption,
                    minimumSequence: row.minSeq, maximumSequence: row.maxSeq)
            }
        }
    }

    public static func sequences(_ data: Data, conversationIDs: Set<String>) throws -> [String: DirectMessageSequence] {
        try redacted {
            guard conversationIDs.allSatisfy(validID) else { throw InvalidResponse.value }
            let response: WireSequences = try payload(data)
            guard Set(response.seqs.keys) == conversationIDs else { throw InvalidResponse.value }
            return try response.seqs.mapValues { row in
                // A read watermark can exceed the current maximum after cloud
                // deletion/filtering. Preserve it; never turn it into unread.
                guard row.maxSeq >= 0, row.hasReadSeq >= 0 else { throw InvalidResponse.value }
                return DirectMessageSequence(maximum: row.maxSeq, read: row.hasReadSeq)
            }
        }
    }

    public static func messages(_ data: Data, conversationID: String, userID: String, peerID: String,
        begin: Int64, end: Int64) throws -> DirectMessagePull {
        try redacted {
            guard validID(conversationID), validID(userID), validID(peerID), begin > 0, end >= begin else { throw InvalidResponse.value }
            let response: WirePull = try payload(data)
            guard Set(response.msgs.keys) == [conversationID], let conversation = response.msgs[conversationID]
            else { throw InvalidResponse.value }
            var sequences = Set<Int64>(), clients = Set<String>(), servers = Set<String>()
            let messages = try conversation.messages.compactMap { row -> DirectMessageMetadata? in
                guard row.sequence >= begin, row.sequence <= end, sequences.insert(row.sequence).inserted else { throw InvalidResponse.value }
                // protocol v0.0.14 constant.go:117-120 identifies status 4 as a
                // deleted message. Tombstones do not need display metadata.
                guard let message = row.metadata else { return nil }
                let client = try messageID(message.clientMsgID), server = try messageID(message.serverMsgID)
                guard client != nil || server != nil, message.sessionType == 1,
                    validID(message.sendID), validID(message.recvID), message.contentType > 0, message.contentType <= Int32.max,
                    message.sendTime >= 946_684_800_000, message.sendTime <= 253_402_300_799_999,
                    client.map({ clients.insert($0).inserted }) ?? true,
                    server.map({ servers.insert($0).inserted }) ?? true else { throw InvalidResponse.value }
                let direction: DirectMessageDirection
                if message.sendID == userID && message.recvID == peerID { direction = .outgoing }
                else if message.recvID == userID && message.sendID == peerID { direction = .incoming }
                else { direction = .other }
                return DirectMessageMetadata(clientMessageID: client, serverMessageID: server,
                    sessionType: message.sessionType, direction: direction,
                    sentAt: Date(timeIntervalSince1970: Double(message.sendTime) / 1_000),
                    contentType: message.contentType, sequence: row.sequence)
            }
            // Deleted/filtered sequence gaps are valid. Do not fabricate a
            // message or reject the response merely because a seq is absent.
            return DirectMessagePull(messages: messages, isEnd: conversation.isEnd)
        }
    }

    private static func payload<T: Decodable>(_ data: Data) throws -> T {
        let code = try JSONDecoder().decode(WireCode.self, from: data).errCode
        // Both tools v0.0.5 (deployed WASM) and compatible server tools
        // v0.0.13 define 1501...1507 as expired/invalid/kicked token errors.
        // OpenIM returns these inside HTTP 200, without a valid data payload.
        if (1501...1507).contains(code) { throw DirectMessageServiceError.authentication }
        let envelope = try JSONDecoder().decode(WireEnvelope<T>.self, from: data)
        guard envelope.errCode == 0, let value = envelope.data else { throw InvalidResponse.value }
        return value
    }
    private static func redacted<T>(_ operation: () throws -> T) throws -> T {
        do { return try operation() }
        catch DirectMessageServiceError.authentication { throw DirectMessageServiceError.authentication }
        catch { throw PulseError.malformed("direct-message service response") }
    }
    private static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512
            && value.unicodeScalars.allSatisfy { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) }
    }
    private static func messageID(_ value: String?) throws -> String? {
        guard let value, !value.isEmpty else { return nil }
        guard validID(value) else { throw InvalidResponse.value }
        return value
    }

    private enum InvalidResponse: Error { case value }
    private struct WireCode: Decodable { let errCode: Int64 }
    private struct WireEnvelope<T: Decodable>: Decodable {
        let errCode: Int64
        let data: T?
    }
    private struct WireConversations: Decodable { let conversations: [WireConversation] }
    private struct WireConversation: Decodable {
        let ownerUserID: String
        let conversationID: String
        let conversationType: Int
        let userID: String
        let recvMsgOpt: Int
        let minSeq: Int64
        let maxSeq: Int64
    }
    private struct WireSequences: Decodable { let seqs: [String: WireSequence] }
    private struct WireSequence: Decodable { let maxSeq: Int64; let hasReadSeq: Int64 }
    private struct WirePull: Decodable { let msgs: [String: WirePullConversation] }
    private struct WirePullConversation: Decodable {
        let messages: [WireMessage]
        let isEnd: Bool
        private enum CodingKeys: String, CodingKey { case Msgs, isEnd }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            // sdkws.pb.go v0.0.14:1258-1264 has json:"Msgs" without
            // omitempty: nil slices encode as null, not a missing key.
            guard values.contains(.Msgs) else { throw InvalidResponse.value }
            messages = try values.decodeIfPresent([WireMessage].self, forKey: .Msgs) ?? []
            isEnd = try values.decode(Bool.self, forKey: .isEnd)
        }
    }
    private struct WireMessage: Decodable {
        let sequence: Int64
        let metadata: WireMessageMetadata?
        private enum CodingKeys: String, CodingKey { case seq, status }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            sequence = try values.decode(Int64.self, forKey: .seq)
            switch try values.decode(Int.self, forKey: .status) {
            case 1: metadata = try WireMessageMetadata(from: decoder)
            case 4: metadata = nil
            default: throw InvalidResponse.value
            }
        }
    }
    private struct WireMessageMetadata: Decodable {
        let sendID: String
        let recvID: String
        let clientMsgID: String?
        let serverMsgID: String?
        let sessionType: Int
        let contentType: Int
        let sendTime: Int64
    }
}
