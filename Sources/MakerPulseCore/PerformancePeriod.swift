import Foundation

public enum PerformancePeriod: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, threeMonths, sixMonths, year, lastCalendarMonth, lifetime
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .day: "1 Day"; case .week: "1 Week"; case .month: "1 Month"
        case .threeMonths: "3 Months"; case .sixMonths: "6 Months"; case .year: "1 Year"
        case .lastCalendarMonth: "Last Calendar Month (UTC)"; case .lifetime: "Lifetime"
        }
    }
    public func interval(now: Date, calendar: Calendar = .autoupdatingCurrent) -> DateInterval? {
        guard self != .lifetime else { return nil }
        if self == .lastCalendarMonth {
            let utc = CreatorPeriod.calendar
            let end = utc.dateInterval(of: .month, for: now)!.start
            return DateInterval(start: utc.date(byAdding: .month, value: -1, to: end)!, end: end)
        }
        let start: Date
        switch self {
        case .day: start = now.addingTimeInterval(-86400)
        case .week: start = now.addingTimeInterval(-7 * 86400)
        case .month: start = calendar.date(byAdding: .month, value: -1, to: now)!
        case .threeMonths: start = calendar.date(byAdding: .month, value: -3, to: now)!
        case .sixMonths: start = calendar.date(byAdding: .month, value: -6, to: now)!
        case .year: start = calendar.date(byAdding: .year, value: -1, to: now)!
        case .lastCalendarMonth, .lifetime: preconditionFailure("Handled above")
        }
        return DateInterval(start: start, end: now)
    }
}

public struct PerformanceObservation: Equatable, Sendable {
    public var value: Decimal?
    public var comparisonStart: Date?
    public var comparisonEnd: Date?
    public var observations: Int
    public var expectedDays: Int?
    public var isPartial: Bool
    public var largestGap: TimeInterval
    public var unavailableReason: String?
    public var coverageLabel: String {
        if unavailableReason != nil, expectedDays != nil { return "Unavailable" }
        if let expectedDays { return "\(observations)/\(expectedDays) days\(isPartial ? " · partial" : " returned")" }
        guard value != nil else { return observations == 1 ? "One observation" : "No comparison" }
        return isPartial ? "Partial · net change" : "Observed net change"
    }
}

public enum ProfilePerformance {
    /// Compares actual observations inside the requested window. No boundary
    /// interpolation, extrapolation, zero filling or gross-event inference.
    public static func netChange(metric: Metric, samples: [Sample], interval: DateInterval) -> PerformanceObservation {
        var values: [Date: Int] = [:]
        for sample in samples where sample.date >= interval.start && sample.date <= interval.end {
            guard let count = sample.counts[metric] else { continue }
            if let previous = values[sample.date], previous != count {
                return PerformanceObservation(value: nil, comparisonStart: nil, comparisonEnd: nil, observations: 0, expectedDays: nil, isPartial: true, largestGap: 0, unavailableReason: "Conflicting observations at the same time")
            }
            values[sample.date] = count
        }
        let times = values.keys.sorted()
        let first = times.first, last = times.last
        let value = times.count >= 2 ? Decimal(values[last!]!) - Decimal(values[first!]!) : nil
        return PerformanceObservation(value: value, comparisonStart: first, comparisonEnd: last, observations: times.count, expectedDays: nil,
            isPartial: first != interval.start || last != interval.end,
            largestGap: zip(times, times.dropFirst()).map { $1.timeIntervalSince($0) }.max() ?? 0,
            unavailableReason: value == nil ? "At least two observations of this metric are required" : nil)
    }

    /// Server daily model activity has a different source and UTC scope from
    /// profile snapshot changes. Only returned days contribute to its total.
    public static func calendarMonthTotal(metric: Metric, report: CreatorReport?, interval: DateInterval) -> PerformanceObservation {
        let calendar = CreatorPeriod.calendar
        let expected = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        func unavailable(_ reason: String) -> PerformanceObservation {
            PerformanceObservation(value: nil, comparisonStart: nil, comparisonEnd: nil, observations: 0, expectedDays: expected, isPartial: true, largestGap: 0, unavailableReason: reason)
        }
        guard let month = calendar.dateInterval(of: .month, for: interval.start), month == interval else { return unavailable("A complete UTC calendar-month interval is required") }
        guard metric != .followers else { return unavailable("The server follower-activity field is not verified as a new-follower or net-follower count") }
        guard let report, report.scope == .models else { return unavailable("Load the Models report for this UTC month in Analytics → Creator Center") }
        let key: CreatorMetric
        switch metric {
        case .likes: key = .likes; case .downloads: key = .downloads; case .prints: key = .prints
        case .boosts: key = .boosts; case .collections: key = .saves
        case .followers: return unavailable("Follower event counts are unavailable")
        }
        var days: [Date: Decimal] = [:]
        for row in report.history ?? [] where row.date >= interval.start && row.date < interval.end && row.date >= report.period.start && row.date <= report.period.end {
            guard row.date == calendar.startOfDay(for: row.date), let value = row.metrics[key] else { continue }
            if let previous = days[row.date], previous != value { return unavailable("Conflicting server values for the same UTC day") }
            days[row.date] = value
        }
        let dates = days.keys.sorted()
        guard !dates.isEmpty else { return unavailable("No daily values for this metric and UTC month are stored") }
        return PerformanceObservation(value: days.values.reduce(Decimal(0), +), comparisonStart: dates.first, comparisonEnd: dates.last,
            observations: days.count, expectedDays: expected, isPartial: days.count != expected,
            largestGap: zip(dates, dates.dropFirst()).map { $1.timeIntervalSince($0) }.max() ?? 0, unavailableReason: nil)
    }
}
