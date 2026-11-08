import Foundation

public enum ActivityAlerts {
    // Fetch current rows after any suspended refresh work. Local read/dismiss
    // actions win over queued alerts, and delivery uses the latest enrichment.
    public static func pending(_ queued: [Activity], in state: LibraryState) -> [Activity] {
        let current = Dictionary(state.activity.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        return queued.compactMap { candidate in
            guard seen.insert(candidate.id).inserted,
                !(state.dismissedActivityIDs ?? []).contains(candidate.id),
                let item = current[candidate.id], !item.isRead else { return nil }
            return item
        }
    }
}
