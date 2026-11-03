import Foundation

public enum LedgerPagination {
    // MakerWorld currently exposes no ledger IDs. Content fingerprints and
    // multiplicity distinguish local rows without claiming server identifiers.
    public static func collect(limit: Int = 50, maxPages: Int = 500,
        fetch: @Sendable (Int, Int) async throws -> Page<RewardTransaction>) async throws -> [RewardTransaction] {
        var output: [RewardTransaction] = [], offset = 0
        var expected: Int?, seenServerIDs = Set<String>(), seenPages = Set<[String]>()
        var occurrences: [String: Int] = [:]
        var identityContents: [String: String] = [:]
        for _ in 0..<maxPages {
            try Task.checkCancellation()
            let page = try await fetch(offset, limit)
            if let total = page.total {
                guard expected == nil || expected == total else { throw PulseError.incomplete("changing points ledger total") }
                expected = total
            }
            if page.items.isEmpty {
                guard expected == nil || offset >= expected! else { throw PulseError.incomplete("points ledger") }
                return output
            }
            let repeated = !seenPages.insert(page.items.map(\.id)).inserted
            guard !repeated || expected != nil && Set(page.items.map(\.id)).count == 1 && page.items.allSatisfy({ $0.localIdentity == true }) else { throw PulseError.incomplete("repeating points ledger page") }
            for var item in page.items {
                if item.localIdentity == true {
                    if let content = item.identitySignature ?? item.identityContent {
                        guard identityContents[item.id] == nil || identityContents[item.id] == content else { throw PulseError.malformed("ledger identity collision") }
                        identityContents[item.id] = content
                    }
                    occurrences[item.id, default: 0] += 1
                    item.id += ":\(occurrences[item.id]!)"
                    output.append(item)
                } else if seenServerIDs.insert(item.id).inserted { output.append(item) }
            }
            offset += page.items.count
            if let expected, offset >= expected {
                guard output.count == expected else { throw PulseError.incomplete("points ledger entry count") }
                return output
            }
            if expected == nil && page.items.count < limit { return output }
        }
        throw PulseError.incomplete("points ledger page limit")
    }
}
