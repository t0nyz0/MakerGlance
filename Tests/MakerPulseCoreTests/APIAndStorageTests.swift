import Foundation
import XCTest
@testable import MakerPulseCore

private actor FakeTransport: HTTPTransport {
    var responses: [HTTPResult]
    var requests: [URLRequest] = []
    init(_ responses: [HTTPResult]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        guard !responses.isEmpty else { throw PulseError.incomplete("test fixture") }
        return responses.removeFirst()
    }
    var count: Int { requests.count }
}

final class APIAndStorageTests: XCTestCase {
    func testParsesRealFieldNamesAndNumericIDs() throws {
        let data = Data(#"{"total":1,"hits":[{"id":101,"title":"Sample storage tray","coverUrl":"https://makerworld.bblmw.com/image.jpg","likeCount":3,"downloadCount":3,"boostCnt":0,"collectionCount":1,"publishTime":"2026-10-16T02:22:29Z"}]}"#.utf8)
        let page = try APIParser.models(data)
        XCTAssertEqual(page.total, 1); XCTAssertEqual(page.items[0].id, "101")
        XCTAssertEqual(page.items[0].counts.boosts, 0); XCTAssertNotNil(page.items[0].publishedAt)
        let missing = try APIParser.models(Data(#"{"hits":[{"id":"1","title":"Test"}]}"#.utf8))
        XCTAssertNil(missing.items[0].counts.boosts)
    }
    func testSchemaChangeDoesNotSilentlyEraseData() {
        XCTAssertThrowsError(try APIParser.followers(Data(#"{"users":[]}"#.utf8)))
        XCTAssertThrowsError(try APIParser.models(Data(#"{"hits":[{"title":"Missing id"}]}"#.utf8)))
        XCTAssertThrowsError(try APIParser.profile(Data(#"{"message":"expired"}"#.utf8)))
    }
    func testProfileDownloadsAndPrintsUseAuthoritativeMakerWorldDesignFields() throws {
        let profile = try APIParser.profile(Data(#"{"uid":1,"handle":"maker","fanCount":37,"likeCount":4312,"downloadCount":2718,"collectionCount":778,"favoritesCount":3,"boostGained":16,"MWCount":{"myDesignDownloadCount":1421,"myInstanceDownloadCount":151,"myDesignPrintCount":505,"myInstancePrintCount":301}}"#.utf8))
        XCTAssertEqual(profile.counts.downloads, 1421)
        XCTAssertEqual(profile.counts.prints, 505)
        XCTAssertEqual(profile.counts.apiDownloads, 2718)
        XCTAssertEqual(profile.counts.collections, 778)
        XCTAssertEqual(profile.counts.boosts, 16)
        let unavailable = try APIParser.profile(Data(#"{"uid":1,"handle":"maker","fanCount":1,"downloadCount":2718}"#.utf8))
        XCTAssertNil(unavailable.counts.downloads, "Do not substitute a different aggregate when MWCount is absent")
        XCTAssertNil(unavailable.counts.prints)
    }
    func testV1DownloadDefinitionMigratesWithoutFalseDropOrMilestone() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MakerPulseMigration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try Storage(url: dir.appendingPathComponent("history.sqlite"))
        var old = LibraryState(); old.schema = 1; old.profileImported = true
        old.profile = Profile(id: "1", name: "Maker", handle: "maker", counts: Counts(downloads: 2718))
        old.highWater["profile:1:downloads"] = 2718
        try await store.commit(old, samples: ["profile": Sample(date: Date(), counts: old.profile!.counts)])
        var restored = try await store.load()
        XCTAssertEqual(restored.schema, 2)
        XCTAssertNil(restored.profile?.counts.downloads)
        XCTAssertEqual(restored.profile?.counts.apiDownloads, 2718)
        let samples = try await store.history(entity: "profile")
        XCTAssertNil(samples[0].counts.downloads); XCTAssertEqual(samples[0].counts.apiDownloads, 2718)
        var profile = restored.profile!; profile.counts.downloads = 1421; profile.counts.prints = 505
        XCTAssertTrue(Analytics.ingestProfile(profile, into: &restored, at: Date()).isEmpty)
        XCTAssertEqual(restored.highWater["profile:1:downloads"], 1421)
        profile.counts.downloads = 2000
        XCTAssertEqual(Analytics.ingestProfile(profile, into: &restored, at: Date()).count, 1)
    }
    func testPaginationDeduplicatesAndUsesActualPageLength() async throws {
        let output: [Design] = try await Pagination.collect(limit: 3) { offset, _ in
            let ids: [String]
            switch offset { case 0: ids = ["1", "2"]; case 2: ids = ["2", "3"]; default: ids = [] }
            return Page(items: ids.map { Design(id: $0, title: $0, counts: Counts()) }, total: 3)
        }
        XCTAssertEqual(output.map(\.id), ["1", "2", "3"])
    }
    func testPaginationRejectsRepeatedAndIncompletePages() async {
        do {
            let _: [Design] = try await Pagination.collect { _, _ in Page(items: [Design(id: "1", title: "1", counts: Counts())], total: 2) }
            XCTFail("A repeated page must fail")
        } catch { XCTAssertTrue(error is PulseError) }
        do {
            let _: [Follower] = try await Pagination.collect { _, _ in Page(items: [], total: 37) }
            XCTFail("A partial crawl must fail")
        } catch { XCTAssertTrue(error is PulseError) }
    }
    func test429BackoffAndLiveRouteWithoutCredentials() async throws {
        let payload = Data(#"{"uid":42,"handle":"t0nyz","name":"t0nyz","fanCount":37,"likeCount":4312}"#.utf8)
        let fake = FakeTransport([HTTPResult(data: Data(), status: 429, headers: ["retry-after": "0"]), HTTPResult(data: payload, status: 200)])
        let api = MakerWorldAPI(transport: fake, minimumInterval: 0)
        let profile = try await api.profile(userID: "42")
        XCTAssertEqual(profile.counts.followers, 37)
        let count = await fake.count; XCTAssertEqual(count, 2)
        let requests = await fake.requests
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(requests[0].url?.path, "/v1/design-user-service/user/profile/42")
    }
    func testRetryAfterDateAndCap() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(MakerWorldAPI.retryDelay(header: "Thu, 01 Jan 1970 00:00:30 GMT", attempt: 0, now: date), 30)
        XCTAssertEqual(MakerWorldAPI.retryDelay(header: "9999", attempt: 0), 300)
        XCTAssertEqual(MakerWorldAPI.retryDelay(header: "-1", attempt: 0), 0)
    }
    func testSavedSessionIsOnlyUsedAfterPublicDenial() async throws {
        let data = Data(#"{"uid":1,"handle":"maker","fanCount":1}"#.utf8)
        let fake = FakeTransport([HTTPResult(data: Data(), status: 401), HTTPResult(data: data, status: 200)])
        let api = MakerWorldAPI(transport: fake, minimumInterval: 0)
        await api.useSession("unit-test-session")
        _ = try await api.profile(userID: "1")
        let requests = await fake.requests
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-session")
        XCTAssertEqual(requests[1].url?.host, "api.bambulab.com")
    }
    func testHistorySamplingKeepsRecentAndLongRangeObservations() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MakerPulseHistory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try Storage(url: dir.appendingPathComponent("history.sqlite"))
        let now = Date()
        let offsets: [Double] = [30 * 86400, 10 * 86400, 1, 0]
        for (i, seconds) in offsets.enumerated() {
            try await store.commit(LibraryState(), samples: ["profile": Sample(date: now.addingTimeInterval(-seconds), counts: Counts(likes: i))])
        }
        let all = try await store.history(entity: "profile", limit: 100)
        XCTAssertEqual(all.first?.counts.likes, 0)
        XCTAssertEqual(all.last?.counts.likes, 3)
        let recent = try await store.history(entity: "profile", since: now.addingTimeInterval(-60), limit: 100)
        XCTAssertEqual(recent.count, 2)
    }
    func testSQLiteRoundTripAndRestartDeduplication() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MakerPulseTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("analytics.sqlite")
        let store = try Storage(url: url)
        var state = LibraryState(); let date = Date()
        let p = Profile(id: "1", name: "Maker", handle: "maker", counts: Counts(likes: 900))
        _ = Analytics.ingestProfile(p, into: &state, at: date)
        try await store.commit(state, samples: ["profile": Sample(date: date, counts: p.counts)])
        var next = p; next.counts.likes = 1000
        XCTAssertEqual(Analytics.ingestProfile(next, into: &state, at: date.addingTimeInterval(1)).count, 1)
        try await store.commit(state, samples: ["profile": Sample(date: date.addingTimeInterval(1), counts: next.counts)])
        let reopened = try Storage(url: url)
        var restored = try await reopened.load()
        XCTAssertTrue(Analytics.ingestProfile(next, into: &restored, at: Date()).isEmpty)
        XCTAssertEqual(restored.activity.count, 1)
        let history = try await reopened.history(entity: "profile")
        XCTAssertEqual(history.count, 2); XCTAssertEqual(history[0].counts.likes, 900)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
