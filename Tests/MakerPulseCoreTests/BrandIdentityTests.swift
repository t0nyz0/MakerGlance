import XCTest
@testable import MakerPulseCore

final class BrandIdentityTests: XCTestCase {
    func testBrandRenamePreservesExistingCredentialsPermissionsAndLibraryIdentity() {
        XCTAssertEqual(AppIdentity.bundleIdentifier, "com.t0nyz0.MakerPulse")
        XCTAssertEqual(AppIdentity.keychainService, "com.t0nyz0.MakerPulse")
        XCTAssertEqual(AppIdentity.supportDirectoryName, "MakerPulse")
        XCTAssertNotEqual(AppIdentity.displayName, AppIdentity.supportDirectoryName)
    }
}
