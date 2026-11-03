import XCTest
@testable import MakerPulseCore

final class HistoryAndMediaTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    func testSnapshotDeltasUseActualAvailablePointsWithinSharedRange() {
        let samples = [Sample(date: start.addingTimeInterval(-1), counts: Counts(likes: 1)), Sample(date: start, counts: Counts(likes: 100)), Sample(date: start.addingTimeInterval(1), counts: Counts(likes: 101, downloads: 3)), Sample(date: start.addingTimeInterval(2), counts: Counts(likes: 100, downloads: 4))]
        let interval = DateInterval(start: start, duration: 2)
        let likes = HistorySeries.snapshots(samples, metric: .likes, interval: interval)
        let downloads = HistorySeries.snapshots(samples, metric: .downloads, interval: interval)
        XCTAssertEqual(HistorySeries.delta(likes), 0); XCTAssertEqual(HistorySeries.delta(downloads), 1)
        XCTAssertEqual(downloads.first?.date, start.addingTimeInterval(1))
        XCTAssertTrue(HistorySeries.snapshots(samples, metric: .prints, interval: interval).isEmpty)
    }
    func testDailyTotalsKeepNegativeValuesExactFractionsAndExclusiveEnd() {
        let rows = [CreatorDaily(date: start, metrics: [.followers: -1, .regularPoints: Decimal(string: "0.125")!]), CreatorDaily(date: start.addingTimeInterval(1), metrics: [.followers: 2, .regularPoints: Decimal(string: "0.001")!]), CreatorDaily(date: start.addingTimeInterval(2), metrics: [.followers: 100])]
        let interval = DateInterval(start: start, duration: 2)
        XCTAssertEqual(HistorySeries.total(HistorySeries.daily(rows, metric: .followers, interval: interval)), 1)
        XCTAssertEqual(HistorySeries.total(HistorySeries.daily(rows, metric: .regularPoints, interval: interval)), Decimal(string: "0.126"))
        XCTAssertNil(HistorySeries.total(HistorySeries.daily(rows, metric: .prints, interval: interval)))
        XCTAssertNil(HistorySeries.delta([HistoryPoint(date: start, value: 100)]))
    }
    func testActualEventMediaMapsWithoutInventedIdentity() throws {
        let data = Data(#"{"hits":[{"id":1,"type":201,"from":{"name":"Example maker","handle":"example","avatar":"https://cdn.bblmw.com/avatar.jpg"},"createTime":"2026-10-21T10:00:00Z","designCommented":{"designInfo":{"id":7,"title":"Example model","cover":"https://cdn.bblmw.com/model.jpg"},"commentInfo":{"content":"Looks good"}}},{"id":2,"type":999}]}"#.utf8)
        let events = try AccountParser.events(data).items
        XCTAssertEqual(events[0].presentation?.actorName, "Example maker")
        XCTAssertEqual(events[0].presentation?.actorAvatar, "https://cdn.bblmw.com/avatar.jpg")
        XCTAssertEqual(events[0].presentation?.modelCover, "https://cdn.bblmw.com/model.jpg")
        XCTAssertEqual(events[0].presentation?.content, "Looks good")
        XCTAssertNil(events[1].presentation?.actorName); XCTAssertNil(events[1].presentation?.actorAvatar)
    }
    func testMediaEnrichmentPreservesMetricDeltaAndExistingReadState() {
        var state = LibraryState()
        state.activity = [Activity(id: "model:7:boosts:43", date: start, title: "+2 boosts", detail: "Model", symbol: "bolt", isRead: true,
            presentation: ActivityPresentation(modelTitle: "Model", metric: .boosts, delta: 2))]
        let event = AccountEvent(id: "event-1", kind: .boost, title: "Boost", detail: "Actor boosted Model", modelID: "7", metricCorrelationID: "model:7:boosts:43", presentation: ActivityPresentation(actorName: "Actor", actorAvatar: "https://cdn.bblmw.com/avatar.jpg", kind: .boost))
        XCTAssertTrue(AccountAnalytics.ingestEvents([event], into: &state, at: start).isEmpty)
        XCTAssertEqual(state.activity.count, 1); XCTAssertTrue(state.activity[0].isRead)
        XCTAssertEqual(state.activity[0].presentation?.delta, 2)
        XCTAssertEqual(state.activity[0].presentation?.actorName, "Actor")
    }
    func testImagePolicyRejectsCredentialsWrongOriginsAndInsecureURLs() {
        for url in ["http://cdn.bblmw.com/image.jpg", "https://user:password@cdn.bblmw.com/image.jpg", "https://cdn.bblmw.com.evil.example/image.jpg", "file:///tmp/image.png"] { XCTAssertNil(ImageURLPolicy.thumbnail(url)) }
        let valid = ImageURLPolicy.thumbnail("https://cdn.bblmw.com/example.gif", pixelWidth: 96)!
        let transform = URLComponents(url: valid, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        XCTAssertTrue(transform?.contains("w_96") == true); XCTAssertTrue(transform?.contains("format,png") == true)
    }
    func testOriginalFallbackPreservesSourceAndSignedPrintURLs() {
        let publicURL = "https://makerworld.bblmw.com/model/example.jpg"
        XCTAssertEqual(ImageURLPolicy.original(publicURL)?.absoluteString, publicURL)
        XCTAssertNotEqual(ImageURLPolicy.thumbnail(publicURL), ImageURLPolicy.original(publicURL))
        let signed = "https://" + ImageURLPolicy.printCoverHost + "/private.jpg?X-Amz-Signature=example%2Fvalue&X-Amz-Expires=3600"
        XCTAssertEqual(ImageURLPolicy.original(signed)?.absoluteString, signed)
        XCTAssertEqual(ImageURLPolicy.thumbnail(signed)?.absoluteString, signed)
        for unsafe in ["https://attacker.example/image.jpg", "http://makerworld.bblmw.com/image.jpg", "https://user:secret@makerworld.bblmw.com/image.jpg"] {
            XCTAssertNil(ImageURLPolicy.original(unsafe))
        }
    }
    func testDisplayGroupingKeepsLargeIntegersAndFractionalPrecision() {
        XCTAssertEqual(DisplayNumber.decimal(Decimal(string: "9007199254740993.125")!, locale: Locale(identifier: "en_US")), "9,007,199,254,740,993.125")
        XCTAssertEqual(DisplayNumber.decimal(Decimal(string: "0.00000000000000001")!, locale: Locale(identifier: "en_US")), "0.00000000000000001")
    }
    func testDisplayFormattingUsesLocaleWithoutChangingValue() {
        XCTAssertEqual(DisplayNumber.decimal(Decimal(string: "1234.125")!, locale: Locale(identifier: "de_DE")), "1.234,125")
        XCTAssertEqual(DisplayNumber.decimal(0, locale: Locale(identifier: "en_US")), "0")
    }
}
