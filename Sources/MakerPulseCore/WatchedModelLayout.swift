import Foundation

public enum WatchedModelLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case cards, compact
    public var id: String { rawValue }
    public var title: String { self == .cards ? "Cards" : "Compact" }
}

// Presentation changes never re-rank, re-aggregate or re-baseline observations.
// Both layouts render this same selection, including the same initial limit.
public struct WatchedModelSelection: Sendable {
    public let all: [ObservedModelActivity]
    public let visible: [ObservedModelActivity]
    public init(ranked: [ObservedModelActivity], watches: [String: WatchRule], expanded: Bool) {
        all = ranked.filter { watches[$0.id]?.enabled ?? true }
        visible = expanded ? all : Array(all.prefix(9))
    }
}
