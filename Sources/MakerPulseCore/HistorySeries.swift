import Foundation

public struct HistoryPoint: Identifiable, Equatable, Sendable {
    public var date: Date
    public var value: Decimal
    public var id: Date { date }
    public init(date: Date, value: Decimal) { self.date = date; self.value = value }
}
public enum HistorySeries {
    public static func snapshots(_ samples: [Sample], metric: Metric, interval: DateInterval) -> [HistoryPoint] {
        samples.filter { $0.date >= interval.start && $0.date <= interval.end }.sorted { $0.date < $1.date }.compactMap {
            guard let value = $0.counts[metric] else { return nil }
            return HistoryPoint(date: $0.date, value: Decimal(value))
        }
    }
    public static func daily(_ days: [CreatorDaily], metric: CreatorMetric, interval: DateInterval) -> [HistoryPoint] {
        days.filter { $0.date >= interval.start && $0.date < interval.end }.sorted { $0.date < $1.date }.compactMap {
            guard let value = $0.metrics[metric] else { return nil }
            return HistoryPoint(date: $0.date, value: value)
        }
    }
    public static func delta(_ points: [HistoryPoint]) -> Decimal? {
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        return last.value - first.value
    }
    public static func total(_ points: [HistoryPoint]) -> Decimal? { points.isEmpty ? nil : points.reduce(Decimal(0)) { $0 + $1.value } }
}
