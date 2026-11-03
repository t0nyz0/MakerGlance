import XCTest
@testable import MakerPulseCore

final class DemoDataTests: XCTestCase {
    func testDocumentationFixturesHaveOnlyFictionalIdentitiesAndLocalArtwork() {
        let demo = DemoData()
        XCTAssertEqual(demo.state.profile?.handle, "samplecreator")
        XCTAssertEqual(demo.state.profile?.counts.followers, demo.state.followers.count)
        XCTAssertNil(demo.state.account, "Never embed a balance, inbox or session in documentation fixtures")
        XCTAssertFalse(demo.state.preferences.notificationsEnabled)
        XCTAssertEqual(demo.state.printHistory?.accountID,"1000")
        XCTAssertTrue(demo.state.printHistory?.jobs.allSatisfy{$0.id.hasPrefix("sample-print-") && $0.cover?.hasPrefix("demo://")==true && $0.deviceName?.hasPrefix("Sample ")==true} == true)
        XCTAssertTrue(demo.state.models.allSatisfy { $0.cover?.hasPrefix("demo://") == true })
        XCTAssertTrue(demo.state.followers.allSatisfy { $0.id.hasPrefix("sample-") && $0.name.hasPrefix("Sample ") })
        XCTAssertTrue(demo.state.followers.filter(\.baseline).allSatisfy { $0.firstObservedAt == nil })
        XCTAssertTrue(demo.state.activity.allSatisfy { $0.id.hasPrefix("sample-") })
    }
    func testDemoChartsAndLatestCheckPrintIncreaseComeFromComparableSnapshots() {
        let now = Date(), demo = DemoData(now: now)
        let samples = demo.samples["model:9000"]!
        XCTAssertGreaterThan(samples.count, 100)
        XCTAssertEqual(samples.last?.counts.prints, demo.state.models.first?.counts.prints)
        let change = samples.last!.counts.prints! - samples[samples.count - 2].counts.prints!
        XCTAssertEqual(change, demo.increases["9000"]?[.prints]?.delta)
        XCTAssertTrue(demo.state.models.allSatisfy { demo.state.watches[$0.id]?.enabled == true })
    }
}
