import Foundation

public enum DirectMessageDirection: String, Codable, Sendable {
    case incoming, outgoing, other
}

public enum DirectMessageReceiveOption: Int, Codable, Sendable {
    case normal = 0, notReceive = 1, notNotify = 2
}

/// A message's identity and delivery metadata. Participant IDs, names, content,
/// attachment URLs, and authentication material are deliberately not retained.
public struct DirectMessageMetadata: Codable, Equatable, Sendable {
    public var clientMessageID: String?
    public var serverMessageID: String?
    public var sessionType: Int
    public var direction: DirectMessageDirection
    public var sentAt: Date
    public var contentType: Int

    public init(clientMessageID: String? = nil, serverMessageID: String? = nil, sessionType: Int,
        direction: DirectMessageDirection, sentAt: Date, contentType: Int) {
        self.clientMessageID = clientMessageID; self.serverMessageID = serverMessageID
        self.sessionType = sessionType; self.direction = direction
        self.sentAt = sentAt; self.contentType = contentType
    }

    public var isIncomingDirectMessage: Bool { sessionType == 1 && direction == .incoming }

    /// These aliases must be scoped to the conversation by the consumer. Keep
    /// both so a later response that adds a server ID need not replay a message.
    public var identityKeys: [String] {
        [clientMessageID.map { "client:" + $0 }, serverMessageID.map { "server:" + $0 }].compactMap { $0 }
    }
}

public struct DirectMessageConversation: Codable, Equatable, Sendable {
    public var conversationID: String
    public var unreadCount: Int
    public var receiveOption: DirectMessageReceiveOption
    public var latestMessage: DirectMessageMetadata?

    public init(conversationID: String, unreadCount: Int, receiveOption: DirectMessageReceiveOption,
        latestMessage: DirectMessageMetadata?) {
        self.conversationID = conversationID; self.unreadCount = unreadCount
        self.receiveOption = receiveOption; self.latestMessage = latestMessage
    }
}

public struct DirectMessagePage: Equatable, Sendable {
    public var conversationTotal: Int
    public var unreadTotal: Int
    public var conversations: [DirectMessageConversation]

    public init(conversationTotal: Int, unreadTotal: Int, conversations: [DirectMessageConversation]) {
        self.conversationTotal = conversationTotal; self.unreadTotal = unreadTotal
        self.conversations = conversations
    }
}

/// Parses the upstream OpenIM sorted-conversation contract, not a verified live
/// MakerWorld response. This parser performs no authentication or network work.
/// Source: openimsdk/protocol at 1a91e17b, conversation/conversation.proto:62-100.
/// Its whitelist contains no message content, names, attachments, or tokens.
public enum DirectMessageParser {
    public static func page(_ data: Data, currentUserID: String) throws -> DirectMessagePage {
        // Errors intentionally contain no response values or decoding context.
        do { return try parse(data, currentUserID: currentUserID) }
        catch { throw PulseError.malformed("direct-message metadata") }
    }

    private static func parse(_ data: Data, currentUserID: String) throws -> DirectMessagePage {
        guard validID(currentUserID) else { throw InvalidMetadata.value }
        let envelope = try JSONDecoder().decode(WireEnvelope.self, from: data)
        guard envelope.errCode == 0, let page = envelope.data else { throw InvalidMetadata.value }
        let total = try count(page.conversationTotal), unreadTotal = try count(page.unreadTotal)
        guard total >= page.conversationElems.count, total != 0 || unreadTotal == 0 else { throw InvalidMetadata.value }
        var seen = Set<String>(), unreadOnPage = 0
        let conversations = try page.conversationElems.map { row in
            guard validID(row.conversationID), seen.insert(row.conversationID).inserted,
                let receiveOption = DirectMessageReceiveOption(rawValue: row.recvMsgOpt) else { throw InvalidMetadata.value }
            let unread = try count(row.unreadCount)
            // The ceiling in count() makes addition safe; check before adding
            // anyway so a corrupt page never wraps or reports a partial result.
            guard unread <= unreadTotal - unreadOnPage else { throw InvalidMetadata.value }
            unreadOnPage += unread
            let message = try row.msgInfo.map { try metadata($0, currentUserID: currentUserID) }
            return DirectMessageConversation(conversationID: row.conversationID, unreadCount: unread,
                receiveOption: receiveOption, latestMessage: message)
        }
        return DirectMessagePage(conversationTotal: total, unreadTotal: unreadTotal, conversations: conversations)
    }

    private static func metadata(_ wire: WireMessage, currentUserID: String) throws -> DirectMessageMetadata {
        let clientID = try messageID(wire.clientMsgID), serverID = try messageID(wire.serverMsgID)
        guard clientID != nil || serverID != nil, (1...4).contains(wire.sessionType),
            validID(wire.sendID), validID(wire.recvID), wire.contentType > 0, wire.contentType <= Int32.max,
            // MakerWorld messages are contemporary. These bounds reject zero,
            // seconds-shaped values, and dates beyond the supported calendar.
            wire.LatestMsgRecvTime >= 946_684_800_000, wire.LatestMsgRecvTime <= 253_402_300_799_999
        else { throw InvalidMetadata.value }
        let direction: DirectMessageDirection = wire.sendID == currentUserID ? .outgoing
            : wire.recvID == currentUserID ? .incoming : .other
        return DirectMessageMetadata(clientMessageID: clientID, serverMessageID: serverID,
            sessionType: wire.sessionType, direction: direction,
            sentAt: Date(timeIntervalSince1970: Double(wire.LatestMsgRecvTime) / 1_000), contentType: wire.contentType)
    }

    private static func count(_ value: Int64) throws -> Int {
        guard value >= 0, value <= Int32.max else { throw InvalidMetadata.value }
        return Int(value)
    }

    private static func messageID(_ value: String?) throws -> String? {
        guard let value, !value.isEmpty else { return nil }
        guard validID(value) else { throw InvalidMetadata.value }
        return value
    }

    private static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512
            && value.unicodeScalars.allSatisfy { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) }
    }

    private enum InvalidMetadata: Error { case value }
    private struct WireEnvelope: Decodable {
        let errCode: Int64
        let data: WirePage?
    }
    private struct WirePage: Decodable {
        let conversationTotal: Int64
        let unreadTotal: Int64
        let conversationElems: [WireConversation]
    }
    private struct WireConversation: Decodable {
        let conversationID: String
        let recvMsgOpt: Int
        let unreadCount: Int64
        let msgInfo: WireMessage?
    }
    private struct WireMessage: Decodable {
        let clientMsgID: String?
        let serverMsgID: String?
        let sessionType: Int
        let sendID: String
        let recvID: String
        let LatestMsgRecvTime: Int64
        let contentType: Int
    }
}
