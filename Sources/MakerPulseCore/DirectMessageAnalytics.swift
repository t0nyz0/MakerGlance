import Foundation
import CryptoKit

// A complete, metadata-only observation. No chat content is retained.
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

// Only opaque hashes, timestamps and the baseline are retained. Message bodies,
// attachments, participant names, credentials and remote read state are absent.
public struct DirectMessageState: Codable, Sendable, Equatable {
    public var profileKey: String
    public var baselineAt: Date
    public var lastSync: Date
    public var aliases: [String: String] = [:]
    public var conversationWatermarks: [String: Date] = [:]
    public var sequenceWatermarks: [String: Int64]?
    public init(profileKey: String, baselineAt: Date) {
        self.profileKey = profileKey; self.baselineAt = baselineAt; self.lastSync = baselineAt
    }
}

public enum DirectMessageAnalytics {
    private static func key(_ parts: [String]) -> String {
        let data = (try? JSONEncoder().encode(parts)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func knownSequence(conversationID: String, profileID: String, metadata: DirectMessageState?) throws -> Int64? {
        guard !profileID.isEmpty else { throw PulseError.accountMismatch }
        let profileKey = key(["profile", profileID])
        guard metadata == nil || metadata?.profileKey == profileKey else { throw PulseError.accountMismatch }
        let value = metadata?.sequenceWatermarks?[key([profileKey, conversationID])]
        guard value.map({ $0 >= 0 }) ?? true else { throw PulseError.malformed("direct-message watermark") }
        return value
    }

    // The caller must persist library and metadata atomically before delivering
    // returned alerts. A complete initial snapshot is quiet; currently unread
    // incoming messages can still appear in Activity. The deployed service
    // supplies complete bounded sequence windows, including multiple messages.
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
            let conversationKey = key([profileKey, conversation.conversationID])
            let previousSequence = next.sequenceWatermarks?[conversationKey]
            guard (conversation.maximumSequence == nil) == (conversation.readSequence == nil),
                conversation.maximumSequence.map({ $0 >= 0 }) ?? true,
                conversation.readSequence.map({ $0 >= 0 }) ?? true else { throw PulseError.malformed("direct-message sequence") }
            let messages = conversation.messages ?? conversation.latestMessage.map { [$0] } ?? []
            var observedSequences = Set<Int64>()
            for message in messages {
                let aliases = message.identityKeys.map { key([conversationKey, $0]) }
                guard !aliases.isEmpty, message.sentAt.timeIntervalSince1970.isFinite,
                    message.sentAt <= date.addingTimeInterval(300) else { throw PulseError.malformed("direct-message metadata") }
                if let maximum = conversation.maximumSequence {
                    guard let sequence = message.sequence, sequence > 0, sequence <= maximum,
                        observedSequences.insert(sequence).inserted else { throw PulseError.malformed("direct-message sequence") }
                }
                let knownIDs = Set(aliases.compactMap { next.aliases[$0] })
                guard knownIDs.count <= 1 else { throw PulseError.malformed("conflicting direct-message identity") }
                let known = !knownIDs.isEmpty
                let watermark = next.conversationWatermarks[conversationKey]
                next.conversationWatermarks[conversationKey] = max(watermark ?? .distantPast, message.sentAt)
                let newer: Bool
                if let sequence = message.sequence, conversation.maximumSequence != nil {
                    newer = previousSequence.map { sequence > $0 } ?? (message.sentAt > next.baselineAt)
                } else { newer = message.sentAt > (watermark ?? next.baselineAt) }
                // Stale alternate IDs do not create a competing canonical ID.
                guard known || baseline || newer else { continue }
                let canonical = message.sequence.map { key([conversationKey, "sequence:\($0)"]) } ?? aliases[0]
                let activityID = knownIDs.first ?? "direct:\(canonical)"
                for alias in aliases { next.aliases[alias] = activityID }
                let remotelyRead = message.sequence.flatMap { sequence in conversation.readSequence.map { sequence <= $0 } } ?? (conversation.unreadCount == 0)
                // Legacy summary observations require unreadCount; deployed
                // sequence windows also retain fresh already-read rows quietly.
                guard message.isIncomingDirectMessage, (101...105).contains(message.contentType),
                    conversation.maximumSequence != nil || conversation.unreadCount > 0,
                    conversation.receiveOption != .notReceive, !known, baseline || newer,
                    !existing.contains(activityID), !(library.dismissedActivityIDs ?? []).contains(activityID) else { continue }
                let activity = Activity(id: activityID, date: message.sentAt, title: "New direct message",
                    detail: "A MakerWorld direct message was received. Open MakerWorld to view it.", symbol: "bubble.left.and.bubble.right",
                    isRead: remotelyRead, presentation: ActivityPresentation(originalTimestamp: true))
                additions.append(activity)
                if !baseline, !remotelyRead, notificationsEnabled, conversation.receiveOption == .normal { alerts.append(activity) }
            }
            if let maximum = conversation.maximumSequence {
                var watermarks = next.sequenceWatermarks ?? [:]
                watermarks[conversationKey] = max(previousSequence ?? 0, maximum)
                next.sequenceWatermarks = watermarks
            }
        }
        // Stage everything first: malformed metadata or identity conflicts leave
        // both caller-owned values untouched, including read/dismissed controls.
        next.lastSync = date
        try Task.checkCancellation()
        library.activity = Array((library.activity + additions).sorted {
            $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date
        }.prefix(1000))
        metadata = next
        return alerts
    }
}
