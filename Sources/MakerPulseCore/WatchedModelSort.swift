import Foundation

public enum WatchedModelSort: String, Codable, CaseIterable, Identifiable, Sendable {
    case recent, prints, saves, boosts, downloads, likes
    public var id: String { rawValue }
    public var title: String { switch self { case .recent: "Recent activity"; case .prints: "Most prints"; case .saves: "Most saves"; case .boosts: "Most boosts"; case .downloads: "Most downloads"; case .likes: "Most likes" } }
    public var metric: Metric? { switch self { case .recent: nil; case .prints: .prints; case .saves: .collections; case .boosts: .boosts; case .downloads: .downloads; case .likes: .likes } }
}
public enum WatchedSortBasis: String, Codable, CaseIterable, Sendable { case total, growth }
public enum WatchedModelSorting {
    public static func ordered(_ rows: [ObservedModelActivity], by sort: WatchedModelSort, basis: WatchedSortBasis) -> [ObservedModelActivity] {
        rows.sorted { a, b in
            if let metric = sort.metric {
                let x = basis == .total ? a.design.counts[metric] : a.deltas[metric]
                let y = basis == .total ? b.design.counts[metric] : b.deltas[metric]
                if x != y { if x == nil { return false }; if y == nil { return true }; return x! > y! }
            } else if a.lastActivityAt != b.lastActivityAt {
                if a.lastActivityAt == nil { return false }; if b.lastActivityAt == nil { return true }
                return a.lastActivityAt! > b.lastActivityAt!
            }
            let title = a.design.title.localizedStandardCompare(b.design.title)
            return title == .orderedSame ? a.id < b.id : title == .orderedAscending
        }
    }
}
