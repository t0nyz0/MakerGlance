import XCTest
@testable import MakerPulseCore

final class DailyGrowthTests: XCTestCase {
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func calendar(_ zone: String) -> Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone)!; return calendar }
    func testPartialDayPositiveNegativeAndNeutralChanges() {
        let now = date("2026-10-21T18:00:00Z"), start = date("2026-10-21T13:00:00Z")
        let baseline = Sample(date: start, counts: Counts(likes: 100))
        for value in [105, 95, 100] {
            let growth = DayGrowth.evaluate(metric: .likes, baseline: baseline, current: Counts(likes: value), now: now, calendar: calendar("UTC"))
            XCTAssertEqual(growth.value, value - 100); XCTAssertTrue(growth.isPartial); XCTAssertEqual(growth.baselineDate, start)
        }
    }
    func testMidnightIsInclusiveAndYesterdayIsExcluded() {
        let now = date("2026-10-21T12:00:00Z"), midnight = date("2026-10-21T00:00:00Z")
        let growth = DayGrowth.evaluate(metric: .likes, baseline: Sample(date: midnight, counts: Counts(likes: 100)), current: Counts(likes: 101), now: now, calendar: calendar("UTC"))
        XCTAssertFalse(growth.isPartial); XCTAssertEqual(growth.value, 1)
        let yesterday = Sample(date: midnight.addingTimeInterval(-1), counts: Counts(likes: 99))
        XCTAssertNil(DayGrowth.evaluate(metric: .likes, baseline: yesterday, current: Counts(likes: 101), now: now, calendar: calendar("UTC")).value)
    }
    func testDaylightSavingDaysHaveCalendarLengths() {
        let c = calendar("America/New_York")
        let spring = DayGrowth.evaluate(metric: .likes, baseline: nil, current: Counts(), now: date("2026-03-08T16:00:00Z"), calendar: c)
        let fall = DayGrowth.evaluate(metric: .likes, baseline: nil, current: Counts(), now: date("2026-11-01T16:00:00Z"), calendar: c)
        XCTAssertEqual(spring.interval.duration, 23 * 3600); XCTAssertEqual(fall.interval.duration, 25 * 3600)
    }
    func testTimezoneChangeUsesNewDayWithoutRewritingHistory() {
        let now = date("2026-10-21T05:30:00Z"), baseline = Sample(date: date("2026-10-20T20:00:00Z"), counts: Counts(likes: 10))
        XCTAssertNil(DayGrowth.evaluate(metric: .likes, baseline: baseline, current: Counts(likes: 15), now: now, calendar: calendar("UTC")).value)
        XCTAssertEqual(DayGrowth.evaluate(metric: .likes, baseline: baseline, current: Counts(likes: 15), now: now, calendar: calendar("America/Los_Angeles")).value, 5)
    }
    func testDailyBaselinesPersistPerMetricAcrossRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MakerPulseDay-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let c = calendar("UTC"), now = Date(), day = c.dateInterval(of: .day, for: now)!
        let first = Sample(date: day.start.addingTimeInterval(10), counts: Counts(likes: 10))
        let second = Sample(date: day.start.addingTimeInterval(20), counts: Counts(likes: 12, downloads: 5))
        let path = directory.appendingPathComponent("history.sqlite")
        let store = try Storage(url: path)
        try await store.commit(LibraryState(), samples: ["model:1": first])
        try await store.commit(LibraryState(), samples: ["model:1": second])
        let reopened = try Storage(url: path)
        let likes = try await reopened.dailyBaseline(entity: "model:1", metric: .likes, now: day.start.addingTimeInterval(30), calendar: c)
        let downloads = try await reopened.dailyBaseline(entity: "model:1", metric: .downloads, now: day.start.addingTimeInterval(30), calendar: c)
        XCTAssertEqual(likes?.date, first.date); XCTAssertEqual(downloads?.date, second.date)
        let history = try await reopened.history(entity: "model:1"); XCTAssertEqual(history.count, 2)
    }
}
