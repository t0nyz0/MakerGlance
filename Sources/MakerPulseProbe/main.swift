import Foundation
import MakerPulseCore

@main struct Probe {
    static func main() async {
        do {
            guard let id = CommandLine.arguments.dropFirst().first, ProfileSetup.validID(id) else {
                print("Usage: swift run MakerGlanceProbe NUMERIC_PUBLIC_USER_ID")
                exit(2)
            }
            let api = MakerWorldAPI()
            let profile = try await api.profile(userID: id)
            print("Public profile fetched; account identifiers and values omitted.")
            let models = try await api.models(userID: id)
            print("Public model pagination fetched; identifiers and values omitted.")
            guard !models.isEmpty else { throw PulseError.incomplete("model verification") }
            let followers = try await api.followers(userID: id)
            print("Public follower pagination fetched; identities and values omitted.")
            guard followers.count >= (profile.counts.followers ?? 0) else { throw PulseError.incomplete("follower verification") }
            var state = LibraryState()
            let date = Date()
            let events = Analytics.ingestProfile(profile, into: &state, at: date) + Analytics.ingestModels(models, into: &state, at: date) + Analytics.ingestFollowers(followers, into: &state, at: date)
            guard events.isEmpty, state.followers.allSatisfy({ $0.firstObservedAt == nil && $0.baseline }) else { throw PulseError.incomplete("baseline verification") }
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("MakerPulseProbe-\(UUID().uuidString)").appendingPathComponent("analytics.sqlite")
            let store = try Storage(url: path)
            try await store.commit(state, samples: ["profile": Sample(date: date, counts: profile.counts)])
            let restored = try await store.load()
            guard restored.models.count == models.count, restored.followers.count == followers.count else { throw PulseError.incomplete("storage roundtrip") }
            print("PASS live pagination, deduplication, quiet baseline, unknown follow dates, SQLite roundtrip")
            try? FileManager.default.removeItem(at: path.deletingLastPathComponent())
        } catch {
            print("FAIL \(error.localizedDescription)")
            exit(1)
        }
    }
}
