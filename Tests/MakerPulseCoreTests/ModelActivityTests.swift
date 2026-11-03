import XCTest
@testable import MakerPulseCore

final class ModelActivityTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_612_800)
    func calendar() -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    func design(_ id: String, likes: Int = 10, title: String? = nil) -> Design { Design(id: id, title: title ?? id, counts: Counts(likes: likes)) }
    func sample(_ ago: Double, _ likes: Int?, downloads: Int? = nil) -> Sample { Sample(date: now.addingTimeInterval(-ago), counts: Counts(likes: likes, downloads: downloads)) }
    func rank(_ designs: [Design], _ samples: [String: [Sample]], events: [Activity] = []) -> [ObservedModelActivity] {
        ModelActivity.ranked(designs: designs, samples: samples, events: events, window: .day, now: now, calendar: calendar())
    }
    func testRecentChangeOutranksLifetimePopularityAndLargerOldGrowth() {
        let result = rank([design("popular", likes: 5000), design("recent")], ["popular": [sample(800, 4500), sample(600, 5000), sample(10, 5000)], "recent": [sample(800, 9), sample(60, 10)]])
        XCTAssertEqual(result.map(\.id), ["recent", "popular"])
        XCTAssertEqual(result[0].deltas[.likes], 1)
        XCTAssertEqual(result[1].lastMetricChangeAt, now.addingTimeInterval(-600))
    }
    func testNoChangeRefreshDoesNotRenewActivityTime() {
        var history = ["a": [sample(800, 10), sample(600, 12)]]
        let first = rank([design("a")], history)[0]
        history["a"]!.append(sample(1, 12))
        let refreshed = rank([design("a")], history)[0]
        XCTAssertEqual(first.lastActivityAt, refreshed.lastActivityAt)
        XCTAssertEqual(refreshed.lastObservedAt, now.addingTimeInterval(-1))
    }
    func testFirstBaselineIsUnknownRatherThanActivityOrZeroDelta() {
        let result = rank([design("a", likes: 5000)], ["a": [sample(10, 5000)]])[0]
        XCTAssertNil(result.lastActivityAt); XCTAssertFalse(result.hasComparison)
        XCTAssertNil(result.deltas[.likes]); XCTAssertNotNil(result.baselineDate)
    }
    func testEqualActivityTimestampsUseStableTitleAndIdentifier() {
        let a = design("2", title: "Same"), b = design("1", title: "Same")
        let history = ["1": [sample(50, 1), sample(10, 2)], "2": [sample(50, 10), sample(10, 11)]]
        XCTAssertEqual(rank([a,b], history).map(\.id), ["1", "2"])
        XCTAssertEqual(rank([b,a], history).map(\.id), ["1", "2"])
    }
    func testDecreasesAndReturnToBaselineStillHaveActivity() {
        let result = rank([design("a")], ["a": [sample(600, 10), sample(300, 12), sample(60, 10)]])[0]
        XCTAssertEqual(result.deltas[.likes], 0); XCTAssertEqual(result.lastMetricChangeAt, now.addingTimeInterval(-60))
        let decrease = rank([design("a")], ["a": [sample(600, 10), sample(60, 9)]])[0]
        XCTAssertEqual(decrease.deltas[.likes], -1)
    }
    func testModelEventCanReorderWithoutMetricDeltaButUnrelatedEventsCannot() {
        let event = Activity(id: "reply", date: now.addingTimeInterval(-5), title: "Reply", detail: "", symbol: "bubble", modelID: "b")
        let unrelated = Activity(id: "wallet", date: now, title: "Points", detail: "", symbol: "star")
        let result = rank([design("a"), design("b")], ["a": [sample(500, 10), sample(50, 11)], "b": [sample(500, 10), sample(5, 10)]], events: [event,unrelated])
        XCTAssertEqual(result.map(\.id), ["b", "a"]); XCTAssertEqual(result[0].latestEvent?.id, "reply")
    }
    func testMissingFieldsAndFutureObservationsDoNotCreateGrowth() {
        let result = rank([design("a")], ["a": [sample(500, nil), sample(50, 10), sample(-10, 100)]])[0]
        XCTAssertNil(result.lastActivityAt); XCTAssertNil(result.deltas[.likes]); XCTAssertNil(result.deltas[.downloads])
    }
    func testTodayUsesLocalMidnightAcrossDST() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Chicago")!
        let date = ISO8601DateFormatter().date(from: "2026-11-01T20:00:00Z")!
        let start = ModelActivityWindow.today.interval(now: date, calendar: c).start
        XCTAssertEqual(start, ISO8601DateFormatter().date(from: "2026-11-01T05:00:00Z"))
        let samples = [Sample(date: start.addingTimeInterval(-60), counts: Counts(likes: 5)), Sample(date: start.addingTimeInterval(60), counts: Counts(likes: 6)), Sample(date: date, counts: Counts(likes: 7))]
        let result = ModelActivity.ranked(designs: [design("a")], samples: ["a": samples], events: [], window: .today, now: date, calendar: c)[0]
        XCTAssertEqual(result.deltas[.likes], 1); XCTAssertEqual(result.baselineDate, start.addingTimeInterval(60))
    }
    func testStorageAndRefreshPropagateActivityEvenWhenLikeAlertsAreDisabled() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Storage(url: root.appendingPathComponent("test.sqlite"))
        let date = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)), start = date.addingTimeInterval(-600)
        var state = LibraryState()
        let original = design("a", likes: 10)
        XCTAssertTrue(Analytics.ingestModels([original], into: &state, at: start).isEmpty)
        try await store.commit(state, samples: ["model:a": Sample(date: start, counts: original.counts)])
        let fresh = design("a", likes: 11)
        XCTAssertTrue(Analytics.ingestModels([fresh], into: &state, at: date).isEmpty)
        try await store.commit(state, samples: ["model:a": Sample(date: date, counts: fresh.counts)])
        let full = try await store.activityHistory(entity: "model:a", since: date.addingTimeInterval(-300))
        XCTAssertEqual(full.count, 2) // Includes the immediately preceding sample.
        let refreshed = ModelActivity.ranked(designs: state.models, samples: ["a": full], events: state.activity, window: .day, now: date)
        XCTAssertEqual(refreshed[0].lastMetricChangeAt, date); XCTAssertEqual(refreshed[0].deltas[.likes], 1)
        XCTAssertFalse(state.watches["a"]!.likes); XCTAssertTrue(state.watches["a"]!.enabled)
    }
}
