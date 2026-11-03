import XCTest
@testable import MakerPulseCore

private let ledgerJSON = #"{"hits":[{"type":"design_reward_v2","pointTime":"2026-10-22T10:00:05Z","createTime":"2026-10-22T10:00:05Z","pointChange":10.125,"pointChangeRegular":10.125,"pointChangeExclusive":0,"designRewardV2":{"id":7,"title":"Sample planter","earningTime":"2026-10-21T00:00:00Z"}}],"total":1}"#
private actor CappedLedgerTransport: HTTPTransport {
    var calls: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> HTTPResult {
        calls.append(request)
        let row = #"{"type":"boost_exchange_point","pointChangeRegular":1,"pointChangeExclusive":0,"pointTime":"2026-10-22T10:00:05Z","extInfoBoostExchangePoint":{"designId":7,"fromUid":9,"fromUsername":"Sample maker","designTitle":"Sample model"}}"#
        return HTTPResult(data: Data(("{\"hits\":[" + row + "," + row + "],\"total\":4}").utf8), status: 200)
    }
}
final class RewardReasonTests: XCTestCase {
    let time = ISO8601DateFormatter().date(from: "2026-10-22T10:00:00Z")!
    func row(_ amount: Decimal = 1, seconds: TimeInterval = 5) -> RewardTransaction {
        var row = RewardTransaction(id: "local:sample:\(seconds):1", type: "boost_exchange_point", date: time.addingTimeInterval(seconds), regularChange: amount, exclusiveChange: 0, reason: "Received a boost · Sample planter · Sample maker", localIdentity: true)
        row.presentation = ActivityPresentation(actorName: "Sample maker", modelTitle: "Sample planter")
        return row
    }
    func state() -> LibraryState {
        var value = LibraryState(); value.preferences.userID = "1000"; value.account = AccountState()
        value.account?.preferences.balanceNotifications = [.regularPoints]
        _ = AccountAnalytics.ingestRewards(RewardBalance(regularPoints: 0), transactions: [], into: &value, at: time)
        return value
    }
    func testRealShapeDesignAndProfileIncentivesUseModelAndIncentiveDate() throws {
        let design = try AccountParser.transactions(Data(ledgerJSON.utf8), accountID: "1000").items[0]
        XCTAssertEqual(design.modelID, "7"); XCTAssertEqual(design.regularChange, Decimal(string: "10.125"))
        XCTAssertTrue(design.reason!.contains("Sample planter")); XCTAssertNotEqual(design.date, design.earnedAt); XCTAssertEqual(design.earningDayUTC, "2026-10-21")
        let profile = try AccountParser.transactions(Data(#"{"hits":[{"type":"instance_reward_v2","pointChangeRegular":0.125,"pointChangeExclusive":0.875,"pointChange":1,"instanceRewardV2":{"designId":7,"designTitle":"Sample model","instanceId":42,"instanceTitle":"Sample profile","donatedByUid":9,"donatedByUsername":"Sample maker"}}]}"#.utf8)).items[0]
        XCTAssertEqual(profile.modelID, "7"); XCTAssertEqual(profile.printProfileID, "42")
        XCTAssertTrue(profile.reason!.contains("Sample profile")); XCTAssertEqual(profile.presentation?.actorID, "9")
        XCTAssertEqual(profile.change(for: .totalPoints), 1)
    }
    func testBoostDonorSourceBonusAndUnknownTypeAreReadable() throws {
        let result = try AccountParser.transactions(Data(#"{"hits":[{"type":"boost_exchange_point","pointChangeRegular":1,"pointChangeExclusive":0,"syncSource":"CN","isExclusiveBonus":true,"extInfoBoostExchangePoint":{"designId":7,"designTitle":"Sample model","fromUid":9,"fromUsername":"Sample maker","fromUserHandle":"sample"}},{"type":"future_reward","pointChange":2,"description":"<b>Recorded explanation</b>"},{"type":"future_unknown","pointChange":3}]}"#.utf8)).items
        XCTAssertTrue(result[0].reason!.contains("CN site")); XCTAssertTrue(result[0].reason!.contains("Exclusive bonus"))
        XCTAssertEqual(result[0].presentation?.actorName, "Sample maker")
        XCTAssertEqual(result[1].reason, "Recorded explanation"); XCTAssertEqual(result[1].change(for: .totalPoints), 2)
        XCTAssertNil(result[1].change(for: .regularPoints)); XCTAssertTrue(result[2].reason!.contains("future_unknown"))
    }
    func testIdentitySurvivesDisplayMetadataEnrichmentButSeparatesDonors() throws {
        let a = try AccountParser.transactions(Data(ledgerJSON.utf8), accountID: "1000").items[0]
        let updated = ledgerJSON.replacingOccurrences(of: "Sample planter", with: "Renamed planter").replacingOccurrences(of: "\"id\":7", with: "\"coverUrl\":\"https://images.bblmw.com/sample.png\",\"id\":7")
        let b = try AccountParser.transactions(Data(updated.utf8), accountID: "1000").items[0]
        XCTAssertEqual(a.id, b.id); XCTAssertEqual(a.identitySignature, b.identitySignature)
        XCTAssertNotEqual(a.reason, b.reason)
        let textAmounts = ledgerJSON.replacingOccurrences(of: "\"pointChangeRegular\":10.125", with: "\"pointChangeRegular\":\"10.125\"")
        XCTAssertEqual(a.id, try AccountParser.transactions(Data(textAmounts.utf8), accountID: "1000").items[0].id)
        let otherDay = ledgerJSON.replacingOccurrences(of: "2026-10-21T00:00:00Z", with: "2026-10-20T00:00:00Z")
        XCTAssertNotEqual(a.id, try AccountParser.transactions(Data(otherDay.utf8), accountID: "1000").items[0].id)
    }
    func testLocalRowsReconcileExactGroupedFractionsWithoutClaimingServerIDs() {
        let result = RewardLedger.match(metric: .regularPoints, delta: Decimal(string: "0.375")!, rows: [row(Decimal(string: "0.125")!), row(Decimal(string: "0.25")!, seconds: 6)])
        XCTAssertTrue(result.matched); XCTAssertTrue(result.text.contains("2 point transactions")); XCTAssertFalse(result.text.contains("local:"))
        XCTAssertFalse(RewardLedger.match(metric: .regularPoints, delta: 1, rows: result.rows).matched)
        XCTAssertTrue(RewardLedger.match(metric: .regularPoints, delta: 1, rows: result.rows).text.contains("Sample planter"))
    }
    func testDelayedLedgerResolvesAfterRestartWithOneNotification() throws {
        var value = state()
        XCTAssertTrue(AccountAnalytics.ingestRewards(RewardBalance(regularPoints: 1), transactions: nil, into: &value, at: time.addingTimeInterval(10)).isEmpty)
        let id = value.activity[0].id
        value = try JSONDecoder().decode(LibraryState.self, from: JSONEncoder().encode(value))
        let alerts = AccountAnalytics.ingestRewards(RewardBalance(regularPoints: 1), transactions: [row()], into: &value, at: time.addingTimeInterval(20))
        XCTAssertEqual(alerts.count, 1); XCTAssertEqual(alerts[0].id, id); XCTAssertTrue(alerts[0].detail.contains("Sample planter"))
        XCTAssertTrue(AccountAnalytics.ingestRewards(RewardBalance(regularPoints: 1), transactions: [row()], into: &value, at: time.addingTimeInterval(30)).isEmpty)
        XCTAssertEqual(value.activity.count, 1)
    }
    func testTimeoutThenLateBackfillEnrichesQuietly() {
        var value = state()
        _ = AccountAnalytics.ingestRewards(RewardBalance(regularPoints: 1), transactions: [], into: &value, at: time.addingTimeInterval(10))
        let timeout = AccountAnalytics.ingestRewards(RewardBalance(regularPoints: 1), transactions: [], into: &value, at: time.addingTimeInterval(1820))
        XCTAssertEqual(timeout.count, 1); XCTAssertTrue(timeout[0].detail.contains("Waiting for transaction"))
        XCTAssertTrue(AccountAnalytics.ingestRewards(RewardBalance(regularPoints: 1), transactions: [row()], into: &value, at: time.addingTimeInterval(1900)).isEmpty)
        XCTAssertTrue(value.activity[0].detail.contains("Boost received")); XCTAssertEqual(value.activity.count, 1)
    }
    func testMissingPostingTimeAndMismatchedEntriesStayPending() {
        var value = state(); var unknown = row(); unknown.date = nil
        XCTAssertTrue(AccountAnalytics.ingestRewards(RewardBalance(regularPoints: 1), transactions: [unknown], into: &value, at: time.addingTimeInterval(10)).isEmpty)
        XCTAssertTrue(value.activity[0].detail.contains("Waiting for transaction"))
        var other = state()
        _ = AccountAnalytics.ingestRewards(RewardBalance(regularPoints: 1), transactions: [row(2)], into: &other, at: time.addingTimeInterval(10))
        XCTAssertTrue(other.activity[0].detail.contains("does not match")); XCTAssertTrue(other.activity[0].detail.contains("Boost received"))
    }
    func testCachedLegacyRowsAndMisleadingActivityAreRepairedWithoutReplay() throws {
        var value = state()
        var old = try AccountParser.transactions(Data(ledgerJSON.utf8), accountID: "1000").items[0]
        old.id = "local:1000:old:1"; old.parserVersion = nil
        value.account?.transactions = [old]; value.account?.seenTransactionIDs = [old.id]
        value.account?.lastTransactionSync = time.addingTimeInterval(8)
        value.activity = [Activity(id: "balance:regularPoints:1", date: time.addingTimeInterval(10), title: "Saved change", detail: "MakerWorld does not expose transaction IDs", symbol: "sparkles", isRead: true)]
        RewardLedger.repair(&value, history: [BalanceSample(date: time, balance: RewardBalance(regularPoints: 0)), BalanceSample(date: time.addingTimeInterval(10), balance: RewardBalance(regularPoints: Decimal(string: "10.125")))])
        XCTAssertTrue(value.activity[0].detail.contains("Sample planter")); XCTAssertTrue(value.activity[0].isRead)
        XCTAssertEqual(value.activity[0].modelID, "7"); XCTAssertTrue(value.account!.rewardChanges![0].notificationIssued)
        XCTAssertEqual(value.account?.transactions.count, 1)
    }
    func testLegacyWithoutObservationWindowDoesNotInventAttribution() {
        var value = state()
        value.activity = [Activity(id: "balance:regularPoints:1", date: time, title: "Saved", detail: "MakerWorld does not expose transaction IDs", symbol: "sparkles")]
        RewardLedger.repair(&value)
        XCTAssertFalse(value.activity[0].detail.contains("does not expose")); XCTAssertTrue(value.activity[0].detail.contains("no saved comparison window"))
    }
    func testIdenticalSameTimeBoostsAcrossIdenticalPagesRetainMultiplicity() async throws {
        let sample = row()
        let rows = try await LedgerPagination.collect(limit: 2) { _, _ in Page(items: [sample, sample], total: 4) }
        XCTAssertEqual(rows.count, 4); XCTAssertEqual(Set(rows.map(\.id)).count, 4)
        XCTAssertTrue(RewardLedger.match(metric: .regularPoints, delta: 4, rows: rows).matched)
    }
    func testNativeEndpointPaginationUsesActualReturnedCount() async throws {
        let transport = CappedLedgerTransport()
        let client = MakerWorldAPI(transport: transport, minimumInterval: 0); await client.useSession("unit-test-session")
        let rows = try await client.rewardTransactions(userID: "1000")
        XCTAssertEqual(rows.count, 4)
        let calls = await transport.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls.allSatisfy { $0.httpMethod == "GET" && $0.url?.path == "/v1/point-service/point-bill/my" })
        XCTAssertTrue(calls[1].url!.query!.contains("offset=2"))
    }
    func testDateOnlyIncentiveStaysOnItsServerUTCDay() throws {
        let json = ledgerJSON.replacingOccurrences(of: "2026-10-21T00:00:00Z", with: "2026-10-21")
        let row = try AccountParser.transactions(Data(json.utf8)).items[0]
        XCTAssertEqual(row.earningDayUTC, "2026-10-21")
        XCTAssertNotNil(row.earnedAt)
    }
    func testRepeatedMixedLocalPagesFailInsteadOfMultiplyingDifferentTransactions() async {
        let one = row(), two = row(seconds: 6)
        do {
            _ = try await LedgerPagination.collect(limit: 2) { _, _ in Page(items: [one, two], total: 4) }
            XCTFail("Mixed repeated pages must not be counted twice")
        } catch {}
    }
    func testEntryObservedDuringCrawlMatchesNextBalanceReadWithoutBeingLost() {
        var value = state()
        XCTAssertTrue(AccountAnalytics.ingestRewards(RewardBalance(regularPoints: 0), transactions: [row(seconds: 15)], into: &value, at: time.addingTimeInterval(10), ledgerObservedAt: time.addingTimeInterval(20)).isEmpty)
        let alerts = AccountAnalytics.ingestRewards(RewardBalance(regularPoints: 1), transactions: nil, into: &value, at: time.addingTimeInterval(30))
        XCTAssertEqual(alerts.count, 1); XCTAssertTrue(alerts[0].detail.contains("Boost received"))
    }
    func testTwoPendingWindowsDoNotReuseLedgerEntries() {
        var value = state()
        _ = AccountAnalytics.ingestRewards(RewardBalance(regularPoints: 1), transactions: nil, into: &value, at: time.addingTimeInterval(10))
        let alerts = AccountAnalytics.ingestRewards(RewardBalance(regularPoints: 2), transactions: [row(), row(seconds: 15)], into: &value, at: time.addingTimeInterval(20))
        XCTAssertEqual(alerts.count, 2)
        let ids = value.account!.rewardChanges!.flatMap(\.matchedIDs)
        XCTAssertEqual(Set(ids).count, 2)
    }
}
