import Foundation

// Independently implemented from verified MakerWorld web field names. See
// docs/INBOX_EVENT_SCHEMAS.md; unsupported types deliberately stay explicit.
enum InboxEventParser {
    struct Definition {
        let type: String
        let key: String
        let kind: EventKind
        let title: String
        let summary: String
    }
    static let definitions: [Definition] = [
        .init(type: "101", key: "draftSliceFailed", kind: .model, title: "Print-profile slicing failed", summary: "MakerWorld could not slice a draft print profile."),
        .init(type: "104", key: "instancePublished", kind: .model, title: "Print profile published", summary: "A print profile was published on MakerWorld."),
        .init(type: "106", key: "instanceAddToDesign", kind: .model, title: "Print profile added to a model", summary: "A print profile was added to a model on MakerWorld."),
        .init(type: "107", key: "draftImportFinished", kind: .model, title: "Draft import finished", summary: "MakerWorld finished importing drafts. Individual import results are unavailable."),
        .init(type: "254", key: "instanceRatingRemind", kind: .model, title: "Print-profile rating reminder", summary: "MakerWorld is asking you to rate a print profile."),
        .init(type: "368", key: "auditSystem", kind: .system, title: "Copyright review update", summary: "MakerWorld updated a copyright review. Review details are unavailable."),
        .init(type: "412", key: "systemForWeb", kind: .system, title: "MakerWorld system update", summary: "MakerWorld posted a system message. Message details are unavailable."),
        .init(type: "501", key: "pointBoostingRightGet", kind: .system, title: "Boost tokens received", summary: "MakerWorld reports new boost tokens. Token and expiry details are unavailable."),
        .init(type: "502", key: "pointBoostingRightExpireRemind", kind: .system, title: "Boost token expiry reminder", summary: "MakerWorld sent a boost token expiry reminder. The expiry date is unavailable."),
        .init(type: "604", key: "communityPostFollowingLatest", kind: .community, title: "New community post", summary: "A creator you follow posted to the community."),
        .init(type: "811", key: "newSubscriberForCreator", kind: .system, title: "New subscriber", summary: "Someone subscribed to your membership. Subscriber and tier details are unavailable."),
        .init(type: "815", key: "newBadgeReceived", kind: .system, title: "New badge received", summary: "MakerWorld awarded you a badge. Badge details are unavailable.")
    ]

    static func definition(for type: String) -> Definition? { definitions.first { $0.type == type } }

    static func parse(_ event: JSONNode, id: String, type: String) -> AccountEvent? {
        guard let definition = definition(for: type) else { return nil }
        let payload = event[definition.key]
        var actor = event["from"]
        if type == "811" { actor = payload["userInfo"] }
        if type == "604" { actor = payload["user"] }
        let design = payload["designInfo"], profile = payload["instanceInfo"]
        let draft = payload["draftInfo"], system = payload["systemInfo"]
        let name = text(actor["name"])
        let modelTitle = text(design["title"]) ?? text(draft["designTitle"])
        let profileTitle = text(profile["title"]) ?? text(draft["instanceTitle"])
        let values: [String: String?] = ["name": name, "model": modelTitle, "profile": profileTitle,
            "tier": text(payload["membershipLevelInfo"]["title"]), "expiry": text(payload["expireAt"]),
            "title": text(system["title"]), "body": text(system["newContent"]),
            "review": text(payload["content"]), "reviewDetail": text(payload["contentDetail"]), "reviewAction": text(payload["opDesc"]),
            "badge": text(payload["badgeTitle"]), "milestone": text(payload["sparkAward"]["milestone"]),
            "imported": text(payload["draftImportInfo"]["successNum"]), "failed": text(payload["draftImportInfo"]["failedNum"])]
        let fields = values.compactMapValues { $0 }
        let display = render(fields, definition: definition)
        let media = ActivityPresentation(actorID: actor["uid"].string ?? actor["id"].string,
            actorName: name, actorHandle: text(actor["handle"]), actorAvatar: actor["avatar"].string,
            modelTitle: modelTitle, modelCover: design["cover"].string ?? design["coverUrl"].string,
            content: display.content, eventFields: fields.isEmpty ? nil : fields,
            kind: definition.kind, originalTimestamp: event["createTime"].date != nil)
        return AccountEvent(id: id, kind: definition.kind, rawType: type, title: display.title, detail: display.detail,
            occurredAt: event["createTime"].date, modelID: design["id"].string, presentation: media)
    }

    private static func render(_ fields: [String: String], definition: Definition) -> (title: String, detail: String, content: String?) {
        let name = fields["name"], tier = fields["tier"]
        var title = definition.title
        var pieces: [String] = []
        switch definition.type {
        case "811":
            if let name, let tier { pieces = ["\(name) subscribed to your \(tier) membership tier."] }
            else if let name { pieces = ["\(name) subscribed to your membership. Tier details are unavailable."] }
            else if let tier { pieces = ["Someone subscribed to your \(tier) membership tier. Subscriber details are unavailable."] }
        case "501", "502":
            // Preserve the supplied timestamp, rather than guessing its timezone
            // or the number of tokens from a notification template.
            if let expiry = fields["expiry"] {
                pieces = [definition.type == "501" ? "Boost tokens received." : "Boost token expiry reminder.", "Expires: \(expiry)"]
            }
        case "412":
            title = fields["title"] ?? title
            pieces = [fields["body"]].compactMap { $0 }
        case "368":
            pieces = [fields["review"], fields["reviewDetail"], fields["reviewAction"]].compactMap { $0 }
        case "815":
            if let badge = fields["badge"] { pieces = ["Badge received: \(badge)"] }
            if let milestone = fields["milestone"] { pieces.append("Print milestone: \(milestone)") }
        case "107":
            let imported = fields["imported"], failed = fields["failed"]
            pieces = [imported.map { "Imported: \($0)" }, failed.map { "Failed: \($0)" }].compactMap { $0 }
        case "604":
            if let name { pieces = ["\(name) posted to the community."] }
        default:
            pieces = [name, fields["model"], fields["profile"]].compactMap { $0 }
        }
        let detail = String((pieces.isEmpty ? definition.summary : pieces.joined(separator: " · ")).prefix(2000))
        return (String(title.prefix(300)), detail, pieces.isEmpty ? nil : detail)
    }

    static func enriching(_ incoming: AccountEvent, from old: AccountEvent) -> AccountEvent {
        guard old.rawType == incoming.rawType, let definition = definition(for: incoming.rawType) else { return incoming }
        var result = incoming
        result.modelID = incoming.modelID ?? old.modelID
        result.occurredAt = incoming.occurredAt ?? old.occurredAt
        result.presentation = (old.presentation ?? ActivityPresentation()).merging(incoming.presentation)
        if old.occurredAt != nil { result.presentation?.originalTimestamp = true }
        if let fields = result.presentation?.eventFields {
            let display = render(fields, definition: definition)
            result.title = display.title; result.detail = display.detail
            result.presentation?.content = display.content
        } else {
            if incoming.detail == definition.summary, !old.detail.hasPrefix("MakerWorld event type ") { result.detail = old.detail }
            if incoming.title == definition.title, !old.title.hasPrefix("MakerWorld update (") { result.title = old.title }
        }
        return result
    }

    // A title-only repair is possible even when older versions discarded the
    // payload. Never infer an identity, tier, date, model or quantity from type.
    static func upgrade(_ event: AccountEvent) -> AccountEvent? {
        guard event.title == "MakerWorld update (\(event.rawType))", let definition = definition(for: event.rawType) else { return nil }
        var result = event
        result.title = definition.title; result.kind = definition.kind
        if event.detail == "MakerWorld event type \(event.rawType). Details are unavailable for this event type." { result.detail = definition.summary }
        result.presentation = (event.presentation ?? ActivityPresentation()).merging(ActivityPresentation(kind: definition.kind))
        return result
    }

    static func text(_ value: JSONNode) -> String? {
        guard let string = value.string else { return nil }
        let clean = string.replacingOccurrences(of: "<(script|style)\\b[^>]*>[\\s\\S]*?</\\1\\s*>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return clean.isEmpty ? nil : String(clean.prefix(2000))
    }
}
