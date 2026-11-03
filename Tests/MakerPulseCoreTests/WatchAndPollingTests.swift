import XCTest
@testable import MakerPulseCore

final class WatchAndPollingTests: XCTestCase {
    func testAllWatchedDefaultAndExplicitPauseSurviveRefreshAndRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MakerPulseWatches-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite")
        var state = LibraryState()
        let original = [Design(id: "a", title: "One", counts: Counts(boosts: 1)), Design(id: "b", title: "Two", counts: Counts(boosts: 2))]
        _ = Analytics.ingestModels(original, into: &state, at: Date())
        XCTAssertEqual(ModelWatchFilter.watched.count(state.models, watches: state.watches), 2)
        state.watches["a"]?.enabled = false; state.preferences.modelFilter = .paused
        let store = try Storage(url: url); try await store.commit(state)
        let reopened = try Storage(url: url); state = try await reopened.load()
        let changed = [Design(id: "a", title: "One", counts: Counts(boosts: 3)), Design(id: "b", title: "Two", counts: Counts(boosts: 4)), Design(id: "c", title: "New", counts: Counts(boosts: 5))]
        let alerts = Analytics.ingestModels(changed, into: &state, at: Date())
        XCTAssertEqual(alerts.map(\.modelID), ["b"])
        XCTAssertEqual(ModelWatchFilter.paused.count(state.models, watches: state.watches), 1)
        XCTAssertEqual(ModelWatchFilter.watched.count(state.models, watches: state.watches), 2)
        XCTAssertEqual(state.preferences.modelFilter, .paused)
        XCTAssertTrue(state.watches["c"]!.enabled)
        state.watches["a"]?.enabled = true
        XCTAssertEqual(ModelWatchFilter.paused.count(state.models, watches: state.watches), 0)
        XCTAssertEqual(ModelWatchFilter.all.count(state.models, watches: state.watches), 3)
    }
    func testRemoteBoostPreferencesRespectPausedModelWhileCommentsRemainSeparate() {
        var state = LibraryState(); state.account = AccountState(); state.account?.eventsImported = true
        state.account?.preferences.eventNotifications = [.boost, .comment]
        var paused = WatchRule(); paused.enabled = false; state.watches["a"] = paused
        let events = [AccountEvent(id: "boost", kind: .boost, title: "Boost", detail: "Test", modelID: "a"), AccountEvent(id: "comment", kind: .comment, title: "Comment", detail: "Test", modelID: "a")]
        let alerts = AccountAnalytics.ingestEvents(events, into: &state, at: Date())
        XCTAssertEqual(alerts.map(\.id), ["remote:comment"])
    }
    func testExpandedPollingOptionsAndValidation() {
        for minutes in [5, 10, 15, 30, 60, 120, 360, 720] { XCTAssertTrue(PollingPolicy.presets.contains(minutes)) }
        XCTAssertFalse(PollingPolicy.valid(4)); XCTAssertFalse(PollingPolicy.valid(1441))
        XCTAssertTrue(PollingPolicy.valid(17)); XCTAssertEqual(PollingPolicy.title(120), "Every 2 hours")
    }
    func testPollingDelayHasBoundedPositiveJitterAndChangesImmediately() {
        XCTAssertEqual(PollingPolicy.delay(minutes: 10, jitterUnit: 0), 600)
        XCTAssertEqual(PollingPolicy.delay(minutes: 10, jitterUnit: 1), 612)
        XCTAssertEqual(PollingPolicy.delay(minutes: 120, jitterUnit: 1), 7230)
        XCTAssertLessThan(PollingPolicy.delay(minutes: 5, jitterUnit: 1), PollingPolicy.delay(minutes: 10, jitterUnit: 0))
    }
}
