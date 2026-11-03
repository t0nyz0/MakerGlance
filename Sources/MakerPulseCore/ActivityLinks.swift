import Foundation

public enum ActivityLinks {
    public static func followerProfile(for activity: Activity, followers: [Follower]) -> URL? {
        guard activity.id.hasPrefix("followers:") else { return nil }
        let ids = activity.id.dropFirst("followers:".count).split(separator: ",", omittingEmptySubsequences: false)
        // A grouped update must not silently choose one person's profile.
        guard ids.count == 1, let id = ids.first, !id.isEmpty else { return nil }
        let follower = followers.first { $0.id == id }
        let media = activity.presentation
        guard follower != nil || media?.actorID == nil || media?.actorID == String(id) else { return nil }
        guard let handle = follower?.handle ?? media?.actorHandle else { return nil }
        var normalized = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("@") { normalized.removeFirst() }
        guard !normalized.isEmpty, normalized.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        // Encode one path segment, keeping handles from becoming URL queries,
        // fragments or a different origin. Never use a display name as a handle.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = normalized.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://makerworld.com/en/@" + encoded)
    }
}
