import Foundation

public struct ActivityPresentation: Codable, Equatable, Sendable {
    public var actorID: String?
    public var rewardMetric: RewardMetric?
    public var rewardDelta: Decimal?
    public var actorName: String?
    public var actorHandle: String?
    public var actorAvatar: String?
    public var modelTitle: String?
    public var modelCover: String?
    public var content: String?
    public var kind: EventKind?
    public var metric: Metric?
    public var delta: Int?
    public var originalTimestamp: Bool?
    public init(actorID: String? = nil, rewardMetric: RewardMetric? = nil, rewardDelta: Decimal? = nil, actorName: String? = nil, actorHandle: String? = nil, actorAvatar: String? = nil, modelTitle: String? = nil, modelCover: String? = nil,
        content: String? = nil, kind: EventKind? = nil, metric: Metric? = nil, delta: Int? = nil, originalTimestamp: Bool? = nil) {
        self.actorID = actorID; self.rewardMetric = rewardMetric; self.rewardDelta = rewardDelta
        self.actorName = actorName; self.actorHandle = actorHandle; self.actorAvatar = actorAvatar; self.modelTitle = modelTitle; self.modelCover = modelCover
        self.content = content; self.kind = kind; self.metric = metric; self.delta = delta; self.originalTimestamp = originalTimestamp
    }
    public func merging(_ incoming: Self?) -> Self {
        guard let incoming else { return self }
        return Self(actorID: incoming.actorID ?? actorID, rewardMetric: incoming.rewardMetric ?? rewardMetric, rewardDelta: incoming.rewardDelta ?? rewardDelta, actorName: incoming.actorName ?? actorName, actorHandle: incoming.actorHandle ?? actorHandle, actorAvatar: incoming.actorAvatar ?? actorAvatar,
            modelTitle: incoming.modelTitle ?? modelTitle, modelCover: incoming.modelCover ?? modelCover, content: incoming.content ?? content, kind: incoming.kind ?? kind,
            metric: incoming.metric ?? metric, delta: incoming.delta ?? delta, originalTimestamp: incoming.originalTimestamp ?? originalTimestamp)
    }
}

public enum ImageURLPolicy {
    public static let printCoverHost = "or-cloud-model-prod.s3.dualstack.us-west-2.amazonaws.com"
    public static func original(_ raw: String?) -> URL? {
        guard let raw, let url = URLComponents(string: raw), url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443,
            let host = url.host?.lowercased(), host.hasSuffix(".bblmw.com") || host.hasSuffix(".bambulab.com") || host == printCoverHost else { return nil }
        return URL(string: raw)
    }
    public static func thumbnail(_ raw: String?, pixelWidth: Int = 480) -> URL? {
        guard let original = original(raw), var url = URLComponents(url: original, resolvingAgainstBaseURL: false), let host = url.host else { return nil }
        // Signed print-history URLs must remain byte-for-byte unchanged.
        if host == printCoverHost { return original }
        var query = url.queryItems ?? []
        if !query.contains(where: { $0.name == "x-oss-process" }) {
            let format = url.path.lowercased().hasSuffix(".gif") ? "png" : "webp"
            query.append(URLQueryItem(name: "x-oss-process", value: "image/resize,w_\(max(32, min(640, pixelWidth)))/quality,q_80/format,\(format)"))
        }
        url.queryItems = query; return url.url
    }
}
