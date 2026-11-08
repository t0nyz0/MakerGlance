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
    public var sequence: Int64?

    public init(clientMessageID: String? = nil, serverMessageID: String? = nil, sessionType: Int,
        direction: DirectMessageDirection, sentAt: Date, contentType: Int, sequence: Int64? = nil) {
        self.clientMessageID = clientMessageID; self.serverMessageID = serverMessageID
        self.sessionType = sessionType; self.direction = direction
        self.sentAt = sentAt; self.contentType = contentType
        self.sequence = sequence
    }

    public var isIncomingDirectMessage: Bool { sessionType == 1 && direction == .incoming }

    /// These aliases must be scoped to the conversation by the consumer. Keep
    /// both so a later response that adds a server ID need not replay a message.
    public var identityKeys: [String] {
        [clientMessageID.map { "client:" + $0 }, serverMessageID.map { "server:" + $0 }, sequence.map { "sequence:\($0)" }].compactMap { $0 }
    }
}

public struct DirectMessageConversation: Codable, Equatable, Sendable {
    public var conversationID: String
    public var unreadCount: Int
    public var receiveOption: DirectMessageReceiveOption
    public var latestMessage: DirectMessageMetadata?
    public var messages: [DirectMessageMetadata]?
    public var maximumSequence: Int64?
    public var readSequence: Int64?

    public init(conversationID: String, unreadCount: Int, receiveOption: DirectMessageReceiveOption,
        latestMessage: DirectMessageMetadata?, messages: [DirectMessageMetadata]? = nil,
        maximumSequence: Int64? = nil, readSequence: Int64? = nil) {
        self.conversationID = conversationID; self.unreadCount = unreadCount
        self.receiveOption = receiveOption; self.latestMessage = latestMessage
        self.messages = messages; self.maximumSequence = maximumSequence; self.readSequence = readSequence
    }
}
