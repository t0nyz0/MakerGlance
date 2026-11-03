import Foundation

public struct MenuStatus: Equatable, Sendable {
    public let unread: Int
    public let refreshing: Bool
    public let attention: Bool
    public init(unread: Int, refreshing: Bool, attention: Bool) { self.unread = max(0, unread); self.refreshing = refreshing; self.attention = attention }
    public var badge: String? { unread == 0 ? nil : unread > 99 ? "99+" : "\(unread)" }
    public var symbol: String? { attention ? "exclamationmark.circle" : refreshing ? "arrow.triangle.2.circlepath" : nil }
    public var accessibility: String { "Creator analytics, \(unread) unread updates" + (attention ? ", needs attention" : "") + (refreshing ? ", refreshing" : "") }
}
