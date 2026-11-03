import XCTest
@testable import MakerPulseCore

private actor ReadOnlyTransport: HTTPTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        return HTTPResult(data: Data(#"{"hits":[],"total":0}"#.utf8), status: 200)
    }
}

final class AccountTests: XCTestCase {
    func testPrinterUpdatesAreOptInAndNotReplayed() throws {
        var state = LibraryState()
        let event = AccountEvent(id: "print-1", kind: .device, title: "Printer update", detail: "Finished")
        XCTAssertTrue(AccountAnalytics.ingestEvents([event], into: &state, at: Date()).isEmpty)
        XCTAssertTrue(state.activity.isEmpty)
        state.account?.preferences.eventNotifications.insert(.device)
        XCTAssertTrue(AccountAnalytics.ingestEvents([event], into: &state, at: Date()).isEmpty)
        let next = AccountEvent(id: "print-2", kind: .device, title: "Printer update", detail: "Finished")
        XCTAssertEqual(AccountAnalytics.ingestEvents([next], into: &state, at: Date()).count, 1)
    }
    func testDismissalSurvivesInFlightObservationAndRestart() throws {
        var current = LibraryState()
        let item = Activity(id: "remote:a", date: Date(), title: "Comment", detail: "Example", symbol: "bell")
        var observation = current; observation.activity = [item]
        current.dismissedActivityIDs = [item.id]
        XCTAssertTrue(LocalControls.preserve(from: current, in: &observation))
        XCTAssertTrue(observation.activity.isEmpty)
        let restored = try JSONDecoder().decode(LibraryState.self, from: JSONEncoder().encode(observation))
        XCTAssertTrue(restored.dismissedActivityIDs?.contains(item.id) == true)
    }

    func testKnownCommentsRepliesMentionsAndBoostCorrelation() throws {
        let data = Data(#"{"hits":[{"id":1,"type":201,"from":{"name":"Maker"},"createTime":"2026-10-21T10:00:00Z","designCommented":{"designInfo":{"id":7,"title":"Example"},"commentInfo":{"content":"<b>Great</b> print"}}},{"id":2,"type":202,"commentReplied":{}},{"id":3,"type":261,"commentMentioned":{}},{"id":4,"type":503,"pointDesignBoosted":{"designId":7,"designTitle":"Example","designBoostCnt":43}}],"total":4}"#.utf8)
        let events = try AccountParser.events(data).items
        XCTAssertEqual(events.map(\.kind), [.comment, .reply, .mention, .boost])
        XCTAssertTrue(events[0].detail.contains("Great print")); XCTAssertFalse(events[0].detail.contains("<b>"))
        XCTAssertEqual(events[3].metricCorrelationID, "model:7:boosts:43")
        XCTAssertNil(events[1].occurredAt)
    }
    func testInboxBaselineAndRestartDeduplication() throws {
        var state = LibraryState(); let date = Date()
        let first = AccountEvent(id: "a", kind: .comment, title: "Comment", detail: "Example")
        XCTAssertTrue(AccountAnalytics.ingestEvents([first, first], into: &state, at: date).isEmpty)
        XCTAssertEqual(state.activity.count, 1); XCTAssertTrue(state.activity[0].isRead)
        state = try JSONDecoder().decode(LibraryState.self, from: JSONEncoder().encode(state))
        XCTAssertTrue(AccountAnalytics.ingestEvents([first], into: &state, at: date).isEmpty)
        let next = AccountEvent(id: "b", kind: .reply, title: "Reply", detail: "Example")
        XCTAssertEqual(AccountAnalytics.ingestEvents([first, next], into: &state, at: date).count, 1)
    }
    func testBoostEventEnrichesMatchingMetricAlert() {
        var state = LibraryState(); let date = Date()
        state.activity = [Activity(id: "model:7:boosts:43", date: date, title: "+1 boost", detail: "Model", symbol: "bolt")]
        let event = AccountEvent(id: "a", kind: .boost, title: "Boost", detail: "Example boosted by Maker", modelID: "7", metricCorrelationID: "model:7:boosts:43")
        XCTAssertTrue(AccountAnalytics.ingestEvents([event], into: &state, at: date).isEmpty)
        XCTAssertEqual(state.activity.count, 1); XCTAssertTrue(state.activity[0].detail.contains("Maker"))
    }
    func testPrivateInboxOnlyIssuesGetRequestsToVerifiedCategories() async throws {
        let transport = ReadOnlyTransport(); let api = MakerWorldAPI(transport: transport, minimumInterval: 0)
        await api.useSession("unit-test-session")
        let events = try await api.accountEvents(); XCTAssertTrue(events.isEmpty)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 6)
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" && $0.url?.path == "/v1/user-service/my/messages" })
        XCTAssertFalse(requests.contains { $0.url!.path.contains("/read") })
    }
    func testDecimalBalancesAndServerCashEstimateStayDistinct() throws {
        let balance = try AccountParser.points(Data(#"{"totalRegularPoint":9007199254740993.125,"totalExclusivePoint":"112.875"}"#.utf8))
        XCTAssertEqual(balance.regularPoints, Decimal(string: "9007199254740993.125"))
        XCTAssertEqual(balance.totalPoints, Decimal(string: "9007199254741106"))
        let cash = try AccountParser.cashProgress(Data(#"{"canRedeemAmount":"17.03","currency":"USD"}"#.utf8), into: balance)
        XCTAssertEqual(cash.cashEstimate, Decimal(string: "17.03")); XCTAssertNil(cash.cashAvailable)
        let wallet = try AccountParser.wallet(Data(#"{"remainingToTransfer":"8.15","pendingIncome":"2.10","currency":"USD"}"#.utf8), into: cash)
        XCTAssertEqual(wallet.cashEstimate, Decimal(string: "17.03")); XCTAssertEqual(wallet.cashAvailable, Decimal(string: "8.15")); XCTAssertEqual(wallet.cashPending, Decimal(string: "2.10"))
        let otherCurrency = try AccountParser.wallet(Data(#"{"remainingToTransfer":1,"currency":"EUR"}"#.utf8), into: cash)
        XCTAssertEqual(otherCurrency.currency(for: .cashAvailable), "EUR")
        XCTAssertEqual(otherCurrency.currency(for: .cashEstimate), "USD")
    }
    func testBalanceIncreasesDecreasesAndNoRepeatAfterRestart() throws {
        var state = LibraryState(); let date = Date()
        XCTAssertTrue(AccountAnalytics.ingestRewards(RewardBalance(exclusivePoints: 100), transactions: [], into: &state, at: date).isEmpty)
        let tx = RewardTransaction(id: "tx-1", type: "design_reward_v2", date: date.addingTimeInterval(1), regularChange: 0, exclusiveChange: Decimal(string: "10.125"), reason: "Model incentive")
        let increased = RewardBalance(exclusivePoints: Decimal(string: "110.125"))
        let alerts = AccountAnalytics.ingestRewards(increased, transactions: [tx], into: &state, at: date.addingTimeInterval(2))
        XCTAssertEqual(alerts.count, 1); XCTAssertTrue(alerts[0].title.contains("+10.125")); XCTAssertTrue(alerts[0].detail.contains("Model incentive"))
        state = try JSONDecoder().decode(LibraryState.self, from: JSONEncoder().encode(state))
        XCTAssertTrue(AccountAnalytics.ingestRewards(increased, transactions: [tx], into: &state, at: date.addingTimeInterval(3)).isEmpty)
        let decreased = AccountAnalytics.ingestRewards(RewardBalance(exclusivePoints: 99), transactions: [], into: &state, at: date.addingTimeInterval(4))
        XCTAssertTrue(decreased.isEmpty, "Unmatched points wait for a ledger before notifying")
        let timeout = AccountAnalytics.ingestRewards(RewardBalance(exclusivePoints: 99), transactions: [], into: &state, at: date.addingTimeInterval(1810))
        XCTAssertEqual(timeout.count, 1); XCTAssertTrue(timeout[0].title.contains("-11.125")); XCTAssertTrue(timeout[0].detail.contains("Waiting for transaction"))
    }
    func testReasonsRequireExactDelta() {
        let tx = RewardTransaction(id: "stable-1", type: "example", date: Date(), regularChange: 0, exclusiveChange: 12, reason: "Verified description")
        XCTAssertTrue(AccountAnalytics.reconciledReason(for: .exclusivePoints, delta: 13, transactions: [tx]).contains("does not match"))
        XCTAssertTrue(AccountAnalytics.reconciledReason(for: .exclusivePoints, delta: 12, transactions: [tx]).contains("Verified description"))
        XCTAssertTrue(AccountAnalytics.reconciledReason(for: .cashEstimate, delta: 12, transactions: [tx]).contains("Reason unavailable"))
    }
    func testTransactionsWithoutIDsUseExplicitLocalFingerprints() throws {
        let missing = try AccountParser.transactions(Data(#"{"hits":[{"type":"unknown","pointChangeExclusive":1}]}"#.utf8))
        XCTAssertNil(missing.items[0].serverID)
        XCTAssertTrue(missing.items[0].id.hasPrefix("local:"))
        let page = try AccountParser.transactions(Data(#"{"hits":[{"id":"1","type":"unknown","pointChangeRegular":"0.125","pointChangeExclusive":"-0.001"}]}"#.utf8))
        XCTAssertTrue(page.items[0].reason!.contains("unknown")); XCTAssertNil(page.items[0].date)
        XCTAssertEqual(page.items[0].exclusiveChange, Decimal(string: "-0.001"))
    }
    func testLocalLedgerReasonsDoNotClaimServerIDs() throws {
        let data = Data(#"{"hits":[{"type":"boost_exchange_point","pointChangeRegular":0,"pointChangeExclusive":1,"extInfoBoostExchangePoint":{"designTitle":"Test"}}]}"#.utf8)
        let rows = try AccountParser.transactions(data).items
        XCTAssertTrue(rows[0].reason!.contains("Received a boost"))
        let reason = AccountAnalytics.reconciledReason(for: .exclusivePoints, delta: 1, transactions: rows)
        XCTAssertTrue(reason.contains("Boost received")); XCTAssertFalse(reason.contains("local:"))
    }
    func testFingerprintIgnoresObjectKeyOrderAndPreservesExactFractions() throws {
        let a = try AccountParser.transactions(Data(#"{"hits":[{"type":"unknown","pointChangeExclusive":0.00000000000000001,"pointChangeRegular":2}]}"#.utf8)).items[0]
        let b = try AccountParser.transactions(Data(#"{"hits":[{"pointChangeRegular":2,"pointChangeExclusive":0.00000000000000001,"type":"unknown"}]}"#.utf8)).items[0]
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(a.exclusiveChange, Decimal(string: "0.00000000000000001"))
    }
    func testLedgerPaginationPreservesIdenticalRowsWithoutInventingServerIDs() async throws {
        let row = RewardTransaction(id: "local:test", type: "unknown", date: nil, regularChange: 0, exclusiveChange: 1, reason: nil, localIdentity: true)
        let other = RewardTransaction(id: "local:other", type: "unknown", date: nil, regularChange: 0, exclusiveChange: 2, reason: nil, localIdentity: true)
        let rows = try await LedgerPagination.collect(limit: 2) { offset, _ in
            offset == 0 ? Page(items: [row, row], total: 3) : Page(items: [other], total: 3)
        }
        XCTAssertEqual(rows.count, 3); XCTAssertEqual(Set(rows.map(\.id)).count, 3)
        XCTAssertTrue(rows.allSatisfy { $0.serverID == nil })
        var state = LibraryState()
        XCTAssertTrue(AccountAnalytics.ingestRewards(RewardBalance(exclusivePoints: 4), transactions: rows, into: &state, at: Date()).isEmpty)
        state = try JSONDecoder().decode(LibraryState.self, from: JSONEncoder().encode(state))
        _ = AccountAnalytics.ingestRewards(RewardBalance(exclusivePoints: 4), transactions: rows, into: &state, at: Date())
        XCTAssertEqual(state.account?.transactions.count, 3)
    }
    func testLedgerRejectsRepeatedAndIncompletePages() async {
        let row = RewardTransaction(id: "server-test", type: "unknown", date: nil, regularChange: 0, exclusiveChange: 1, reason: nil)
        do { _ = try await LedgerPagination.collect { _, _ in Page(items: [row], total: 3) }; XCTFail("Repeated server page must fail") } catch {}
        do { _ = try await LedgerPagination.collect { offset, _ in Page(items: offset == 0 ? [row] : [], total: 3) }; XCTFail("Incomplete page must fail") } catch {}
    }
    func testPartialBalanceRefreshPreservesLastVerifiedValueAndTimestamp() {
        var state = LibraryState(); let first = Date()
        _ = AccountAnalytics.ingestRewards(RewardBalance(exclusivePoints: 100, cashEstimate: 5, currency: "USD"), transactions: [], into: &state, at: first)
        _ = AccountAnalytics.ingestRewards(RewardBalance(exclusivePoints: 110), transactions: [], into: &state, at: first.addingTimeInterval(10))
        XCTAssertEqual(state.account?.balance?.balance.cashEstimate, 5)
        XCTAssertEqual(state.account?.balanceDates[.cashEstimate], first)
        XCTAssertEqual(state.account?.balanceDates[.exclusivePoints], first.addingTimeInterval(10))
    }
    func testControlsEditedDuringObservationSaveSurviveWithoutLosingFreshData() {
        var current = LibraryState(), observation = LibraryState()
        current.preferences.pollingMinutes = 30
        var paused = WatchRule(); paused.enabled = false; current.watches["old"] = paused
        current.account = AccountState(); current.account?.preferences.eventNotifications = [.mention]
        current.activity = [Activity(id: "a", date: Date(), title: "Test", detail: "Test", symbol: "bell", isRead: true)]
        observation.watches["new"] = WatchRule()
        observation.account = AccountState(); observation.account?.balance = BalanceSample(date: Date(), balance: RewardBalance(exclusivePoints: 123))
        observation.activity = [Activity(id: "a", date: Date(), title: "Fresh", detail: "Fresh", symbol: "bell")]
        XCTAssertTrue(LocalControls.preserve(from: current, in: &observation))
        XCTAssertEqual(observation.preferences.pollingMinutes, 30)
        XCTAssertFalse(observation.watches["old"]!.enabled); XCTAssertTrue(observation.watches["new"]!.enabled)
        XCTAssertEqual(observation.account?.preferences.eventNotifications, [.mention])
        XCTAssertEqual(observation.account?.balance?.balance.exclusivePoints, 123)
        XCTAssertTrue(observation.activity[0].isRead); XCTAssertEqual(observation.activity[0].title, "Fresh")
    }
    func testLiveReplyPayloadNamesAndQuietExistingMetadataCorrection() throws {
        let data = Data(#"{"hits":[{"id":1,"type":202,"commentReplied":{"commentReply":{"content":"Actual reply"}}},{"id":2,"type":261,"commentMentioned":{"commentAtReply":{"content":"Actual mention"}}}]}"#.utf8)
        let rows = try AccountParser.events(data).items
        XCTAssertTrue(rows[0].detail.contains("Actual reply")); XCTAssertTrue(rows[1].detail.contains("Actual mention"))
        var state = LibraryState()
        _ = AccountAnalytics.ingestEvents([AccountEvent(id: "1", kind: .reply, title: "Old", detail: "Old")], into: &state, at: Date())
        XCTAssertTrue(AccountAnalytics.ingestEvents([rows[0]], into: &state, at: Date()).isEmpty)
        XCTAssertEqual(state.activity.count, 1); XCTAssertTrue(state.activity[0].isRead)
        XCTAssertTrue(state.activity[0].detail.contains("Actual reply"))
    }
    func testAccountScopedLedgerAndEarningTimeAreExplicit() throws {
        let data = Data(#"{"hits":[{"type":"design_reward_v2","pointTime":"2026-10-21T10:00:00Z","pointChangeRegular":1,"pointChangeExclusive":0,"designRewardV2":{"id":7,"title":"Recorded title","earningTime":"2026-10-20T00:00:00Z"}}]}"#.utf8)
        let a = try AccountParser.transactions(data, accountID: "1").items[0]
        let b = try AccountParser.transactions(data, accountID: "2").items[0]
        XCTAssertNotEqual(a.id, b.id); XCTAssertTrue(a.reason!.contains("Recorded title"))
        XCTAssertNotEqual(a.date, a.earnedAt); XCTAssertNil(a.serverID)
    }
    func testLedgerFingerprintCollisionStopsImport() async {
        var a = RewardTransaction(id: "local:collision", type: "one", date: nil, regularChange: 1, exclusiveChange: 0, reason: nil, localIdentity: true)
        a.identityContent = "first"
        var b = a; b.identityContent = "different"
        let first = a, second = b
        let other = RewardTransaction(id: "local:other", type: "other", date: nil, regularChange: 2, exclusiveChange: 0, reason: nil, localIdentity: true)
        do { _ = try await LedgerPagination.collect { offset, _ in offset == 0 ? Page(items: [first, other], total: 3) : Page(items: [second], total: 3) }; XCTFail("Collision must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("collision")) }
    }
}
