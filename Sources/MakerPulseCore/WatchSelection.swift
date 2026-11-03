import Foundation

public enum ModelWatchFilter: String, CaseIterable, Codable, Identifiable, Sendable {
    case all, watched, paused
    public var id: String { rawValue }
    public var title: String { switch self { case .all: "All models"; case .watched: "Watched"; case .paused: "Paused" } }
    public func includes(_ design: Design, watches: [String: WatchRule]) -> Bool {
        let enabled = watches[design.id]?.enabled ?? true
        return self == .all || (self == .watched ? enabled : !enabled)
    }
    public func count(_ designs: [Design], watches: [String: WatchRule]) -> Int { designs.filter { includes($0, watches: watches) }.count }
}
