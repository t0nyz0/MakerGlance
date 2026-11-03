import XCTest
@testable import MakerPulseCore

private actor SessionSpy: SessionBackend, SessionStorage {
    var calls: [String] = []
    let userID: String
    let rejectValidation: Bool
    let rejectStorage: Bool
    init(userID: String = "42", rejectValidation: Bool = false, rejectStorage: Bool = false) {
        self.userID = userID; self.rejectValidation = rejectValidation; self.rejectStorage = rejectStorage
    }
    func validate(token: String) throws -> Profile {
        calls.append("validate")
        if rejectValidation { throw PulseError.authentication }
        return Profile(id: userID, name: "Test", handle: "example", counts: Counts())
    }
    func saveSession(_ token: String) throws {
        calls.append("save")
        if rejectStorage { throw PulseError.database("Synthetic storage failure") }
    }
    func useSession(_ token: String?) { calls.append("activate") }
    func stage(_ value: ConnectionStage) { calls.append(value.rawValue) }
}

final class AuthenticationTests: XCTestCase {
    func testOpaqueTokensAndPastedPrefixes() throws {
        for input in ["unit-test-session", "  unit-test-session\n", "Bearer unit-test-session", "token=\"unit-test-session\"", "'Bearer unit-test-session'"] {
            XCTAssertEqual(try SessionInput.normalize(input), "unit-test-session")
        }
        for input in ["", " \n", "Cookie: token=x; other=y", "abc\ndef", "abc def", "abc\u{0}def"] {
            XCTAssertThrowsError(try SessionInput.normalize(input))
        }
    }
    func testValidatesAndStoresBeforeActivatingWithImmediateProgress() async throws {
        let spy = SessionSpy()
        _ = try await SessionConnection.connect(raw: "Bearer unit-test-session", expectedUserID: "42", backend: spy, storage: spy) { await spy.stage($0) }
        let calls = await spy.calls
        XCTAssertEqual(calls, ["validating", "validate", "saving", "save", "activate", "connected"])
    }
    func testRejectedOrWrongAccountNeverSavesOrActivates() async {
        for spy in [SessionSpy(rejectValidation: true), SessionSpy(userID: "other")] {
            do { _ = try await SessionConnection.connect(raw: "unit-test-session", expectedUserID: "42", backend: spy, storage: spy); XCTFail("Should reject") } catch {}
            let calls = await spy.calls
            XCTAssertEqual(calls, ["validate"])
        }
    }
    func testStorageFailureNeverActivatesSession() async {
        let spy = SessionSpy(rejectStorage: true)
        do { _ = try await SessionConnection.connect(raw: "unit-test-session", expectedUserID: "42", backend: spy, storage: spy); XCTFail("Should reject") } catch {}
        let calls = await spy.calls
        XCTAssertEqual(calls, ["validate", "save"])
    }
    func testFirstConnectionIdentifiesTheAccountButRejectsInvalidServerIDs() async throws {
        let spy = SessionSpy()
        let profile = try await SessionConnection.connect(raw: "unit-test-session", expectedUserID: "", backend: spy, storage: spy)
        XCTAssertEqual(profile.id, "42")
        let invalid = SessionSpy(userID: "invalid-id")
        do { _ = try await SessionConnection.connect(raw: "unit-test-session", expectedUserID: "", backend: invalid, storage: invalid); XCTFail("Must reject unsupported identity") } catch {}
        let calls = await invalid.calls; XCTAssertEqual(calls, ["validate"])
    }
    func testSchemaDiagnosticsContainFieldNamesWithoutPrivateValues() {
        let report = SchemaDiagnostics.describe(Data(#"{"total":2,"hits":[{"id":"private-transaction","reason":"private-reason","pointChangeExclusive":7123.456}]}"#.utf8))
        XCTAssertTrue(report.contains("pointChangeExclusive"))
        for privateValue in ["private-transaction", "private-reason", "7123.456"] { XCTAssertFalse(report.contains(privateValue)) }
    }
}
