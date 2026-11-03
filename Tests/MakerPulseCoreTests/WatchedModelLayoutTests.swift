import XCTest
@testable import MakerPulseCore

final class WatchedModelLayoutTests: XCTestCase {
    func testExistingPreferencesDefaultToCardsWithoutChangingOtherSettings() throws {
        var old = Preferences(); old.textScalePercent = 150; old.pollingMinutes = 30; old.appearanceChoice = .dark
        let bytes = try JSONEncoder().encode(old)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("watchedModelLayout"))
        let restored = try JSONDecoder().decode(Preferences.self, from: bytes)
        XCTAssertEqual(restored.watchedLayout, .cards)
        XCTAssertEqual(restored.textSizePercent, 150); XCTAssertEqual(restored.pollingMinutes, 30); XCTAssertEqual(restored.appearance, .dark)
    }
    func testCompactPersistsAcrossLoadAndConcurrentObservationThenCanReturnToCards() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Storage(url: root.appendingPathComponent("fixture.sqlite"))
        var current = LibraryState(); current.preferences.watchedModelLayout = .compact; current.preferences.textScalePercent = 125
        var observation = LibraryState(); observation.models = [Design(id: "one", title: "Model", counts: Counts(prints: 7))]
        XCTAssertTrue(LocalControls.preserve(from: current, in: &observation))
        try await store.commit(observation)
        var restored = try await store.load()
        XCTAssertEqual(restored.preferences.watchedLayout, .compact); XCTAssertEqual(restored.preferences.textSizePercent, 125)
        XCTAssertEqual(restored.models, observation.models)
        restored.preferences.watchedModelLayout = .cards; try await store.commit(restored)
        let cards = try await store.load(); XCTAssertEqual(cards.preferences.watchedLayout, .cards); XCTAssertEqual(cards.models, restored.models)
    }
    func testSharedSelectionPreservesRankAndEveryObservationWhileFilteringPausedAndLimiting() {
        let now = Date(timeIntervalSince1970: 1000)
        let ranked = (0..<13).map { index in
            ObservedModelActivity(design: Design(id: "\(index)", title: "Model \(index)", counts: Counts(likes: index, prints: index * 2)),
                deltas: [.likes: -index, .prints: index], baselineDate: now.addingTimeInterval(-600), lastObservedAt: now,
                lastMetricChangeAt: now.addingTimeInterval(-Double(index)), latestEvent: index == 2 ? Activity(id: "event", date: now, title: "Comment", detail: "Actual event", symbol: "text.bubble", modelID: "2") : nil)
        }
        var pause = WatchRule(); pause.enabled = false
        let watches = ["0": pause]
        let expected = Array(ranked.dropFirst())
        let collapsed = WatchedModelSelection(ranked: ranked, watches: watches, expanded: false)
        XCTAssertEqual(collapsed.all, expected); XCTAssertEqual(collapsed.visible, Array(expected.prefix(9)))
        let expanded = WatchedModelSelection(ranked: ranked, watches: watches, expanded: true)
        XCTAssertEqual(expanded.visible, expected)
        XCTAssertEqual(expanded.visible[1].latestEvent?.id, "event")
        XCTAssertEqual(expanded.visible[1].deltas[.prints], 2); XCTAssertEqual(expanded.visible[1].deltas[.likes], -2)
        XCTAssertTrue(WatchedModelSelection(ranked: [], watches: watches, expanded: false).visible.isEmpty)
    }
}
