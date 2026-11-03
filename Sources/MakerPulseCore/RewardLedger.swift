import Foundation

public struct RewardChange: Codable, Sendable, Equatable {
    public var activityID: String
    public var metric: RewardMetric
    public var delta: Decimal
    public var start: Date
    public var end: Date
    public var legacy: Bool
    public var notificationIssued: Bool
    public var matchedIDs: [String]
    public var relatedExclusiveDelta: Decimal?
    public init(activityID: String, metric: RewardMetric, delta: Decimal, start: Date, end: Date, legacy: Bool = false, notificationIssued: Bool = false) {
        self.activityID = activityID; self.metric = metric; self.delta = delta; self.start = start; self.end = end
        self.legacy = legacy; self.notificationIssued = notificationIssued; self.matchedIDs = []
    }
}
public struct RewardMatch: Sendable {
    public var matched: Bool
    public var text: String
    public var rows: [RewardTransaction]
}

public enum RewardLedger {
    public static let version = 2
    public static func match(metric: RewardMetric, delta: Decimal, rows: [RewardTransaction]) -> RewardMatch {
        guard !metric.isCash else { return RewardMatch(matched: false, text: "Reason unavailable from the verified wallet data.", rows: []) }
        let relevant = rows.filter { $0.change(for: metric) != 0 }
        guard !relevant.isEmpty else { return RewardMatch(matched: false, text: "Waiting for transaction details. This point change is saved.", rows: []) }
        let reasons = relevant.prefix(6).map(cause).joined(separator: "; ") + (relevant.count > 6 ? "; more transactions in Rewards" : "")
        guard relevant.allSatisfy({ $0.change(for: metric) != nil }) else {
            return RewardMatch(matched: false, text: "Transactions in this period: \(reasons). Some point amounts are missing, so this change is still being matched.", rows: relevant)
        }
        let sum = relevant.reduce(Decimal.zero) { $0 + $1.change(for: metric)! }
        guard sum == delta else {
            return RewardMatch(matched: false, text: "Transactions in this period: \(reasons). Their total does not match this point change yet.", rows: relevant)
        }
        return RewardMatch(matched: true, text: relevant.count == 1 ? reasons + "." : "From \(relevant.count) point transactions: \(reasons).", rows: relevant)
    }
    private static func cause(_ row: RewardTransaction) -> String {
        let reason = row.reason ?? "MakerWorld point transaction (\(row.type))"
        for label in ["Model creation incentive", "Print-profile incentive"] where reason.hasPrefix(label + " · ") {
            return label + " for " + reason.dropFirst(label.count + 3)
        }
        if row.type == "boost_exchange_point", reason.hasPrefix("Received a boost"), let model = row.presentation?.modelTitle {
            let actor = row.presentation?.actorName ?? row.presentation?.actorHandle
            return "Boost received" + (actor.map { " from " + $0 } ?? "") + " for " + model
                + (row.syncSource == "CN" ? " · CN site" : "") + (reason.contains("Exclusive bonus") ? " · Exclusive bonus" : "")
        }
        return reason
    }
    private static func enriched(_ transaction: RewardTransaction, state: LibraryState) -> RewardTransaction {
        var row = transaction, media = row.presentation ?? ActivityPresentation()
        if let design = state.models.first(where: { $0.id == row.modelID }) {
            media.modelTitle = media.modelTitle ?? design.title; media.modelCover = media.modelCover ?? design.cover
        }
        if let id = media.actorID {
            let event = state.account?.events.first { $0.presentation?.actorID == id }?.presentation
            let follower = state.followers.first { $0.id == id }
            media.actorAvatar = media.actorAvatar ?? event?.actorAvatar ?? follower?.avatar
            media.actorName = media.actorName ?? event?.actorName ?? follower?.name
            media.actorHandle = media.actorHandle ?? event?.actorHandle ?? follower?.handle
        }
        row.presentation = media; return row
    }
    // Link co-observed point rewards without assuming a cash conversion rate or
    // claiming that the estimate was posted to the wallet.
    private static func relatedPoints(before: RewardBalance, after: RewardBalance) -> Decimal? {
        guard let old = before.exclusivePoints, let new = after.exclusivePoints,
              let oldCash = before.cashEstimate, let newCash = after.cashEstimate,
              before.currency(for: .cashEstimate) == after.currency(for: .cashEstimate) else { return nil }
        let delta = new - old
        guard delta != 0, (delta > 0 && newCash > oldCash) || (delta < 0 && newCash < oldCash) else { return nil }
        return delta
    }
    private static let estimateExplanation = "MakerWorld updated the cash redemption estimate. A related exclusive-point change could not be verified for this observation."
    // Quietly repair cached reasons/identities and older visible balance rows.
    // A cached server response is reparsed locally; no credentials or writes to
    // MakerWorld are involved. Old activity is never returned as a new alert.
    public static func repair(_ state: inout LibraryState, history: [BalanceSample] = [], resolveChanges: Bool = true) {
        guard var account = state.account else { return }
        if account.transactions.contains(where: { $0.parserVersion != version && $0.identityContent != nil }) {
            var occurrences: [String: Int] = [:]
            account.transactions = account.transactions.map { old in
                var row = AccountParser.reparse(old, accountID: state.preferences.userID) ?? old
                if row.localIdentity == true, row.parserVersion == version {
                    let base = row.id.split(separator: ":").prefix(3).joined(separator: ":")
                    occurrences[base, default: 0] += 1; row.id = base + ":\(occurrences[base]!)"
                }
                row.firstObservedAt = old.firstObservedAt ?? account.lastTransactionSync ?? account.balance?.date ?? .distantPast
                return row
            }
            account.seenTransactionIDs.formUnion(account.transactions.map(\.id))
        }
        state.account = account
        account.transactions = account.transactions.map { enriched($0, state: state) }
        var changes = account.rewardChanges ?? []
        let samples = history.sorted { $0.date < $1.date }
        for index in state.activity.indices {
            let activity = state.activity[index]
            guard activity.id.hasPrefix("balance:"), !changes.contains(where: { $0.activityID == activity.id }),
                let metric = RewardMetric(rawValue: String(activity.id.split(separator: ":").dropFirst().first ?? "")), !metric.isCash || metric == .cashEstimate else { continue }
            if let current = samples.last(where: { abs($0.date.timeIntervalSince(activity.date)) < 0.1 }),
               let before = samples.last(where: { $0.date < current.date && $0.balance[metric] != nil }),
               let value = current.balance[metric], let previous = before.balance[metric] {
                var change = RewardChange(activityID: activity.id, metric: metric, delta: value - previous, start: before.date, end: current.date, legacy: true, notificationIssued: true)
                if metric == .cashEstimate { change.relatedExclusiveDelta = relatedPoints(before: before.balance, after: current.balance) }
                changes.append(change)
            } else if metric == .cashEstimate {
                state.activity[index].detail = "MakerWorld supplied this cash redemption estimate. This older update has no saved comparison window for linking point rewards."
            } else if activity.detail.contains("does not expose transaction IDs") {
                state.activity[index].detail = "Ledger reasons are available in Rewards. This older balance change has no saved comparison window for exact attribution."
            }
        }
        account.rewardChanges = changes; state.account = account
        if resolveChanges { _ = resolve(into: &state, at: Date(), allowNotifications: false) }
    }
    @discardableResult private static func resolve(into state: inout LibraryState, at now: Date, allowNotifications: Bool) -> [Activity] {
        guard var account = state.account else { return [] }
        account.transactions = account.transactions.map { enriched($0, state: state) }
        var changes = (account.rewardChanges ?? []).sorted { $0.end == $1.end ? $0.activityID < $1.activityID : $0.end < $1.end }
        var claimed: [RewardMetric: Set<String>] = [:], alerts: [Activity] = []
        for i in changes.indices {
            guard let index = state.activity.firstIndex(where: { $0.id == changes[i].activityID }) else { continue }
            let change = changes[i]
            let estimate = change.metric == .cashEstimate
            let candidates = account.transactions.filter { row in
                guard (estimate || !(claimed[change.metric] ?? []).contains(row.id)),
                    change.legacy || (row.firstObservedAt ?? .distantPast) > change.start else { return false }
                // Prefer server record creation; use pointTime only when it is
                // absent. Never use an incentive's earningTime as posting time.
                guard let recorded = row.createdAt ?? row.date else { return false }
                return recorded > change.start && recorded <= change.end
            }
            let result = estimate && change.relatedExclusiveDelta == nil
                ? RewardMatch(matched: false, text: estimateExplanation, rows: [])
                : match(metric: estimate ? .exclusivePoints : change.metric, delta: estimate ? change.relatedExclusiveDelta! : change.delta, rows: candidates)
            changes[i].matchedIDs = result.matched ? result.rows.map(\.id) : []
            if result.matched && !estimate { claimed[change.metric, default: []].formUnion(changes[i].matchedIDs) }
            let detail: String
            if estimate {
                if let points = change.relatedExclusiveDelta {
                    let observed = "Estimate updated alongside \(points > 0 ? "+" : "")\(AccountAnalytics.decimalText(points)) exclusive points. "
                    detail = observed + (result.matched ? "Related verified rewards: " : "Point ledger: ") + result.text + " MakerWorld supplies the cash estimate; this link is based on the same observation window."
                } else { detail = estimateExplanation }
            } else {
                state.activity[index].title = "\(change.delta > 0 ? "+" : "")\(AccountAnalytics.decimalText(change.delta)) \(change.metric.title.lowercased())"
                detail = result.text
            }
            state.activity[index].detail = detail
            let models = Set(result.rows.compactMap(\.modelID))
            var media = ActivityPresentation(rewardMetric: change.metric, rewardDelta: change.delta, content: detail, originalTimestamp: false)
            state.activity[index].modelID = nil
            if result.matched, models.count == 1, result.rows.allSatisfy({ $0.modelID != nil }), let first = result.rows.first {
                state.activity[index].modelID = first.modelID
                media.modelTitle = first.presentation?.modelTitle; media.modelCover = first.presentation?.modelCover
                let actors = Set(result.rows.compactMap { $0.presentation?.actorID ?? $0.presentation?.actorName })
                if actors.count == 1 && result.rows.allSatisfy({ $0.presentation?.actorID != nil || $0.presentation?.actorName != nil }) {
                    media.actorID = first.presentation?.actorID; media.actorName = first.presentation?.actorName
                    media.actorHandle = first.presentation?.actorHandle; media.actorAvatar = first.presentation?.actorAvatar
                }
            }
            state.activity[index].presentation = media
            if allowNotifications, !change.notificationIssued {
                let age = now.timeIntervalSince(change.end)
                if !account.preferences.balanceNotifications.contains(change.metric) || age > 86400 { changes[i].notificationIssued = true }
                else if result.matched || age >= 1800 {
                    changes[i].notificationIssued = true; alerts.append(state.activity[index])
                }
            }
        }
        account.rewardChanges = Array(changes.suffix(1000)); state.account = account; return alerts
    }
    public static func ingest(_ balance: RewardBalance, transactions: [RewardTransaction]?, walletTransactions: [WalletTransaction]?, into state: inout LibraryState, at date: Date, ledgerObservedAt: Date? = nil) -> [Activity] {
        repair(&state, resolveChanges: false)
        var account = state.account ?? AccountState()
        let previous = account.balance, previousWallet = account.walletTransactions
        if let transactions {
            let old = Dictionary(account.transactions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let incoming = transactions.map { value -> RewardTransaction in
                var row = value; row.firstObservedAt = old[row.id]?.firstObservedAt ?? (account.seenTransactionIDs.contains(row.id) ? .distantPast : (ledgerObservedAt ?? date))
                return row
            }
            let updates = Dictionary(incoming.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let unseen = incoming.filter { !account.seenTransactionIDs.contains($0.id) }
            account.transactions = Array((unseen + account.transactions.map { updates[$0.id] ?? $0 }).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.prefix(10000))
            account.seenTransactionIDs.formUnion(incoming.map(\.id)); account.transactionsImported = true
            account.lastTransactionSync = date; account.ledgerReasonVersion = version
        }
        let changed = RewardMetric.allCases.filter { metric in
            guard let a = previous?.balance[metric], let b = balance[metric] else { return false }
            return a != b && (!metric.isCash || previous?.balance.currency(for: metric) == balance.currency(for: metric))
        }
        if !changed.isEmpty { account.balanceRevision += 1 }
        if let walletTransactions { account.walletTransactions = Array(walletTransactions.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.prefix(10000)); account.lastWalletSync = date }
        var alerts: [Activity] = []
        for metric in changed where account.preferences.balanceNotifications.contains(metric) {
            let delta = balance[metric]! - previous!.balance[metric]!
            let start = account.balanceDates[metric] ?? previous!.date
            let id = "balance:\(metric.rawValue):\(account.balanceRevision)"
            let reason = metric == .cashEstimate ? estimateExplanation : metric.isCash ? WalletAnalytics.reconciledReason(metric: metric, delta: delta, currency: balance.currency(for: metric), previous: previousWallet, current: walletTransactions, observedBefore: start, now: date) : "Pending ledger match."
            let activity = Activity(id: id, date: date, title: "\(metric.title) \(delta > 0 ? "+" : "")\(AccountAnalytics.decimalText(delta))\(metric.isCash ? " " + (balance.currency(for: metric) ?? "currency unavailable") : " points")", detail: reason, symbol: metric.isCash ? "banknote" : "sparkles", presentation: ActivityPresentation(rewardMetric: metric, rewardDelta: delta, originalTimestamp: false))
            state.activity.insert(activity, at: 0)
            if metric.isCash { alerts.append(activity) }
            if !metric.isCash || metric == .cashEstimate {
                var change = RewardChange(activityID: id, metric: metric, delta: delta, start: start, end: date, notificationIssued: metric.isCash)
                if metric == .cashEstimate, account.balanceDates[.exclusivePoints] == account.balanceDates[.cashEstimate] {
                    change.relatedExclusiveDelta = relatedPoints(before: previous!.balance, after: balance)
                }
                account.rewardChanges = (account.rewardChanges ?? []) + [change]
            }
        }
        for metric in RewardMetric.allCases where balance[metric] != nil { account.balanceDates[metric] = date }
        var merged = balance; if let previous { merged.preserveMissing(from: previous.balance) }
        account.balance = BalanceSample(date: date, balance: merged); state.account = account
        alerts += resolve(into: &state, at: ledgerObservedAt ?? date, allowNotifications: true)
        // Include newly enriched estimate details in this cycle's local banner.
        alerts = alerts.map { alert in state.activity.first(where: { $0.id == alert.id }) ?? alert }
        state.activity = Array(state.activity.prefix(1000)); return alerts
    }
}
