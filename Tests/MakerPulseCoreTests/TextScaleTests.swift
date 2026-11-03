import XCTest
@testable import MakerPulseCore

final class TextScaleTests: XCTestCase {
    func testDefaultsBoundsAndMinimumReadableSize() {
        XCTAssertEqual(Preferences().textSizePercent, 100)
        XCTAssertEqual(TextScalePolicy.normalized(2), 85)
        XCTAssertEqual(TextScalePolicy.normalized(200), 150)
        XCTAssertEqual(TextScalePolicy.factor(150), 1.5)
        XCTAssertEqual(TextScalePolicy.pointSize(32, factor: 1.5), 48)
        XCTAssertEqual(TextScalePolicy.pointSize(9, factor: 0.85), 11)
    }
    func testOldPreferencesDefaultTo100WithoutChangingExistingChoices() throws {
        var original = Preferences(); original.pollingMinutes = 30; original.appearanceChoice = .dark
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertEqual(restored.textSizePercent, 100); XCTAssertEqual(restored.pollingMinutes, 30); XCTAssertEqual(restored.appearance, .dark)
    }
    func testPersistenceResetAndConcurrentRefreshPreserveTextPreference() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Storage(url: root.appendingPathComponent("fixture.sqlite"))
        var state = LibraryState(); state.preferences.textScalePercent = 150
        var observation = LibraryState()
        XCTAssertTrue(LocalControls.preserve(from: state, in: &observation))
        XCTAssertEqual(observation.preferences.textSizePercent, 150)
        try await store.commit(state)
        var loaded = try await store.load(); XCTAssertEqual(loaded.preferences.textSizePercent, 150)
        loaded.preferences.textScalePercent = TextScalePolicy.defaultPercent
        try await store.commit(loaded)
        let reset = try await store.load(); XCTAssertEqual(reset.preferences.textSizePercent, 100)
        XCTAssertEqual(reset.preferences.userID, state.preferences.userID)
    }
}
