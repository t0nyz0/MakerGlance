import Foundation

public enum ModelActivityWindow: String, CaseIterable, Identifiable, Sendable {
    case today, day, week
    public var id: String { rawValue }
    public var title: String { switch self { case .today: "Today"; case .day: "24 hours"; case .week: "7 days" } }
    public func interval(now: Date, calendar: Calendar = .autoupdatingCurrent) -> DateInterval {
        let start: Date = switch self {
        case .today: calendar.startOfDay(for: now)
        case .day: now.addingTimeInterval(-86400)
        case .week: now.addingTimeInterval(-7 * 86400)
        }
        return DateInterval(start: start, end: now)
    }
}

public struct ObservedModelActivity: Identifiable, Equatable, Sendable {
    public var design: Design
    public var deltas: [Metric: Int]
    public var baselineDate: Date?
    public var lastObservedAt: Date?
    public var lastMetricChangeAt: Date?
    public var latestEvent: Activity?
    public var id: String { design.id }
    public var lastActivityAt: Date? { [lastMetricChangeAt, latestEvent?.date].compactMap { $0 }.max() }
    public var changedMetrics: [Metric] { ModelActivity.metrics.filter { deltas[$0].map { $0 != 0 } ?? false } }
    public var hasComparison: Bool { !deltas.isEmpty }
}

public enum ModelActivity {
    public static let metrics: [Metric] = [.likes, .downloads, .boosts, .prints, .collections]

    // Use full-fidelity snapshots, independent of notification preferences and
    // high-water marks. A fetch or title/image edit is not metric activity.
    public static func ranked(designs: [Design], samples: [String: [Sample]], events: [Activity], window: ModelActivityWindow,
                              now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> [ObservedModelActivity] {
        let interval = window.interval(now: now, calendar: calendar)
        let modelEvents = Dictionary(grouping: events.filter { $0.modelID != nil && $0.date >= interval.start && $0.date <= now }, by: { $0.modelID! })
        return designs.map { design in
            let history = (samples[design.id] ?? []).filter { $0.date <= now }.sorted { $0.date < $1.date }
            let period = history.filter { $0.date >= interval.start }
            var deltas: [Metric: Int] = [:]
            var lastChange: Date?
            for metric in metrics {
                let valid = history.filter { $0.counts[metric] != nil }
                let inPeriod = valid.filter { $0.date >= interval.start }
                if let first = inPeriod.first, let last = inPeriod.last, first.date < last.date {
                    deltas[metric] = last.counts[metric]! - first.counts[metric]!
                }
                for (before, after) in zip(valid, valid.dropFirst()) where before.date < after.date && after.date >= interval.start && before.counts[metric] != after.counts[metric] {
                    lastChange = max(lastChange ?? .distantPast, after.date)
                }
            }
            let event = modelEvents[design.id]?.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }.first
            return ObservedModelActivity(design: design, deltas: deltas, baselineDate: period.first?.date,
                lastObservedAt: period.last?.date, lastMetricChangeAt: lastChange, latestEvent: event)
        }.sorted { left, right in
            if left.lastActivityAt != right.lastActivityAt { return (left.lastActivityAt ?? .distantPast) > (right.lastActivityAt ?? .distantPast) }
            let order = left.design.title.localizedStandardCompare(right.design.title)
            return order == .orderedSame ? left.id < right.id : order == .orderedAscending
        }
    }
}
