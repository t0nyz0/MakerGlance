import Foundation

public enum EventKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case comment, reply, mention, boost, model, community, crowdfunding, system, device, other
    public var id: String { rawValue }
    public var title: String { switch self { case .comment: "Comments & ratings"; case .reply: "Replies"; case .mention: "Mentions"; case .boost: "Boost events"; case .model: "Model updates"; case .community: "Community"; case .crowdfunding: "Crowdfunding"; case .system: "System & account"; case .device: "Printer/device"; case .other: "Other events" } }
    public var symbol: String { switch self { case .comment: "text.bubble"; case .reply: "arrowshape.turn.up.left"; case .mention: "at"; case .boost: "bolt"; case .model: "cube"; case .community: "person.3"; case .crowdfunding: "person.3.sequence"; case .system: "info.circle"; case .device: "printer"; case .other: "bell" } }
}
public struct AccountEvent: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var kind: EventKind
    public var rawType: String
    public var title: String
    public var detail: String
    public var occurredAt: Date?
    public var modelID: String?
    public var metricCorrelationID: String?
    public var presentation: ActivityPresentation?
    public init(id: String, kind: EventKind, rawType: String = "", title: String, detail: String, occurredAt: Date? = nil, modelID: String? = nil, metricCorrelationID: String? = nil, presentation: ActivityPresentation? = nil) {
        self.id = id; self.kind = kind; self.rawType = rawType; self.title = title; self.detail = detail; self.occurredAt = occurredAt; self.modelID = modelID; self.metricCorrelationID = metricCorrelationID
        self.presentation = presentation
    }
}
public enum RewardMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case totalPoints, regularPoints, exclusivePoints, cashEstimate, cashAvailable, cashPending, cashIncome, cashTransferred, cashWithdrawing
    public var id: String { rawValue }
    public var title: String { switch self { case .totalPoints: "Total points"; case .regularPoints: "Regular points"; case .exclusivePoints: "Exclusive points"; case .cashEstimate: "Cash redemption estimate"; case .cashAvailable: "Wallet remaining to transfer"; case .cashPending: "Wallet pending income"; case .cashIncome: "Wallet total income"; case .cashTransferred: "Wallet transferred"; case .cashWithdrawing: "Wallet withdrawing" } }
    public var isCash: Bool { ![.totalPoints, .regularPoints, .exclusivePoints].contains(self) }
}
public struct RewardBalance: Codable, Sendable, Equatable {
    public var totalPoints: Decimal?
    public var regularPoints: Decimal?
    public var exclusivePoints: Decimal?
    public var cashEstimate: Decimal?
    public var cashAvailable: Decimal?
    public var cashPending: Decimal?
    public var cashIncome: Decimal?
    public var cashTransferred: Decimal?
    public var cashWithdrawing: Decimal?
    public var currency: String?
    public var estimateCurrency: String?
    public var walletCurrency: String?
    public init(totalPoints: Decimal? = nil, regularPoints: Decimal? = nil, exclusivePoints: Decimal? = nil, cashEstimate: Decimal? = nil, cashAvailable: Decimal? = nil, cashPending: Decimal? = nil, currency: String? = nil) {
        self.totalPoints = totalPoints; self.regularPoints = regularPoints; self.exclusivePoints = exclusivePoints; self.cashEstimate = cashEstimate; self.cashAvailable = cashAvailable; self.cashPending = cashPending; self.currency = currency
    }
    public subscript(_ metric: RewardMetric) -> Decimal? { switch metric { case .totalPoints: totalPoints; case .regularPoints: regularPoints; case .exclusivePoints: exclusivePoints; case .cashEstimate: cashEstimate; case .cashAvailable: cashAvailable; case .cashPending: cashPending; case .cashIncome: cashIncome; case .cashTransferred: cashTransferred; case .cashWithdrawing: cashWithdrawing } }
    public func currency(for metric: RewardMetric) -> String? { metric == .cashEstimate ? estimateCurrency ?? currency : walletCurrency ?? currency }
    public mutating func preserveMissing(from old: RewardBalance) {
        totalPoints = totalPoints ?? old.totalPoints; regularPoints = regularPoints ?? old.regularPoints; exclusivePoints = exclusivePoints ?? old.exclusivePoints
        cashEstimate = cashEstimate ?? old.cashEstimate; cashAvailable = cashAvailable ?? old.cashAvailable; cashPending = cashPending ?? old.cashPending
        cashIncome = cashIncome ?? old.cashIncome; cashTransferred = cashTransferred ?? old.cashTransferred; cashWithdrawing = cashWithdrawing ?? old.cashWithdrawing
        estimateCurrency = estimateCurrency ?? old.estimateCurrency; walletCurrency = walletCurrency ?? old.walletCurrency; currency = currency ?? old.currency
    }
}
public struct BalanceSample: Codable, Identifiable, Sendable, Equatable {
    public var date: Date
    public var balance: RewardBalance
    public var id: Date { date }
    public init(date: Date, balance: RewardBalance) { self.date = date; self.balance = balance }
}
public struct RewardTransaction: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var localIdentity: Bool?
    public var identityContent: String?
    public var earnedAt: Date?
    public var createdAt: Date?
    public var firstObservedAt: Date?
    public var parserVersion: Int?
    public var identitySignature: String?
    public var totalChange: Decimal?
    public var modelID: String?
    public var printProfileID: String?
    public var syncSource: String?
    public var presentation: ActivityPresentation?
    public func change(for metric: RewardMetric) -> Decimal? {
        switch metric {
        case .regularPoints: return regularChange
        case .exclusivePoints: return exclusiveChange
        case .totalPoints:
            if let regularChange, let exclusiveChange {
                let sum = regularChange + exclusiveChange
                return totalChange == nil || totalChange == sum ? sum : nil
            }
            return totalChange
        default: return nil
        }
    }
    public var earningDayUTC: String? {
        guard let earnedAt else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withFullDate]; return formatter.string(from: earnedAt)
    }
    public var serverID: String? { localIdentity == true ? nil : id }
    public var type: String
    public var date: Date?
    public var regularChange: Decimal?
    public var exclusiveChange: Decimal?
    public var reason: String?
    public init(id: String, type: String, date: Date?, regularChange: Decimal?, exclusiveChange: Decimal?, reason: String?, localIdentity: Bool = false) {
        self.id = id; self.type = type; self.date = date; self.regularChange = regularChange; self.exclusiveChange = exclusiveChange; self.reason = reason
        self.localIdentity = localIdentity
    }
}
public struct AccountPreferences: Codable, Sendable, Equatable {
    public var eventNotifications: Set<EventKind> = [.comment, .reply, .mention, .model, .system]
    public var balanceNotifications: Set<RewardMetric> = [.exclusivePoints, .cashEstimate, .cashAvailable, .cashPending]
    public var directMessageNotifications: Bool?
    public var allowsDirectMessageAlerts: Bool { directMessageNotifications ?? true }
    public init() {}
}
public struct AccountState: Codable, Sendable {
    public var preferences = AccountPreferences()
    public var events: [AccountEvent] = []
    public var seenEventIDs: Set<String> = []
    public var eventsImported = false
    public var lastEventSync: Date?
    public var balance: BalanceSample?
    public var balanceRevision = 0
    public var balanceDates: [RewardMetric: Date] = [:]
    public var transactions: [RewardTransaction] = []
    public var seenTransactionIDs: Set<String> = []
    public var transactionsImported = false
    public var lastTransactionSync: Date?
    public var walletTransactions: [WalletTransaction]?
    public var lastWalletSync: Date?
    public var rewardChanges: [RewardChange]?
    public var ledgerReasonVersion: Int?
    public var directMessages: DirectMessageState?
    public init() {}
}

public enum AccountAnalytics {
    // Local metadata repair has no alert path and never touches read/dismissed
    // state, seen IDs, import baselines, preferences or activity membership.
    @discardableResult public static func repairEventDescriptions(in state: inout LibraryState) -> Int {
        guard var account = state.account else { return 0 }
        var updates: [String: AccountEvent] = [:]
        account.events = account.events.map { event in
            guard let update = InboxEventParser.upgrade(event) else { return event }
            updates[event.id] = update; return update
        }
        for i in state.activity.indices {
            let id = state.activity[i].id
            guard id.hasPrefix("remote:"), let event = updates[String(id.dropFirst(7))] else { continue }
            enrichActivity(&state.activity[i], using: event)
        }
        state.account = account
        return updates.count
    }

    private static func enrichActivity(_ activity: inout Activity, using event: AccountEvent) {
        activity.title = event.title
        activity.detail = event.detail + (event.occurredAt == nil ? " · original timestamp unavailable" : "")
        activity.symbol = event.kind.symbol
        activity.modelID = event.modelID ?? activity.modelID
        activity.presentation = (activity.presentation ?? ActivityPresentation()).merging(event.presentation)
        if let time = event.occurredAt { activity.date = time }
    }

    public static func ingestEvents(_ events: [AccountEvent], into state: inout LibraryState, at date: Date) -> [Activity] {
        var account = state.account ?? AccountState(); let baseline = !account.eventsImported
        let previous = Dictionary(account.events.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let observations = events.map { incoming -> AccountEvent in
            guard let old = previous[incoming.id] else { return incoming }
            return InboxEventParser.enriching(incoming, from: old)
        }
        let fresh = observations.filter { account.seenEventIDs.insert($0.id).inserted }
        let updates = Dictionary(observations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        account.events = account.events.map { updates[$0.id] ?? $0 }
        for i in state.activity.indices {
            let key = state.activity[i].id
            guard key.hasPrefix("remote:"), let update = updates[String(key.dropFirst(7))] else { continue }
            enrichActivity(&state.activity[i], using: update)
        }
        account.events = Array((fresh + account.events).sorted { ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast) }.prefix(5000))
        account.eventsImported = true; account.lastEventSync = date
        var alerts: [Activity] = []
        for event in fresh {
            if let correlation = event.metricCorrelationID, (state.dismissedActivityIDs ?? []).contains(correlation) { continue }
            if let correlation = event.metricCorrelationID, let i = state.activity.firstIndex(where: { $0.id == correlation }) {
                state.activity[i].detail = event.detail
                state.activity[i].presentation = (state.activity[i].presentation ?? ActivityPresentation()).merging(event.presentation)
                continue
            }
            let watch = event.modelID.flatMap { state.watches[$0] }
            let enabled = account.preferences.eventNotifications.contains(event.kind) && (event.kind != .boost || (watch?.enabled ?? true) && (watch?.boosts ?? true))
            guard enabled || (baseline && event.kind != .device) else { continue }
            guard !(state.dismissedActivityIDs ?? []).contains("remote:\(event.id)") else { continue }
            let activity = Activity(id: "remote:\(event.id)", date: event.occurredAt ?? date, title: event.title,
                detail: event.detail + (event.occurredAt == nil ? " · original timestamp unavailable" : ""), symbol: event.kind.symbol,
                isRead: baseline || !enabled, modelID: event.modelID, presentation: event.presentation)
            state.activity.append(activity)
            if !baseline && enabled { alerts.append(activity) }
        }
        state.activity = Array(state.activity.sorted { $0.date > $1.date }.prefix(1000))
        state.account = account; return alerts
    }

    public static func ingestRewards(_ balance: RewardBalance, transactions: [RewardTransaction]?, walletTransactions: [WalletTransaction]? = nil, into state: inout LibraryState, at date: Date, ledgerObservedAt: Date? = nil) -> [Activity] {
        RewardLedger.ingest(balance, transactions: transactions, walletTransactions: walletTransactions, into: &state, at: date, ledgerObservedAt: ledgerObservedAt)
    }
    public static func reconciledReason(for metric: RewardMetric, delta: Decimal, transactions: [RewardTransaction]) -> String {
        RewardLedger.match(metric: metric, delta: delta, rows: transactions).text
    }
    public static func decimalText(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
}
