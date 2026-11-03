import XCTest
@testable import MakerPulseCore

final class CashEstimateReasonTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    func balance(points: String, estimate: String) -> RewardBalance {
        RewardBalance(exclusivePoints: Decimal(string: points), cashEstimate: Decimal(string: estimate), currency: "USD")
    }
    func rows() -> [RewardTransaction] {
        [RewardTransaction(id: "profile", type: "instance_reward_v2", date: start.addingTimeInterval(3), regularChange: 0, exclusiveChange: Decimal(string: "3.57"), reason: "Print-profile incentive · Sample cable keeper"),
         RewardTransaction(id: "model", type: "design_reward_v2", date: start.addingTimeInterval(4), regularChange: 0, exclusiveChange: Decimal(string: "18.54"), reason: "Model creation incentive · Sample desk tray")]
    }
    func baseline() -> LibraryState {
        var state = LibraryState(); state.account = AccountState()
        // Point attribution must also work when only the estimate alert is enabled.
        state.account?.preferences.balanceNotifications = [.cashEstimate]
        _ = AccountAnalytics.ingestRewards(balance(points: "2000.125", estimate: "10.50"), transactions: [], into: &state, at: start)
        return state
    }
    func testEstimateLinksExactPointRewardsWithoutWalletEntryOrPointAlert() {
        var state = baseline()
        let alerts = AccountAnalytics.ingestRewards(balance(points: "2022.235", estimate: "11.96"), transactions: rows(), into: &state, at: start.addingTimeInterval(10))
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].title, "Cash redemption estimate +1.46 USD")
        XCTAssertTrue(alerts[0].detail.contains("+22.11 exclusive points"))
        XCTAssertTrue(alerts[0].detail.contains("Related verified rewards"))
        XCTAssertTrue(alerts[0].detail.contains("Sample cable keeper"))
        XCTAssertTrue(alerts[0].detail.contains("Sample desk tray"))
        XCTAssertTrue(alerts[0].detail.contains("same observation window"))
        XCTAssertFalse(alerts[0].detail.contains("wallet ledger"))
        XCTAssertEqual(state.account?.rewardChanges?.first?.matchedIDs.count, 2)
    }
    func testDelayedPointLedgerEnrichesSavedEstimateQuietlyAfterRestart() throws {
        var state = baseline()
        let after = balance(points: "2022.235", estimate: "11.96")
        let first = AccountAnalytics.ingestRewards(after, transactions: nil, into: &state, at: start.addingTimeInterval(10))
        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(first[0].detail.contains("Waiting for transaction"))
        state = try JSONDecoder().decode(LibraryState.self, from: JSONEncoder().encode(state))
        let later = AccountAnalytics.ingestRewards(after, transactions: rows(), into: &state, at: start.addingTimeInterval(20))
        XCTAssertTrue(later.isEmpty)
        XCTAssertEqual(state.activity.count, 1)
        XCTAssertTrue(state.activity[0].detail.contains("Related verified rewards"))
    }
    func testExistingEstimateHistoryIsRepairedWithoutChangingReadState() {
        var state = baseline()
        let after = balance(points: "2022.235", estimate: "11.96")
        _ = AccountAnalytics.ingestRewards(after, transactions: rows(), into: &state, at: start.addingTimeInterval(10))
        state.account?.rewardChanges = []
        state.activity[0].detail = "Reason unavailable from the verified wallet ledger."
        state.activity[0].isRead = true
        RewardLedger.repair(&state, history: [BalanceSample(date: start, balance: balance(points: "2000.125", estimate: "10.50")), BalanceSample(date: start.addingTimeInterval(10), balance: after)])
        XCTAssertTrue(state.activity[0].isRead)
        XCTAssertTrue(state.activity[0].detail.contains("Related verified rewards"))
        XCTAssertTrue(state.account?.rewardChanges?.first?.notificationIssued == true)
    }
    func testEstimateOnlyAndOppositeChangesDoNotClaimPointAttribution() {
        for points in ["2000.125", "1998"] {
            var state = baseline()
            let alerts = AccountAnalytics.ingestRewards(balance(points: points, estimate: "11.96"), transactions: rows(), into: &state, at: start.addingTimeInterval(10))
            XCTAssertEqual(alerts.count, 1)
            XCTAssertTrue(alerts[0].detail.contains("could not be verified"))
            XCTAssertFalse(alerts[0].detail.contains("Sample cable"))
        }
    }
    func testUnmatchedPointAmountsAndStalePointBaselineStayUnverified() {
        var state = baseline()
        let alerts = AccountAnalytics.ingestRewards(balance(points: "2022.235", estimate: "11.96"), transactions: Array(rows().prefix(1)), into: &state, at: start.addingTimeInterval(10))
        XCTAssertTrue(alerts[0].detail.contains("does not match"))
        XCTAssertFalse(alerts[0].detail.contains("Related verified rewards"))
        var stale = baseline()
        _ = AccountAnalytics.ingestRewards(RewardBalance(exclusivePoints: Decimal(string: "2000.125")), transactions: nil, into: &stale, at: start.addingTimeInterval(2))
        let unaligned = AccountAnalytics.ingestRewards(balance(points: "2022.235", estimate: "11.96"), transactions: rows(), into: &stale, at: start.addingTimeInterval(10))
        XCTAssertTrue(unaligned[0].detail.contains("could not be verified"))
    }
}
