import Foundation

public enum Analytics {
    public static func delta(_ metric: Metric, samples: [Sample], current: Counts, since: Date) -> Int? {
        let available = samples.filter { $0.counts[metric] != nil }
        guard let baseline = available.last(where: { $0.date <= since }) ?? available.first, let before = baseline.counts[metric], let now = current[metric] else { return nil }
        return now - before
    }

    // A high-water mark, rather than the previous snapshot, prevents duplicates after
    // temporary count corrections, API retries, restarts, and notification toggles.
    public static func ingestProfile(_ profile: Profile, into state: inout LibraryState, at date: Date) -> [Activity] {
        var events: [Activity] = []
        for metric in Metric.allCases {
            guard let value = profile.counts[metric] else { continue }
            let key = "profile:\(profile.id):\(metric.rawValue)"
            let old = state.highWater[key] ?? value
            let step = max(1, state.preferences.milestoneStep)
            if state.profileImported && state.preferences.notifyMilestones && value / step > old / step {
                let mark = (value / step) * step
                events.append(Activity(id: "\(key):milestone:\(mark)", date: date, title: "\(mark.formatted()) \(metric.title.lowercased())", detail: "@\(profile.handle) reached a new milestone.", symbol: metric.symbol,
                    presentation: ActivityPresentation(actorName: profile.name, actorHandle: profile.handle, actorAvatar: profile.avatar, metric: metric, delta: value - old, originalTimestamp: false)))
            }
            state.highWater[key] = max(old, value)
        }
        state.profile = profile; state.profileImported = true; state.lastProfileSync = date
        return append(events, into: &state)
    }

    public static func ingestModels(_ models: [Design], into state: inout LibraryState, at date: Date) -> [Activity] {
        var events: [Activity] = []
        let previousIDs = Set(state.models.map(\.id))
        for model in models {
            if state.watches[model.id] == nil { state.watches[model.id] = WatchRule() }
            let rule = state.watches[model.id] ?? WatchRule()
            for metric in [Metric.likes, .downloads, .boosts, .collections] {
                guard let value = model.counts[metric] else { continue }
                let key = "model:\(model.id):\(metric.rawValue)"
                let old = state.highWater[key] ?? value
                if previousIDs.contains(model.id) && value > old && rule.enabled && rule.allows(metric) {
                    let change = value - old
                    events.append(Activity(id: "\(key):\(value)", date: date,
                        title: "+\(change.formatted()) \(metric.title.lowercased())", detail: model.title,
                        symbol: metric.symbol, modelID: model.id, presentation: ActivityPresentation(modelTitle: model.title, modelCover: model.cover, metric: metric, delta: change, originalTimestamp: false)))
                }
                state.highWater[key] = max(old, value)
            }
        }
        state.models = models; state.lastModelSync = date
        return append(events, into: &state)
    }

    // Only call this after a complete, deduplicated crawl. Existing followers have
    // no known follow date. First observed is our observation time, never a claim
    // about the original follow date; a returning follower keeps their first date.
    public static func ingestFollowers(_ followers: [Follower], into state: inout LibraryState, at date: Date) -> [Activity] {
        var saved = Dictionary(state.followers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>(); var newlyObserved: [Follower] = []
        for var follower in followers where seen.insert(follower.id).inserted {
            if let old = saved[follower.id] { follower.firstObservedAt = old.firstObservedAt; follower.baseline = old.baseline }
            else {
                follower.baseline = !state.followersImported
                follower.firstObservedAt = state.followersImported ? date : nil
                if state.followersImported { newlyObserved.append(follower) }
            }
            follower.isFollowing = true; saved[follower.id] = follower
        }
        for id in saved.keys where !seen.contains(id) { saved[id]?.isFollowing = false }
        state.followers = saved.values.sorted { $0.id < $1.id }
        state.followersImported = true; state.lastFollowerSync = date
        guard state.preferences.notifyFollowers, !newlyObserved.isEmpty else { return [] }
        let ids = newlyObserved.map(\.id).sorted().joined(separator: ",")
        let names = newlyObserved.prefix(3).map { "@\($0.handle)" }.joined(separator: ", ")
        let first = newlyObserved.count == 1 ? newlyObserved.first : nil
        return append([Activity(id: "followers:\(ids)", date: date,
            title: newlyObserved.count == 1 ? "New follower" : "\(newlyObserved.count) new followers",
            detail: names + (newlyObserved.count > 3 ? " and more" : ""), symbol: "person.badge.plus",
            presentation: ActivityPresentation(actorID: first?.id, actorName: first?.name, actorHandle: first?.handle, actorAvatar: first?.avatar, metric: .followers, delta: newlyObserved.count, originalTimestamp: false))], into: &state)
    }

    private static func append(_ events: [Activity], into state: inout LibraryState) -> [Activity] {
        let existing = Set(state.activity.map(\.id))
        let fresh = events.filter { !existing.contains($0.id) }
        state.activity = Array((fresh.reversed() + state.activity).prefix(1000))
        return fresh
    }
}

public enum Pagination {
    public static func collect<T: Sendable & Identifiable>(limit: Int = 50, maxPages: Int = 500,
        fetch: @Sendable (Int, Int) async throws -> Page<T>) async throws -> [T] where T.ID: Sendable {
        var output: [T] = []; var seen = Set<T.ID>(); var offset = 0; var expected: Int?
        for _ in 0..<maxPages {
            try Task.checkCancellation()
            let page = try await fetch(offset, limit)
            if let total = page.total { expected = max(expected ?? 0, total) }
            let fresh = page.items.filter { seen.insert($0.id).inserted }
            output.append(contentsOf: fresh)
            if page.items.isEmpty {
                if let expected, output.count < expected { throw PulseError.incomplete("API") }
                return output
            }
            if fresh.isEmpty { throw PulseError.incomplete("repeating API page") }
            offset += page.items.count
            if let expected, output.count >= expected { return output }
            if expected == nil && page.items.count < limit { return output }
        }
        throw PulseError.incomplete("API page limit")
    }
}
