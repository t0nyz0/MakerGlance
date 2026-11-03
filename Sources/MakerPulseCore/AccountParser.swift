import Foundation
import CryptoKit

// Decimal is decoded directly from JSON, never through Double. This preserves
// fractional point amounts and money exactly in storage and reconciliation.
enum JSONNode: Decodable, Sendable {
    case object([String: JSONNode]), array([JSONNode]), text(String), number(Decimal), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(String.self) { self = .text(value) }
        else if let value = try? c.decode(Decimal.self) { self = .number(value) }
        else if let value = try? c.decode([String: JSONNode].self) { self = .object(value) }
        else { self = .array(try c.decode([JSONNode].self)) }
    }
    subscript(_ key: String) -> JSONNode { if case .object(let object) = self { return object[key] ?? .null }; return .null }
    var string: String? { switch self { case .text(let text): text; case .number(let value): NSDecimalNumber(decimal: value).stringValue; default: nil } }
    var nonempty: String? { string.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } }
    var decimal: Decimal? { switch self { case .number(let value): value; case .text(let text): Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")); default: nil } }
    var array: [JSONNode]? { if case .array(let values) = self { return values }; return nil }
    var object: [String: JSONNode]? { if case .object(let value) = self { return value }; return nil }
    var date: Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: string)
    }
    var incentiveDate: Date? {
        if let date { return date }
        guard let string, string.count == 10 else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withFullDate]
        guard let value = formatter.date(from: string), formatter.string(from: value) == string else { return nil }
        return value
    }
    var canonical: String {
        func quote(_ text: String) -> String { String(data: try! JSONEncoder().encode(text), encoding: .utf8)! }
        switch self {
        case .object(let value): return "{" + value.keys.sorted().map { quote($0) + ":" + value[$0]!.canonical }.joined(separator: ",") + "}"
        case .array(let values): return "[" + values.map(\.canonical).joined(separator: ",") + "]"
        case .text(let value): return quote(value)
        case .number(let value): return NSDecimalNumber(decimal: value).stringValue
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        }
    }
}

public enum AccountParser {
    private static func json(_ data: Data) throws -> JSONNode { try JSONDecoder().decode(JSONNode.self, from: data) }
    public static func events(_ data: Data, group: EventKind? = nil) throws -> Page<AccountEvent> {
        let root = try json(data)
        guard let hits = root["hits"].array else { throw PulseError.malformed("account activity") }
        return Page(items: try hits.map { event in
            guard let id = event["id"].string else { throw PulseError.malformed("stable activity IDs") }
            let rawType = event["type"].string ?? "unknown"
            let mappings: [(String, EventKind, String)] = [
                ("designCommented", .comment, "New model comment"), ("commentReplied", .reply, "New comment reply"),
                ("commentMentioned", .mention, "You were mentioned"), ("ratingMentioned", .mention, "You were mentioned in a rating"),
                ("instRating", .comment, "New print-profile rating"), ("instRatingReply", .reply, "New rating reply"), ("instRatingReplyReply", .reply, "New rating reply"),
                ("makerLabCommentMentioned", .mention, "MakerLab mention"), ("courseCommentMentioned", .mention, "Course mention"),
                ("communityComment", .community, "Community comment"), ("communityPostLiked", .community, "Community like"),
                ("pointDesignBoosted", .boost, "Your model received a boost"), ("taskMessage", .device, "Printer update"),
                ("designPublished", .model, "Model published"), ("designFeatured", .model, "Model featured"), ("designRemixed", .model, "Model remixed"),
                ("walletPayoutFailed", .system, "Wallet payout update"), ("walletWithdrawAduitRejected", .system, "Wallet review update"),
                ("pointRedeemCashAuditRejected", .system, "Cash redemption review update"), ("system", .system, "MakerWorld system update")]
            let match = mappings.first { event[$0.0].object != nil }
            let kind = match?.1 ?? group ?? .other
            let payload = match.map { event[$0.0] } ?? event
            let sender = event["from"]["name"].string
            let design = payload["designInfo"]
            let modelID = design["id"].string ?? payload["designId"].string
            let modelTitle = design["title"].string ?? payload["designTitle"].string
            let content = [payload["commentAtReply"]["content"], payload["commentReply"]["content"], payload["commentReplyReplyInfo"]["content"], payload["commentReplyInfo"]["content"], payload["commentInfo"]["content"], payload["content"], payload["title"]].compactMap(\.string).first { !$0.isEmpty }
            let rating = payload["score"].string.map { "Rating score: \($0)" }
            let pieces = [sender, modelTitle, content, rating].compactMap { $0 }.map(plainText)
            let detail = pieces.isEmpty ? "MakerWorld event type \(rawType). Details are unavailable for this event type." : pieces.joined(separator: " · ")
            let total = payload["designBoostCnt"].string
            let correlation = kind == .boost ? modelID.flatMap { id in total.map { "model:\(id):boosts:\($0)" } } : nil
            let media = ActivityPresentation(actorID: event["from"]["uid"].string ?? event["from"]["id"].string, actorName: sender, actorHandle: event["from"]["handle"].string, actorAvatar: event["from"]["avatar"].string,
                modelTitle: modelTitle, modelCover: design["cover"].string ?? design["coverUrl"].string ?? payload["cover"].string,
                content: content.map(plainText), kind: kind, originalTimestamp: event["createTime"].date != nil)
            return AccountEvent(id: id, kind: kind, rawType: rawType, title: match?.2 ?? "MakerWorld update (\(rawType))", detail: String(detail.prefix(2000)), occurredAt: event["createTime"].date, modelID: modelID, metricCorrelationID: correlation, presentation: media)
        }, total: root["total"].decimal.map { NSDecimalNumber(decimal: $0).intValue })
    }

    public static func points(_ data: Data) throws -> RewardBalance {
        let root = try json(data)
        let regular = root["totalRegularPoint"].decimal
        let exclusive = root["totalExclusivePoint"].decimal
        guard regular != nil || exclusive != nil else { throw PulseError.malformed("points balance") }
        let total = root["totalPoint"].decimal ?? regular.flatMap { a in exclusive.map { a + $0 } }
        return RewardBalance(totalPoints: total, regularPoints: regular, exclusivePoints: exclusive)
    }
    public static func cashProgress(_ data: Data, into balance: RewardBalance) throws -> RewardBalance {
        let root = try json(data)
        guard let amount = root["canRedeemAmount"].decimal, let currency = root["currency"].string, validCurrency(currency) else { throw PulseError.malformed("cash redemption estimate") }
        var result = balance; result.cashEstimate = amount; result.estimateCurrency = currency.uppercased()
        return result
    }
    // Wallet fields are kept separate from the cash-redemption estimate. Unknown
    // field layouts remain unavailable; they are never inferred from points.
    public static func wallet(_ data: Data, into balance: RewardBalance) throws -> RewardBalance {
        let root = try json(data)
        guard let currency = root["currency"].string, validCurrency(currency),
            root["remainingToTransfer"].decimal != nil || root["pendingIncome"].decimal != nil else { throw PulseError.malformed("wallet balance") }
        var result = balance; result.cashAvailable = root["remainingToTransfer"].decimal; result.cashPending = root["pendingIncome"].decimal
        result.cashIncome = root["totalIncome"].decimal; result.cashTransferred = root["transferred"].decimal; result.cashWithdrawing = root["withdrawing"].decimal
        result.walletCurrency = currency.uppercased(); return result
    }
    public static func transactions(_ data: Data, accountID: String = "unscoped") throws -> Page<RewardTransaction> {
        let root = try json(data)
        guard let hits = root["hits"].array else { throw PulseError.malformed("points transactions") }
        return Page(items: try hits.map { try transaction($0, accountID: accountID) }, total: root["total"].decimal.map { NSDecimalNumber(decimal: $0).intValue })
    }
    public static func reparse(_ row: RewardTransaction, accountID: String) -> RewardTransaction? {
        guard let content = row.identityContent, let node = try? json(Data(content.utf8)) else { return nil }
        return try? transaction(node, accountID: accountID)
    }
    private static func transaction(_ raw: JSONNode, accountID: String) throws -> RewardTransaction {
        guard raw.object != nil, let type = raw["type"].string,
            raw["pointChangeRegular"].decimal != nil || raw["pointChangeExclusive"].decimal != nil || raw["pointChange"].decimal != nil else { throw PulseError.malformed("points transaction fields") }
        let boost = raw["extInfoBoostExchangePoint"]
        let instance = [raw["instanceRewardV2"], raw["instanceReward"], raw["instance"], raw["pointRating"]].first { $0.object != nil } ?? .null
        let design = [raw["designRewardV2"], raw["designReward"], raw["design"], raw["extInfoBoostDesign"]].first { $0.object != nil } ?? .null
        let modelID = boost["designId"].string ?? instance["designId"].string ?? design["designId"].string ?? design["id"].string
        let title = boost["designTitle"].string ?? instance["designTitle"].string ?? design["title"].string ?? design["designTitle"].string
        let actorID = boost["fromUid"].string ?? instance["donatedByUid"].string
        let actorName = boost["fromUsername"].nonempty ?? instance["donatedByUsername"].nonempty
        let handle = boost["fromUserHandle"].nonempty
        let profileID = instance["instanceId"].string
        // Display text/images may be enriched later. They are not identity.
        var identity: [String: JSONNode] = [:]
        for key in ["type", "pointTime", "createTime", "isExclusiveBonus", "syncSource"] { identity[key] = raw[key] }
        for key in ["pointChange", "pointChangeRegular", "pointChangeExclusive"] { identity[key] = raw[key].decimal.map(JSONNode.number) ?? raw[key] }
        identity["earningTime"] = design["earningTime"].string.map(JSONNode.text) ?? instance["earningTime"]
        identity["deducted"] = design.object != nil ? design["deducted"] : instance["deducted"]
        identity["boostingRightId"] = raw["extInfoBoostDesign"]["boostingRightId"]
        identity["laserCutReward"] = design["laserCutReward"]
        identity["model"] = modelID.map(JSONNode.text) ?? .null
        identity["profile"] = profileID.map(JSONNode.text) ?? .null
        identity["actor"] = (actorID ?? handle).map(JSONNode.text) ?? .null
        // Other types need their supplied non-display reference fields too.
        if modelID == nil && profileID == nil && actorID == nil {
            let extras = raw.object!.filter { !identity.keys.contains($0.key) && $0.key != "description" && $0.key != "reason" }
            identity["reference"] = .object(extras)
        }
        let signature = JSONNode.object(identity).canonical
        let fingerprint = SHA256.hash(data: Data(signature.utf8)).map { String(format: "%02x", $0) }.joined()
        let serverID = raw["id"].string
        var row = RewardTransaction(id: serverID ?? "local:\(accountID):\(fingerprint)", type: type, date: raw["pointTime"].date,
            regularChange: raw["pointChangeRegular"].decimal, exclusiveChange: raw["pointChangeExclusive"].decimal, reason: nil, localIdentity: serverID == nil)
        row.identityContent = serverID == nil ? raw.canonical : nil; row.identitySignature = signature
        row.totalChange = raw["pointChange"].decimal; row.createdAt = raw["createTime"].date
        row.earnedAt = design["earningTime"].incentiveDate ?? instance["earningTime"].incentiveDate
        row.modelID = modelID; row.printProfileID = profileID; row.syncSource = raw["syncSource"].string
        row.parserVersion = 2
        let labels = ["design_reward_v2": "Model creation incentive", "design_reward": "Model creation incentive", "instance_reward_v2": "Print-profile incentive", "instance_reward": "Print-profile incentive", "design_reward_recover_v2": "Model reward recovery", "instance_reward_recover_v2": "Print-profile reward recovery", "boost_exchange_point": "Received a boost", "exchange_cash": "Points exchanged for cash", "exchange_cash_recover": "Cash redemption points returned", "redeem_exclusive_deduct": "Exclusive points used", "redeem_exclusive_income": "Exclusive points received", "academy_course_award": "Academy course reward", "makerLab_first_export": "MakerLab first export reward", "award": "MakerWorld award", "create_rating": "Print-profile rating reward", "exchange": "Points shop exchange", "redeem_product_request": "Product redemption", "boost_design": "Model boost", "boost_redeem": "Boost token redemption", "create_first_instance": "First print-profile reward", "create_instance": "Print-profile creation reward", "create_design": "Model publishing reward", "fill_personal_info": "Profile completion reward", "fill_personal_info_2": "Profile completion reward"]
        let explicit = raw["description"].string ?? raw["reason"].string
        let label = explicit.flatMap { $0.isEmpty ? nil : plainText($0) } ?? labels[type] ?? "MakerWorld ledger entry (\(type))"
        let extra = instance["instanceTitle"].string ?? raw["extInfoAcademyCourseAward"]["courseName"].string ?? raw["extInfoMakerLabFirstExport"]["makerLabName"].string ?? raw["extInfoAward"]["content"].string ?? raw["extExchange"]["productName"].string ?? raw["extInfoPointRedeemProductRequest"]["productName"].string
        row.reason = [label, title, extra, handle.map { "@" + $0 } ?? actorName, row.syncSource == "CN" ? "CN site" : nil].compactMap { $0 }.map(plainText).joined(separator: " · ")
        if case .bool(true) = raw["isExclusiveBonus"] { row.reason! += " · Exclusive bonus" }
        row.presentation = ActivityPresentation(actorID: actorID, actorName: actorName ?? handle, actorHandle: handle,
            actorAvatar: boost["fromUserAvatar"].string, modelTitle: title,
            modelCover: design["coverUrl"].string ?? design["cover"].string ?? instance["coverUrl"].string, content: extra.map(plainText), originalTimestamp: true)
        return row
    }
    private static func validCurrency(_ value: String) -> Bool { value.count == 3 && value.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) } }
    private static func plainText(_ value: String) -> String { value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&") }
}
