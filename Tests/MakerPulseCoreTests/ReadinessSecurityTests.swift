import XCTest
@testable import MakerPulseCore

final class ReadinessSecurityTests: XCTestCase {
    func testHTTPSRedirectsRequireTheSameEffectiveOrigin() {
        let origin = URL(string: "https://api.example.com/start")!
        for permitted in ["https://api.example.com/end", "https://API.EXAMPLE.COM:443/end"] {
            XCTAssertTrue(NetworkOrigin.permitsRedirect(from: origin, to: URL(string: permitted)))
        }
        for rejected in ["http://api.example.com/end", "https://api.example.com:8443/end", "https://other.example.com/end", "https://api.example.com.attacker.invalid/end", "https://user:pass@api.example.com/end"] {
            XCTAssertFalse(NetworkOrigin.permitsRedirect(from: origin, to: URL(string: rejected)))
        }
        XCTAssertFalse(NetworkOrigin.permitsRedirect(from: nil, to: origin))
        XCTAssertFalse(NetworkOrigin.permitsRedirect(from: URL(string: "http://api.example.com"), to: origin))
        XCTAssertNil(ImageURLPolicy.thumbnail("https://makerworld.bblmw.com:8443/image.jpg"))
        XCTAssertNotNil(ImageURLPolicy.thumbnail("https://makerworld.bblmw.com:443/image.jpg"))
    }
    func testNewLibraryContainsNoCreatorDefaultsAndSetupPreservesPreferences() throws {
        var state = LibraryState(); state.preferences.textScalePercent = 125; state.preferences.watchedModelLayout = .compact
        XCTAssertTrue(state.preferences.userID.isEmpty); XCTAssertTrue(state.preferences.handle.isEmpty)
        let profile = Profile(id: "42", name: "Sample creator", handle: "samplecreator", counts: Counts(likes: 12))
        try ProfileSetup.adopt(profile, into: &state)
        XCTAssertEqual(state.preferences.userID, "42"); XCTAssertEqual(state.preferences.handle, "samplecreator")
        XCTAssertEqual(state.preferences.textSizePercent, 125); XCTAssertEqual(state.preferences.watchedLayout, .compact)
        XCTAssertTrue(state.profileImported); XCTAssertTrue(state.activity.isEmpty)
        XCTAssertThrowsError(try ProfileSetup.adopt(profile, into: &state), "Never replace an existing library's account")
        for invalid in ["", "abc", "../42", "٤٢", String(repeating: "1", count: 33)] { XCTAssertFalse(ProfileSetup.validID(invalid)) }
    }
    func testSetupRefusesExistingAnalyticsWithoutAProfile() {
        var state = LibraryState(); state.models = [Design(id: "101", title: "Sample model", counts: Counts())]
        XCTAssertThrowsError(try ProfileSetup.adopt(Profile(id: "42", name: "Sample", handle: "sample", counts: Counts()), into: &state))
        XCTAssertEqual(state.models.count, 1); XCTAssertTrue(state.preferences.userID.isEmpty)
    }
    func testDatabaseAndSidecarsHavePrivateFilePermissions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.sqlite")
        let store = try Storage(url: url); try await store.commit(LibraryState())
        for path in [url.path, url.path + "-wal", url.path + "-shm"] where FileManager.default.fileExists(atPath: path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }
}
