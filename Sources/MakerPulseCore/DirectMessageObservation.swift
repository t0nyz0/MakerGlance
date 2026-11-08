import Foundation

public enum DirectMessageObservation {
    // Creator/public/control snapshots may have been taken before a suspended
    // DM commit. Preserve the monotonic DM ledger at both the UI and SQLite
    // boundaries so a stale snapshot cannot erase it and replay an alert.
    @discardableResult public static func preserve(from current: LibraryState, in observation: inout LibraryState) throws -> Bool {
        guard current.preferences.userID == observation.preferences.userID,
            let saved = current.account?.directMessages else { return false }
        _ = try DirectMessageAnalytics.knownSequence(conversationID: "", profileID: current.preferences.userID, metadata: saved)
        _ = try DirectMessageAnalytics.knownSequence(conversationID: "", profileID: observation.preferences.userID, metadata: observation.account?.directMessages)
        let incoming = observation.account?.directMessages
        if let incoming, saved.aliases.contains(where: { alias, identity in incoming.aliases[alias].map { $0 != identity } ?? false }) {
            throw PulseError.malformed("direct-message identity ledger")
        }
        var merged = incoming.map { $0.lastSync >= saved.lastSync ? $0 : saved } ?? saved
        if let incoming {
            merged.aliases = saved.aliases.merging(incoming.aliases, uniquingKeysWith: { old, new in incoming.lastSync >= saved.lastSync ? new : old })
            merged.conversationWatermarks = saved.conversationWatermarks.merging(incoming.conversationWatermarks, uniquingKeysWith: max)
            merged.sequenceWatermarks = (saved.sequenceWatermarks ?? [:]).merging(incoming.sequenceWatermarks ?? [:], uniquingKeysWith: max)
            merged.baselineAt = min(saved.baselineAt, incoming.baselineAt)
            merged.lastSync = max(saved.lastSync, incoming.lastSync)
        }
        var changed = incoming != merged
        if observation.account == nil { observation.account = current.account }
        observation.account?.directMessages = merged
        let dismissed = (observation.dismissedActivityIDs ?? []).union((current.dismissedActivityIDs ?? []).filter { $0.hasPrefix("direct:") })
        if observation.dismissedActivityIDs != dismissed { observation.dismissedActivityIDs = dismissed; changed = true }
        var rows = Dictionary(current.activity.filter { $0.id.hasPrefix("direct:") }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for var row in observation.activity where row.id.hasPrefix("direct:") {
            row.isRead = row.isRead || rows[row.id]?.isRead == true
            rows[row.id] = row
        }
        let activity = Array((observation.activity.filter { !$0.id.hasPrefix("direct:") }
            + rows.values.filter { !dismissed.contains($0.id) }).sorted {
                $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date
            }.prefix(1000))
        if activity != observation.activity { observation.activity = activity; changed = true }
        return changed
    }
}
