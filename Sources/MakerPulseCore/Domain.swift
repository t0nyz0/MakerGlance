import Foundation

public enum Metric: String, Codable, CaseIterable, Identifiable, Sendable {
    case likes, downloads, prints, boosts, collections, followers
    public var id: String { rawValue }
    public var title: String { self == .collections ? "Collection saves" : rawValue.capitalized }
    public var symbol: String {
        switch self { case .likes: "heart"; case .downloads: "arrow.down.circle"; case .prints: "printer"; case .boosts: "bolt"; case .collections: "square.stack"; case .followers: "person.2" }
    }
}

public struct Counts: Codable, Equatable, Sendable {
    public var likes: Int?
    public var downloads: Int?
    public var prints: Int?
    public var apiDownloads: Int?
    public var boosts: Int?
    public var collections: Int?
    public var followers: Int?
    public init(likes: Int? = nil, downloads: Int? = nil, prints: Int? = nil, apiDownloads: Int? = nil, boosts: Int? = nil, collections: Int? = nil, followers: Int? = nil) {
        self.likes = likes; self.downloads = downloads; self.prints = prints; self.apiDownloads = apiDownloads; self.boosts = boosts; self.collections = collections; self.followers = followers
    }
    public subscript(_ metric: Metric) -> Int? {
        switch metric { case .likes: likes; case .downloads: downloads; case .prints: prints; case .boosts: boosts; case .collections: collections; case .followers: followers }
    }
}

public struct Profile: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var handle: String
    public var avatar: String?
    public var counts: Counts
    public init(id: String, name: String, handle: String, avatar: String? = nil, counts: Counts) {
        self.id = id; self.name = name; self.handle = handle; self.avatar = avatar; self.counts = counts
    }
}

public struct Design: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var cover: String?
    public var counts: Counts
    public var publishedAt: Date?
    public init(id: String, title: String, cover: String? = nil, counts: Counts, publishedAt: Date? = nil) {
        self.id = id; self.title = title; self.cover = cover; self.counts = counts; self.publishedAt = publishedAt
    }
}

public struct Follower: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var handle: String
    public var avatar: String?
    public var firstObservedAt: Date?
    public var baseline: Bool
    public var isFollowing: Bool
    public init(id: String, name: String, handle: String, avatar: String? = nil, firstObservedAt: Date? = nil, baseline: Bool = true, isFollowing: Bool = true) {
        self.id = id; self.name = name; self.handle = handle; self.avatar = avatar; self.firstObservedAt = firstObservedAt; self.baseline = baseline; self.isFollowing = isFollowing
    }
}

public struct Sample: Codable, Identifiable, Equatable, Sendable {
    public var date: Date
    public var counts: Counts
    public var id: Date { date }
    public init(date: Date, counts: Counts) { self.date = date; self.counts = counts }
}

public struct WatchRule: Codable, Equatable, Sendable {
    public var enabled = true
    public var boosts = true
    public var likes = false
    public var downloads = false
    public var collections = false
    public init() {}
    public func allows(_ metric: Metric) -> Bool {
        switch metric { case .boosts: boosts; case .likes: likes; case .downloads: downloads; case .collections: collections; case .followers, .prints: false }
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var userID = ""
    public var handle = ""
    public var pollingMinutes = 10
    public var pollingSelectionVersion: Int?
    public var modelFilter: ModelWatchFilter?
    public var notifyFollowers = true
    public var notifyMilestones = true
    public var milestoneStep = 1000
    public var notificationsEnabled = false
    public var appearanceChoice: AppearanceChoice?
    public var textScalePercent: Int?
    public var watchedModelSort: WatchedModelSort?
    public var watchedSortBasis: WatchedSortBasis?
    public var dashboardSort: WatchedModelSort { watchedModelSort ?? .recent }
    public var dashboardSortBasis: WatchedSortBasis { watchedSortBasis ?? .total }
    public var watchedModelLayout: WatchedModelLayout?
    public var watchedLayout: WatchedModelLayout { watchedModelLayout ?? .cards }
    public var textSizePercent: Int { TextScalePolicy.normalized(textScalePercent) }
    public var textScaleFactor: Double { TextScalePolicy.factor(textScalePercent) }
    public var appearance: AppearanceChoice { appearanceChoice ?? .system }
    public init() {}
}

public struct Activity: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var date: Date
    public var title: String
    public var detail: String
    public var symbol: String
    public var isRead: Bool
    public var modelID: String?
    public var presentation: ActivityPresentation?
    public init(id: String, date: Date, title: String, detail: String, symbol: String, isRead: Bool = false, modelID: String? = nil, presentation: ActivityPresentation? = nil) {
        self.id = id; self.date = date; self.title = title; self.detail = detail; self.symbol = symbol; self.isRead = isRead; self.modelID = modelID
        self.presentation = presentation
    }
}

public struct LibraryState: Codable, Sendable {
    public var schema = 2
    public var preferences = Preferences()
    public var profile: Profile?
    public var models: [Design] = []
    public var followers: [Follower] = []
    public var watches: [String: WatchRule] = [:]
    public var activity: [Activity] = []
    public var dismissedActivityIDs: Set<String>?
    public var highWater: [String: Int] = [:]
    public var profileImported = false
    public var followersImported = false
    public var lastProfileSync: Date?
    public var lastModelSync: Date?
    public var lastFollowerSync: Date?
    public var account: AccountState?
    public var creatorReport: CreatorReport?
    public var printHistory: PrintHistory?
    public init() {}
}

public struct Page<Item: Sendable>: Sendable {
    public var items: [Item]
    public var total: Int?
    public init(items: [Item], total: Int?) { self.items = items; self.total = total }
}

public enum PulseError: LocalizedError, Sendable {
    case http(Int), malformed(String), incomplete(String), database(String), authentication, challenge, invalidTokenInput, accountMismatch
    public var errorDescription: String? {
        switch self {
        case .http(let code): "MakerWorld returned HTTP \(code). Your saved history is safe."
        case .malformed(let context): "MakerWorld changed its \(context) response. Refresh later or update MakerGlance."
        case .incomplete(let context): "Incomplete \(context) pagination; the previous baseline was preserved."
        case .database(let reason): "Local database error: \(reason)"
        case .authentication: "Your Bambu session has expired. Reconnect in Settings. Public analytics can still work."
        case .challenge: "MakerWorld requires browser verification. Public Bambu API data may still be available."
        case .invalidTokenInput: "Paste only the session-token value, not an entire Cookie header. It must not contain spaces, line breaks, or semicolons."
        case .accountMismatch: "This session belongs to another account. Sign in to the MakerWorld profile monitored by this app."
        }
    }
}
