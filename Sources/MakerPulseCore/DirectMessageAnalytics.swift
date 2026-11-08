import Foundation
import CryptoKit

// Prepared against the public OpenIM contract. No network or application
// connection calls this code until MakerWorld's deployed schema is verified.
public struct DirectMessageBatch: Sendable {
    public let conversations: [DirectMessageConversation]
    public let conversationTotal: Int
    public let unreadTotal: Int
    public init(conversations: [DirectMessageConversation], conversationTotal: Int, unreadTotal: Int) throws {
        guard conversationTotal >= 0, unreadTotal >= 0,
            conversations.count == conversationTotal,
            Set(conversations.map(\.conversationID)).count == conversationTotal,
            conversations.allSatisfy({ !$0.conversationID.isEmpty && $0.unreadCount >= 0 }) else {
            throw PulseError.incomplete("direct-message conversations")
        }
        var countedUnread = 0
        for row in conversations {
            guard row.unreadCount <= unreadTotal - countedUnread else { throw PulseError.incomplete("direct-message unread total") }
            countedUnread += row.unreadCount
        }
        guard countedUnread == unreadTotal else { throw PulseError.incomplete("direct-message unread total") }
        self.conversations = conversations; self.conversationTotal = conversationTotal; self.unreadTotal = unreadTotal
    }
}

public enum DirectMessagePagination {
    public static func collect(limit: Int = 20, maxPages: Int = 500,
        fetch: @Sendable (Int, Int) async throws -> DirectMessagePage) async throws -> DirectMessageBatch {
        guard (1...100).contains(limit), maxPages > 0, maxPages <= 500 else { throw PulseError.incomplete("direct-message page limit") }
        var output: [DirectMessageConversation] = [], seen = Set<String>()
        var expected: Int?, unread: Int?
        for number in 1...maxPages {
            try Task.checkCancellation()
            let page = try await fetch(number, limit)
            try Task.checkCancellation()
            guard page.conversationTotal >= 0, page.unreadTotal >= 0,
                page.conversations.count <= limit,
                expected == nil || expected == page.conversationTotal,
                unread == nil || unread == page.unreadTotal else { throw PulseError.incomplete("changing direct-message conversations") }
            expected = page.conversationTotal; unread = page.unreadTotal
            for row in page.conversations {
                guard seen.insert(row.conversationID).inserted else { throw PulseError.incomplete("repeating direct-message page") }
                output.append(row)
            }
            guard output.count <= page.conversationTotal else { throw PulseError.incomplete("direct-message total") }
            if output.count == page.conversationTotal {
                return try DirectMessageBatch(conversations: output, conversationTotal: page.conversationTotal, unreadTotal: page.unreadTotal)
            }
            guard page.conversations.count == limit else { throw PulseError.incomplete("short direct-message page") }
        }
        throw PulseError.incomplete("direct-message page limit")
    }
}

// Only opaque hashes, timestamps and the baseline are retained. Message bodies,
// attachments, participant names, credentials and remote read state are absent.
public struct DirectMessageState: Codable, Sendable, Equatable {
    public var profileKey: String
    public var baselineAt: Date
    public var lastSync: Date
    public var aliases: [String: String] = [:]
    public var conversationWatermarks: [String: Date] = [:]
    public init(profileKey: String, baselineAt: Date) {
        self.profileKey = profileKey; self.baselineAt = baselineAt; self.lastSync = baselineAt
    }
}

public enum DirectMessageAnalytics {
    private static func key(_ parts: [String]) -> String {
        let data = (try? JSONEncoder().encode(parts)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // The caller must persist library and metadata atomically before delivering
    // returned alerts. A complete initial snapshot is quiet; currently unread
    // incoming messages can still appear in Activity. Later snapshots expose
    // only the latest message per conversation, not every between-poll message.
    public static func ingest(_ batch: DirectMessageBatch, profileID: String,
        metadata: inout DirectMessageState?, into library: inout LibraryState,
        at date: Date, notificationsEnabled: Bool = true) throws -> [Activity] {
        try Task.checkCancellation()
        guard !profileID.isEmpty, library.preferences.userID == profileID else { throw PulseError.accountMismatch }
        let profileKey = key(["profile", profileID])
        guard metadata == nil || metadata?.profileKey == profileKey else { throw PulseError.accountMismatch }
        let baseline = metadata == nil
        var next = metadata ?? DirectMessageState(profileKey: profileKey, baselineAt: date)
        var additions: [Activity] = [], alerts: [Activity] = []
        let existing = Set(library.activity.map(\.id))
        for conversation in batch.conversations {
            guard let message = conversation.latestMessage else { continue }
            let conversationKey = key([profileKey, conversation.conversationID])
            let aliases = message.identityKeys.map { key([conversationKey, $0]) }
            guard !aliases.isEmpty, message.sentAt.timeIntervalSince1970.isFinite,
                message.sentAt <= date.addingTimeInterval(300) else { throw PulseError.malformed("direct-message metadata") }
            let knownIDs = Set(aliases.compactMap { next.aliases[$0] })
            guard knownIDs.count <= 1 else { throw PulseError.malformed("conflicting direct-message identity") }
            let known = !knownIDs.isEmpty
            let watermark = next.conversationWatermarks[conversationKey]
            next.conversationWatermarks[conversationKey] = max(watermark ?? .distantPast, message.sentAt)
            let newer = message.sentAt > (watermark ?? next.baselineAt)
            // A stale sparse observation with entirely different IDs must not
            // establish a competing canonical identity. Watermarks already
            // consume it quietly; a later explicit alias bridge can still
            // enrich the original identity without guessing that they match.
            guard known || baseline || newer else { continue }
            let activityID = knownIDs.first ?? "direct:\(aliases[0])"
            for alias in aliases { next.aliases[alias] = activityID }
            // User-message content types verified in the public MakerWorld
            // client/OpenIM constants. Typing, recall and system events do not
            // become new-message alerts merely because unreadCount is nonzero.
            guard message.isIncomingDirectMessage, (101...105).contains(message.contentType),
                conversation.unreadCount > 0, conversation.receiveOption != .notReceive,
                !known, baseline || newer,
                !existing.contains(activityID), !(library.dismissedActivityIDs ?? []).contains(activityID) else { continue }
            let activity = Activity(id: activityID, date: message.sentAt, title: "New direct message",
                detail: "You have an unread MakerWorld direct message. Open MakerWorld to view it.", symbol: "bubble.left.and.bubble.right",
                presentation: ActivityPresentation(originalTimestamp: true))
            additions.append(activity)
            if !baseline, notificationsEnabled, conversation.receiveOption == .normal { alerts.append(activity) }
        }
        // Stage everything first: malformed metadata or identity conflicts leave
        // both caller-owned values untouched, including read/dismissed controls.
        next.lastSync = date
        try Task.checkCancellation()
        library.activity = Array((library.activity + additions).sorted { $0.date > $1.date }.prefix(1000))
        metadata = next
        return alerts
    }
}
