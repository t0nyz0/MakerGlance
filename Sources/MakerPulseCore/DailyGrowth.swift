import Foundation

public struct DayGrowth: Sendable, Equatable {
    public var value: Int?
    public var baselineDate: Date?
    public var interval: DateInterval
    public var timeZoneID: String
    public var isPartial: Bool { baselineDate.map { $0.timeIntervalSince(interval.start) >= 1 } ?? true }
    public static func evaluate(metric: Metric, baseline: Sample?, current: Counts, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> DayGrowth {
        let day = calendar.dateInterval(of: .day, for: now)!
        guard let baseline, baseline.date >= day.start, baseline.date < day.end, baseline.date <= now,
            let before = baseline.counts[metric], let latest = current[metric] else {
            return DayGrowth(value: nil, baselineDate: nil, interval: day, timeZoneID: calendar.timeZone.identifier)
        }
        return DayGrowth(value: latest - before, baselineDate: baseline.date, interval: day, timeZoneID: calendar.timeZone.identifier)
    }
}
