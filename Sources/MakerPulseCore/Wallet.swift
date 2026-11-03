import Foundation

public struct WalletTransaction: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var date: Date?
    public var amount: Decimal
    public var currency: String
    public var status: Int
    public var source: Int
    public var detailTransactionID: String?
    public var exclusivePoints: Decimal?
    public var statusTitle: String { switch status { case 1: "Completed"; case 2: "Pending"; case 3: "Canceled / refunded"; default: "Unknown status \(status)" } }
    public var reason: String {
        switch source {
        case 1: "Exclusive points redemption" + (exclusivePoints.map { " · \(AccountAnalytics.decimalText($0)) points" } ?? "")
        case 2: "Maker Supply incentive" + (detailTransactionID.map { " · transaction \($0)" } ?? "")
        case 3: "Model sale"
        case 4: "Commercial license membership"
        default: "Reason unavailable · source \(source)"
        }
    }
}
public enum WalletParser {
    public static func transactions(_ data: Data) throws -> Page<WalletTransaction> {
        let root = try JSONDecoder().decode(JSONNode.self, from: data)
        guard let hits = root["hits"].array else { throw PulseError.malformed("wallet income ledger") }
        let rows = try hits.map { row -> WalletTransaction in
            guard let id = row["id"].string, let amount = row["amount"].decimal, let currency = row["currency"].string, currency.count == 3,
                let status = row["status"].string.flatMap(Int.init), let source = row["source"].string.flatMap(Int.init) else { throw PulseError.malformed("wallet income fields") }
            return WalletTransaction(id: id, date: row["date"].date, amount: amount, currency: currency.uppercased(), status: status, source: source,
                detailTransactionID: row["incomeDetail"]["transactionId"].string, exclusivePoints: row["incomeDetail"]["exclusivePoint"].decimal)
        }
        return Page(items: rows, total: root["total"].string.flatMap(Int.init))
    }
}
public enum WalletAnalytics {
    public static func reconciledReason(metric: RewardMetric, delta: Decimal, currency: String?, previous: [WalletTransaction]?, current: [WalletTransaction]?, observedBefore: Date, now: Date) -> String {
        guard [.cashAvailable, .cashPending, .cashIncome].contains(metric), let currency, let previous, let current else { return "Reason unavailable from the verified wallet ledger." }
        let old = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var total: Decimal = 0, reasons: [String] = []
        for row in current where row.currency == currency {
            let before = old[row.id]
            if let before, before.currency != row.currency { return "Reason unavailable: a wallet entry changed currency." }
            if before == nil {
                guard let time = row.date, time > observedBefore, time <= now else { continue }
            }
            func contribution(_ item: WalletTransaction?) -> Decimal {
                guard let item else { return 0 }
                switch metric { case .cashAvailable: return item.status == 1 ? item.amount : 0
                case .cashPending: return item.status == 2 ? item.amount : 0
                case .cashIncome: return [1,2].contains(item.status) ? item.amount : 0
                default: return 0 }
            }
            let change = contribution(row) - contribution(before)
            if change != 0 {
                total += change
                reasons.append("wallet entry \(row.id): \(row.reason) · \(before.map { "\($0.statusTitle) → " } ?? "")\(row.statusTitle)")
            }
        }
        guard !reasons.isEmpty, total == delta else { return "Reason unavailable: wallet entries do not reconcile exactly to this change." }
        return "Reconciled to observed " + reasons.prefix(5).joined(separator: "; ") + ". Status-transition times are first observed locally when the server omits them."
    }
}
