import XCTest
@testable import MakerPulseCore

final class PerformancePeriodTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func report(_ days: [CreatorDaily], scope: CreatorScope = .models, start: String = "2026-10-01T00:00:00Z", end: String = "2026-10-31T00:00:00Z") -> CreatorReport {
        CreatorReport(scope: scope, period: try! CreatorPeriod(start: date(start), end: date(end)), fetchedAt: date("2026-11-22T00:00:00Z"), rows: [], history: days, historyStatus: nil)
    }
    private var october: DateInterval { PerformancePeriod.lastCalendarMonth.interval(now: date("2026-11-22T12:00:00Z"))! }

    func testRollingMonthAndLastCalendarMonthAreDifferent() {
        let now = date("2026-11-22T12:00:00Z")
        let rolling = PerformancePeriod.month.interval(now: now, calendar: CreatorPeriod.calendar)!
        XCTAssertEqual(rolling.start, date("2026-10-22T12:00:00Z")); XCTAssertEqual(rolling.end, now)
        XCTAssertEqual(october.start, date("2026-10-01T00:00:00Z")); XCTAssertEqual(october.end, date("2026-11-01T00:00:00Z"))
        XCTAssertNil(PerformancePeriod.lifetime.interval(now: now))
    }
    func testDayAndWeekAreExactDurationsAcrossDSTButMonthsUseCalendar() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = date("2026-11-02T12:00:00Z")
        XCTAssertEqual(PerformancePeriod.day.interval(now: now, calendar: calendar)!.duration, 86400)
        XCTAssertEqual(PerformancePeriod.week.interval(now: now, calendar: calendar)!.duration, 7 * 86400)
        let leap = date("2024-03-31T12:00:00Z")
        XCTAssertEqual(PerformancePeriod.month.interval(now: leap, calendar: CreatorPeriod.calendar)!.start, date("2024-02-29T12:00:00Z"))
        XCTAssertEqual(PerformancePeriod.year.interval(now: date("2024-02-29T12:00:00Z"), calendar: CreatorPeriod.calendar)!.start, date("2023-02-28T12:00:00Z"))
    }
    func testSnapshotChangeCanBeNegativeOrZeroAndNeverMeansGrossLikesReceived() {
        let interval = DateInterval(start: date("2026-11-01T00:00:00Z"), end: date("2026-11-02T00:00:00Z"))
        let values = [Sample(date: interval.start, counts: Counts(likes: 100, prints: 7)), Sample(date: interval.end, counts: Counts(likes: 96, prints: 7))]
        let likes = ProfilePerformance.netChange(metric: .likes, samples: values, interval: interval)
        XCTAssertEqual(likes.value, -4); XCTAssertFalse(likes.isPartial)
        XCTAssertEqual(ProfilePerformance.netChange(metric: .prints, samples: values, interval: interval).value, 0)
        XCTAssertNil(ProfilePerformance.netChange(metric: .downloads, samples: values, interval: interval).value)
    }
    func testMissingBaselineAndSingleObservationNeverBecomeZero() {
        let result = ProfilePerformance.netChange(metric: .likes, samples: [Sample(date: october.start, counts: Counts(likes: 5000))], interval: october)
        XCTAssertNil(result.value); XCTAssertTrue(result.isPartial); XCTAssertEqual(result.observations, 1)
        let empty = ProfilePerformance.netChange(metric: .likes, samples: [], interval: october)
        XCTAssertNil(empty.value); XCTAssertEqual(empty.observations, 0)
    }
    func testPartialMetricSpecificCoverageExcludesOutsideAndFutureValues() {
        let a = date("2026-10-21T00:00:00Z"), b = date("2026-10-28T00:00:00Z")
        let samples = [Sample(date: october.end, counts: Counts(likes: 1000)), Sample(date: b, counts: Counts(likes: 12)), Sample(date: a, counts: Counts(likes: 10)), Sample(date: october.start.addingTimeInterval(-1), counts: Counts(likes: 99999)), Sample(date: october.end.addingTimeInterval(1), counts: Counts(likes: 99999))]
        let result = ProfilePerformance.netChange(metric: .likes, samples: samples, interval: october)
        XCTAssertEqual(result.value, 990); XCTAssertTrue(result.isPartial); XCTAssertEqual(result.comparisonStart, a)
        XCTAssertEqual(result.largestGap, 7 * 86400)
        XCTAssertNil(ProfilePerformance.netChange(metric: .boosts, samples: samples, interval: october).value)
    }
    func testConflictingSnapshotTimestampDoesNotPickAnArbitraryValue() {
        let samples = [Sample(date: october.start, counts: Counts(likes: 1)), Sample(date: october.start, counts: Counts(likes: 2)), Sample(date: october.end, counts: Counts(likes: 4))]
        XCTAssertNil(ProfilePerformance.netChange(metric: .likes, samples: samples, interval: october).value)
    }
    func testDailyPartialTotalCountsOnlyReturnedDaysNotMissingDays() {
        let days = (0..<20).map { CreatorDaily(date: october.start.addingTimeInterval(Double($0) * 86400), metrics: [.likes: 4]) }
        let result = ProfilePerformance.calendarMonthTotal(metric: .likes, report: report(days, start: "2026-09-21T00:00:00Z", end: "2026-10-20T00:00:00Z"), interval: october)
        XCTAssertEqual(result.value, 80); XCTAssertEqual(result.observations, 20); XCTAssertEqual(result.expectedDays, 31); XCTAssertTrue(result.isPartial)
        XCTAssertEqual(result.coverageLabel, "20/31 days · partial")
    }
    func testDailyCompleteZerosAreRealZerosAndCoverageIsMetricSpecific() {
        var days = (0..<31).map { CreatorDaily(date: october.start.addingTimeInterval(Double($0) * 86400), metrics: [.likes: 0, .prints: 1]) }
        days[2].metrics[.prints] = nil
        let likes = ProfilePerformance.calendarMonthTotal(metric: .likes, report: report(days), interval: october)
        XCTAssertEqual(likes.value, 0); XCTAssertFalse(likes.isPartial); XCTAssertEqual(likes.observations, 31)
        let prints = ProfilePerformance.calendarMonthTotal(metric: .prints, report: report(days), interval: october)
        XCTAssertEqual(prints.value, 30); XCTAssertTrue(prints.isPartial); XCTAssertEqual(prints.observations, 30)
        XCTAssertNil(ProfilePerformance.calendarMonthTotal(metric: .boosts, report: report(days), interval: october).value)
    }
    func testDuplicateServerDaysAreNotDoubleCountedAndConflictsAreUnavailable() {
        let day = CreatorDaily(date: october.start, metrics: [.likes: 2])
        XCTAssertEqual(ProfilePerformance.calendarMonthTotal(metric: .likes, report: report([day, day]), interval: october).value, 2)
        let conflict = CreatorDaily(date: october.start, metrics: [.likes: 3])
        XCTAssertNil(ProfilePerformance.calendarMonthTotal(metric: .likes, report: report([day, conflict]), interval: october).value)
    }
    func testWrongScopeUnknownFollowersAndUnloadedReportStayUnavailable() {
        let days = [CreatorDaily(date: october.start, metrics: [.likes: 10, .followers: 5])]
        XCTAssertNil(ProfilePerformance.calendarMonthTotal(metric: .likes, report: report(days, scope: .profiles), interval: october).value)
        XCTAssertNil(ProfilePerformance.calendarMonthTotal(metric: .followers, report: report(days), interval: october).value)
        XCTAssertNil(ProfilePerformance.calendarMonthTotal(metric: .likes, report: nil, interval: october).value)
    }
    func testReportedRangeAndUTCDateBoundariesAreEnforced() {
        let days = [CreatorDaily(date: october.start, metrics: [.likes: 3]), CreatorDaily(date: october.start.addingTimeInterval(3600), metrics: [.likes: 800]), CreatorDaily(date: october.end, metrics: [.likes: 900])]
        XCTAssertEqual(ProfilePerformance.calendarMonthTotal(metric: .likes, report: report(days), interval: october).value, 3)
        XCTAssertNil(ProfilePerformance.calendarMonthTotal(metric: .likes, report: report(days, start: "2026-10-02T00:00:00Z"), interval: october).value)
        let incomplete = DateInterval(start: october.start.addingTimeInterval(1), end: october.end)
        XCTAssertNil(ProfilePerformance.calendarMonthTotal(metric: .likes, report: report(days), interval: incomplete).value)
    }
}
