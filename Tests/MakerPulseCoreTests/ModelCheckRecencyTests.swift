import XCTest
@testable import MakerPulseCore

private actor PillResponseTransport: HTTPTransport {
    var responses: [HTTPResult]
    init(_ responses: [HTTPResult]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard !responses.isEmpty else { throw PulseError.incomplete("fixture") }
        return responses.removeFirst()
    }
}

final class ModelCheckRecencyTests: XCTestCase {
    let time = Date(timeIntervalSince1970: 1_792_670_400)
    func design(_ likes: Int?, downloads: Int? = nil, id: String = "a") -> Design { Design(id: id, title: "Fixture", counts: Counts(likes: likes, downloads: downloads)) }
    func seeded(_ likes: Int = 100) -> ModelCheckRecency { ModelCheckRecency(baselines: ["a": [.likes: MetricObservation(value: likes, date: time)]]) }

    func testInitialAndNewModelsAreBaselinesWithoutFreshGrowth() {
        var tracker = ModelCheckRecency()
        tracker.recordSuccessful([design(5000), design(800, id: "new")], at: time)
        XCTAssertTrue(tracker.increases.values.allSatisfy(\.isEmpty))
    }
    func testLatestComparableIncreaseIsPerMetricAndTimestamped() {
        var tracker = ModelCheckRecency()
        tracker.recordSuccessful([design(100, downloads: 50)], at: time)
        tracker.recordSuccessful([design(101, downloads: 50)], at: time.addingTimeInterval(600))
        let change = tracker.increases["a"]?[.likes]
        XCTAssertEqual(change?.delta, 1); XCTAssertEqual(change?.previousCheckAt, time)
        XCTAssertEqual(change?.checkedAt, time.addingTimeInterval(600)); XCTAssertNil(tracker.increases["a"]?[.downloads])
    }
    func testSuccessfulUnchangedCheckClearsFreshWithoutResettingDailyTotals() {
        var tracker = seeded()
        let dailyBaseline = Sample(date: time, counts: Counts(likes: 100))
        let current = design(108)
        tracker.recordSuccessful([current], at: time.addingTimeInterval(600))
        XCTAssertEqual(tracker.increases["a"]?[.likes]?.delta, 8)
        tracker.recordSuccessful([current], at: time.addingTimeInterval(1200))
        XCTAssertNil(tracker.increases["a"]?[.likes])
        let growth = DayGrowth.evaluate(metric: .likes, baseline: dailyBaseline, current: current.counts, now: time.addingTimeInterval(1200))
        XCTAssertEqual(growth.value, 8)
    }
    func testMissingFieldAndMissingModelPreserveComparisonAndHighlight() {
        var tracker = seeded()
        tracker.recordSuccessful([design(101)], at: time.addingTimeInterval(600))
        let original = tracker.increases
        tracker.recordSuccessful([design(nil, downloads: 20)], at: time.addingTimeInterval(1200))
        tracker.recordSuccessful([], at: time.addingTimeInterval(1800))
        XCTAssertEqual(tracker.increases, original)
        tracker.recordSuccessful([design(102)], at: time.addingTimeInterval(2400))
        XCTAssertEqual(tracker.increases["a"]?[.likes]?.delta, 1)
        XCTAssertEqual(tracker.increases["a"]?[.likes]?.previousCheckAt, time.addingTimeInterval(600))
    }
    func testFailedAndIncompleteCrawlsDoNotAdvanceTheComparison() async {
        var tracker = seeded()
        tracker.recordSuccessful([design(101)], at: time.addingTimeInterval(600))
        let original = tracker.increases
        let partial = Data(#"{"total":2,"hits":[{"id":"a","title":"Fixture","likeCount":101}]}"#.utf8)
        let empty = Data(#"{"total":2,"hits":[]}"#.utf8)
        for responses in [[HTTPResult(data: Data(), status: 403)], [HTTPResult(data: partial, status: 200), HTTPResult(data: empty, status: 200)]] {
            let api = MakerWorldAPI(transport: PillResponseTransport(responses), minimumInterval: 0)
            do {
                let models = try await api.models(userID: "fixture")
                tracker.recordSuccessful(models, at: time.addingTimeInterval(1200))
                XCTFail("Failure must preserve the last successful comparison")
            } catch { XCTAssertEqual(tracker.increases, original) }
        }
        tracker.recordSuccessful([design(103)], at: time.addingTimeInterval(1800))
        XCTAssertEqual(tracker.increases["a"]?[.likes]?.delta, 2)
    }
    func testDecreaseClearsThenCorrectionIncreaseUsesPreviousComparableValue() {
        var tracker = seeded()
        tracker.recordSuccessful([design(102)], at: time.addingTimeInterval(600))
        tracker.recordSuccessful([design(98)], at: time.addingTimeInterval(1200))
        XCTAssertNil(tracker.increases["a"]?[.likes])
        tracker.recordSuccessful([design(99)], at: time.addingTimeInterval(1800))
        XCTAssertEqual(tracker.increases["a"]?[.likes]?.delta, 1)
    }
    func testRestartLoadsLastKnownMetricAcrossMissingFieldWithoutReplayingHighlight() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Storage(url: root.appendingPathComponent("fixture.sqlite"))
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let old = now.addingTimeInterval(-14 * 86400)
        try await store.commit(LibraryState(), samples: ["model:a": Sample(date: old, counts: Counts(likes: 108))])
        try await store.commit(LibraryState(), samples: ["model:a": Sample(date: now, counts: Counts(downloads: 20))])
        let baseline = try await store.latestMetricObservations(entity: "model:a", before: now)
        XCTAssertEqual(baseline[.likes], MetricObservation(value: 108, date: old))
        var restarted = ModelCheckRecency(baselines: ["a": baseline])
        XCTAssertTrue(restarted.increases.isEmpty)
        restarted.recordSuccessful([design(108)], at: now.addingTimeInterval(1))
        XCTAssertNil(restarted.increases["a"]?[.likes])
        restarted.recordSuccessful([design(109)], at: now.addingTimeInterval(601))
        XCTAssertEqual(restarted.increases["a"]?[.likes]?.delta, 1)
    }
    func testMidnightDoesNotResetComparisonOrInventTodayGrowth() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = calendar.startOfDay(for: time)
        var tracker = ModelCheckRecency(baselines: ["a": [.likes: MetricObservation(value: 100, date: midnight.addingTimeInterval(-300))]])
        tracker.recordSuccessful([design(101)], at: midnight.addingTimeInterval(300))
        XCTAssertEqual(tracker.increases["a"]?[.likes]?.delta, 1)
        let baseline = Sample(date: midnight.addingTimeInterval(300), counts: Counts(likes: 101))
        XCTAssertEqual(DayGrowth.evaluate(metric: .likes, baseline: baseline, current: Counts(likes: 101), now: baseline.date, calendar: calendar).value, 0)
        tracker.recordSuccessful([design(103)], at: midnight.addingTimeInterval(900))
        XCTAssertEqual(DayGrowth.evaluate(metric: .likes, baseline: baseline, current: Counts(likes: 103), now: midnight.addingTimeInterval(900), calendar: calendar).value, 2)
    }
    func testPausedModelsStillObserveMetricsWithoutGeneratingAlerts() {
        var state = LibraryState(); var rule = WatchRule(); rule.enabled = false
        state.models = [design(100)]; state.watches["a"] = rule
        var tracker = seeded()
        let events = Analytics.ingestModels([design(101)], into: &state, at: time.addingTimeInterval(600))
        tracker.recordSuccessful(state.models, at: time.addingTimeInterval(600))
        XCTAssertTrue(events.isEmpty); XCTAssertFalse(state.watches["a"]!.enabled)
        XCTAssertEqual(tracker.increases["a"]?[.likes]?.delta, 1)
    }
}
