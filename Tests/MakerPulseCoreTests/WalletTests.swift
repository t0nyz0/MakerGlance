import XCTest
@testable import MakerPulseCore

final class WalletTests: XCTestCase {
    let before = Date(timeIntervalSince1970: 1_700_000_000)
    func row(id: String = "entry-1", status: Int = 2, currency: String = "USD", amount: Decimal = 5) -> WalletTransaction {
        WalletTransaction(id: id, date: before.addingTimeInterval(1), amount: amount, currency: currency, status: status, source: 1, detailTransactionID: nil, exclusivePoints: 100)
    }
    func testActualWalletSchemaAndSeparateSummaryAmounts() throws {
        let data = Data(#"{"hits":[{"id":"entry-1","source":1,"status":2,"date":"2026-10-21T00:00:00Z","amount":"5.012345","currency":"USD","incomeDetail":{"exclusivePoint":100}}],"total":1}"#.utf8)
        let entry = try WalletParser.transactions(data).items[0]
        XCTAssertEqual(entry.amount, Decimal(string: "5.012345")); XCTAssertTrue(entry.reason.contains("100 points"))
        let summary = try AccountParser.wallet(Data(#"{"currency":"USD","remainingToTransfer":5,"pendingIncome":2,"totalIncome":12,"transferred":4,"withdrawing":1}"#.utf8), into: RewardBalance())
        XCTAssertEqual(summary.cashIncome, 12); XCTAssertEqual(summary.cashTransferred, 4); XCTAssertEqual(summary.cashWithdrawing, 1)
        XCTAssertEqual(summary.cashAvailable, 5); XCTAssertEqual(summary.cashPending, 2)
        XCTAssertThrowsError(try WalletParser.transactions(Data(#"{"hits":[{"source":1,"amount":5}]}"#.utf8)))
    }
    func testWalletBaselineQuietAndRestartDoesNotRepeatChanges() throws {
        var state = LibraryState()
        let balance = RewardBalance(cashAvailable: 0, cashPending: 0, currency: "USD")
        XCTAssertTrue(AccountAnalytics.ingestRewards(balance, transactions: [], walletTransactions: [], into: &state, at: before).isEmpty)
        let pending = RewardBalance(cashAvailable: 0, cashPending: 5, currency: "USD")
        let alerts = AccountAnalytics.ingestRewards(pending, transactions: [], walletTransactions: [row()], into: &state, at: before.addingTimeInterval(2))
        XCTAssertEqual(alerts.count, 1); XCTAssertTrue(alerts[0].detail.contains("wallet entry entry-1"))
        state = try JSONDecoder().decode(LibraryState.self, from: JSONEncoder().encode(state))
        XCTAssertTrue(AccountAnalytics.ingestRewards(pending, transactions: [], walletTransactions: [row()], into: &state, at: before.addingTimeInterval(3)).isEmpty)
    }
    func testPendingCompletionExplainsBothBalanceDirectionsByStableEntry() {
        let pending = row(), completed = row(status: 1)
        for (metric, delta) in [(RewardMetric.cashPending, Decimal(-5)), (.cashAvailable, Decimal(5))] {
            let reason = WalletAnalytics.reconciledReason(metric: metric, delta: delta, currency: "USD", previous: [pending], current: [completed], observedBefore: before.addingTimeInterval(2), now: before.addingTimeInterval(3))
            XCTAssertTrue(reason.contains("entry-1")); XCTAssertTrue(reason.contains("Pending → Completed"))
        }
    }
    func testNoGuessForWrongCurrencyUnknownTimingOrUnmatchedCashEstimate() {
        for (metric, delta, entry) in [(RewardMetric.cashAvailable, Decimal(5), row(status: 1, currency: "EUR")), (.cashAvailable, Decimal(6), row(status: 1)), (.cashEstimate, Decimal(5), row(status: 1))] {
            let reason = WalletAnalytics.reconciledReason(metric: metric, delta: delta, currency: "USD", previous: [], current: [entry], observedBefore: before, now: before.addingTimeInterval(3))
            XCTAssertTrue(reason.contains("Reason unavailable"))
        }
        let reason = WalletAnalytics.reconciledReason(metric: .cashAvailable, delta: 5, currency: "USD", previous: [], current: [row(status: 1)], observedBefore: before.addingTimeInterval(2), now: before.addingTimeInterval(3))
        XCTAssertTrue(reason.contains("Reason unavailable"))
    }
    func testCancellationAndPartialFeedFailurePreserveHistoryWithoutFalseReasons() {
        let canceled = row(status: 3)
        XCTAssertTrue(WalletAnalytics.reconciledReason(metric: .cashPending, delta: -5, currency: "USD", previous: [row()], current: [canceled], observedBefore: before, now: before.addingTimeInterval(3)).contains("Canceled / refunded"))
        var state = LibraryState()
        _ = AccountAnalytics.ingestRewards(RewardBalance(cashPending: 5, currency: "USD"), transactions: [], walletTransactions: [row()], into: &state, at: before)
        let alerts = AccountAnalytics.ingestRewards(RewardBalance(cashPending: 4, currency: "USD"), transactions: nil, into: &state, at: before.addingTimeInterval(2))
        XCTAssertEqual(state.account?.walletTransactions?.count, 1); XCTAssertTrue(alerts[0].detail.contains("Reason unavailable"))
    }
}
