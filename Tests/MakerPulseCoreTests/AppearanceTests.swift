import XCTest
@testable import MakerPulseCore

final class AppearanceTests: XCTestCase {
    func testExistingPreferencesDefaultToSystemWithoutMigrationLoss() throws {
        var dictionary = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Preferences())) as! [String: Any]
        dictionary.removeValue(forKey: "appearanceChoice")
        dictionary["pollingMinutes"] = 30
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: dictionary))
        XCTAssertEqual(restored.appearance, .system); XCTAssertEqual(restored.pollingMinutes, 30)
    }
    func testAllAppearanceChoicesPersistAcrossSQLiteReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MakerPulseAppearance-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite")
        for choice in AppearanceChoice.allCases {
            var state = LibraryState(); state.preferences.appearanceChoice = choice; state.preferences.pollingMinutes = 30
            let first = try Storage(url: url); try await first.commit(state)
            let reopened = try Storage(url: url); let restored = try await reopened.load()
            XCTAssertEqual(restored.preferences.appearance, choice)
            XCTAssertEqual(restored.preferences.pollingMinutes, 30)
        }
    }
}
