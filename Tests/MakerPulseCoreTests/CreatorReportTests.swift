import XCTest
@testable import MakerPulseCore

private actor CreatorTransport: HTTPTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        let body = request.url?.host == "makerworld.com" ? #"<html><script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"statisticalData":{"dateList":[{"intervalVal":"2026-10-20","follower":2,"download":4}]}}}}</script></html>"# : #"{"modelList":[{"designId":7,"title":"Example","download":4}]}"#
        return HTTPResult(data: Data(body.utf8), status: 200)
    }
}
final class CreatorReportTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-10-21T03:00:00Z")!
    func testPeriodUsesInclusiveCompletedUTCDays() {
        let period = CreatorPeriod(days: 30, now: now)
        XCTAssertEqual(period.startText, "2026-09-21"); XCTAssertEqual(period.endText, "2026-10-20")
        let leap = CreatorPeriod(days: 2, now: ISO8601DateFormatter().date(from: "2024-03-01T00:00:00Z")!)
        XCTAssertEqual(leap.startText, "2024-02-28"); XCTAssertEqual(leap.endText, "2024-02-29")
        XCTAssertThrowsError(try CreatorPeriod(start: now, end: now.addingTimeInterval(-86400)))
    }
    func testModelPeriodMetricsAndPointRegionsRemainDistinct() throws {
        let report = try CreatorParser.report(Data(#"{"modelList":[{"designId":7,"title":"Example","view":100,"download":4,"point":12.125,"pointRegular":{"default":2.125,"cn":3},"pointExclusive":{"default":7,"cn":0}}]}"#.utf8), scope: .models, period: CreatorPeriod(now: now))
        XCTAssertEqual(report.rows[0].metrics[.regularPoints], Decimal(string: "2.125"))
        XCTAssertEqual(report.rows[0].metrics[.regularPointsCN], 3)
        XCTAssertNil(report.rows[0].metrics[.likes]); XCTAssertNil(report.history)
    }
    func testPrintProfilesUseOwnIdentifiersAndSchema() throws {
        let report = try CreatorParser.report(Data(#"{"instList":[{"id":8,"designId":7,"title":"Profile","designTitle":"Parent","download":3,"dailyRated":2,"pointSyncSourceExclusive":{"default":4,"cn":5}}]}"#.utf8), scope: .profiles, period: CreatorPeriod(now: now))
        XCTAssertEqual(report.rows[0].id, "8"); XCTAssertEqual(report.rows[0].modelID, "7")
        XCTAssertEqual(report.rows[0].metrics[.ratings], 2); XCTAssertEqual(report.rows[0].metrics[.exclusivePointsCN], 5)
        XCTAssertThrowsError(try CreatorParser.report(Data(#"{"modelList":[]}"#.utf8), scope: .profiles, period: CreatorPeriod(now: now)))
    }
    func testDailyHistoryFiltersPeriodWithoutInventingMissingValues() throws {
        let period = CreatorPeriod(days: 2, now: now)
        let data = Data(#"{"pageProps":{"statisticalData":{"dateList":[{"intervalVal":"2026-10-18","follower":9},{"intervalVal":"2026-10-19","follower":2},{"intervalVal":"2026-10-20","download":3}]}}}"#.utf8)
        let days = try CreatorHistoryParser.history(data, period: period)
        XCTAssertEqual(days.count, 2); XCTAssertEqual(days[0].metrics[.followers], 2)
        XCTAssertNil(days[1].metrics[.followers]); XCTAssertEqual(days[1].metrics[.downloads], 3)
    }
    func testLoginRedirectIsNeverAnEmptySuccessfulReport() throws {
        XCTAssertThrowsError(try CreatorHistoryParser.history(Data(#"{"pageProps":{"__N_REDIRECT":"/login","__N_REDIRECT_STATUS":307}}"#.utf8), period: CreatorPeriod(now: now)))
        XCTAssertThrowsError(try CreatorHistoryParser.nextData(from: Data("Browser verification required".utf8)))
    }
    func testDailyPointTotalsNeverBecomeGlobalOrChinaValues() throws {
        let data = Data(#"{"pageProps":{"statisticalData":{"dateList":[{"intervalVal":"2026-10-20","pointRegular":12,"pointFromSyncSourceRegular":{"default":8,"cn":4}}]}}}"#.utf8)
        let row = try CreatorHistoryParser.history(data, period: CreatorPeriod(days: 2, now: now))[0]
        XCTAssertEqual(row.metrics[.reportedRegularPoints], 12)
        XCTAssertEqual(row.metrics[.regularPoints], 8)
        XCTAssertEqual(row.metrics[.regularPointsCN], 4)
        XCTAssertNil(row.metrics[.exclusivePoints])
    }
    func testNativeReportsAreReadOnlyAndDoNotHardcodeBuildIDs() async throws {
        let transport = CreatorTransport()
        let client = MakerWorldAPI(transport: transport, minimumInterval: 0)
        await client.useSession("unit-test-session")
        let report = try await client.creatorReport(scope: .models, period: CreatorPeriod(days: 2, now: now))
        XCTAssertEqual(report.rows.count, 1); XCTAssertEqual(report.history?.count, 1)
        let requests = await transport.requests
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" })
        XCTAssertEqual(requests[0].url?.path, "/v1/design-user-service/my/creatortools/design/list")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-session")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(requests[1].url?.host, "makerworld.com")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Cookie"), "token=unit-test-session")
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Authorization"))
        XCTAssertFalse(requests[1].url!.path.contains("_next/data"))
    }
}
