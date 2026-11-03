import Foundation
import MakerPulseCore

// Explicit --qa-library mode only. It exercises refresh/action feedback with
// copied observations and no credentials, remote writes, or real notifications.
actor UIReplayTransport: HTTPTransport {
    let state: LibraryState
    init(state: LibraryState) { self.state = state }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        try await Task.sleep(for: .milliseconds(160))
        let path = request.url?.path ?? ""
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let offset = Int(query.first { $0.name == "offset" }?.value ?? "0") ?? 0
        let limit = Int(query.first { $0.name == "limit" }?.value ?? "50") ?? 50
        var payload: [String: Any]
        if path.contains("/user/profile/"), let profile = state.profile {
            payload = ["uid": profile.id, "handle": profile.handle, "name": profile.name, "fanCount": profile.counts.followers ?? 0]
            add(profile.counts, into: &payload, model: false)
        } else if path.contains("/publisheddesigns/") {
            let rows: [[String: Any]] = state.models.dropFirst(offset).prefix(limit).map { design in
                var row: [String: Any] = ["id": design.id, "title": design.title]
                if let cover = design.cover { row["coverUrl"] = cover }; add(design.counts, into: &row, model: true); return row
            }
            payload = ["hits": rows, "total": state.models.count]
        } else if path.hasSuffix("/fans") {
            let rows = state.followers.filter(\.isFollowing)
            payload = ["hits": rows.dropFirst(offset).prefix(limit).map { ["uid": $0.id, "name": $0.name, "handle": $0.handle] }, "total": rows.count]
        } else { return HTTPResult(data: Data(), status: 401) }
        return HTTPResult(data: try JSONSerialization.data(withJSONObject: payload), status: 200)
    }
    private func add(_ counts: Counts, into row: inout [String: Any], model: Bool) {
        if let value = counts.likes { row["likeCount"] = value }; if let value = counts.collections { row["collectionCount"] = value }
        if let value = counts.boosts { row[model ? "boostCnt" : "boostGained"] = value }
        if model { if let value = counts.downloads { row["downloadCount"] = value }; if let value = counts.prints { row["printCount"] = value } }
        else { var mw: [String: Any] = [:]; if let value = counts.downloads { mw["myDesignDownloadCount"] = value }; if let value = counts.prints { mw["myDesignPrintCount"] = value }; row["MWCount"] = mw }
    }
}
