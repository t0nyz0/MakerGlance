import Foundation

public enum LocalControls {
    // A SQLite commit can suspend the UI actor. Preserve controls edited while
    // that observation was saving, without replacing newly ingested API data.
    @discardableResult public static func preserve(from current: LibraryState, in observation: inout LibraryState) -> Bool {
        var changed = false
        if observation.preferences != current.preferences { observation.preferences = current.preferences; changed = true }
        for (id, rule) in current.watches where observation.watches[id] != rule { observation.watches[id] = rule; changed = true }
        if let preferences = current.account?.preferences, observation.account != nil, observation.account?.preferences != preferences {
            observation.account?.preferences = preferences; changed = true
        }
        let dismissed = (observation.dismissedActivityIDs ?? []).union(current.dismissedActivityIDs ?? [])
        if observation.dismissedActivityIDs != dismissed { observation.dismissedActivityIDs = dismissed; changed = true }
        let count = observation.activity.count
        observation.activity.removeAll { dismissed.contains($0.id) }
        if observation.activity.count != count { changed = true }
        let read = Set(current.activity.filter(\.isRead).map(\.id))
        for i in observation.activity.indices where !observation.activity[i].isRead && read.contains(observation.activity[i].id) {
            observation.activity[i].isRead = true; changed = true
        }
        if let history = current.printHistory, history.accountID == observation.preferences.userID,
            (history.lastSync ?? .distantPast) > (observation.printHistory?.lastSync ?? .distantPast) {
            observation.printHistory = history; changed = true
        }
        return changed
    }
}
