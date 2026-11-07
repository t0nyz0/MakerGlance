import Foundation

public enum SchemaDiagnostics {
    public static func describeInbox(_ data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = root["hits"] as? [[String: Any]] else { return "Inbox schema unavailable" }
        var shapes: [String: Set<String>] = [:]
        for hit in hits {
            let raw = hit["type"].map { String(describing: $0) } ?? ""
            let type = !raw.isEmpty && raw.count <= 8 && raw.allSatisfy(\.isNumber) ? raw : "unknown"
            for (key, value) in hit where key.range(of: "^[A-Za-z][A-Za-z0-9_]{0,63}$", options: .regularExpression) != nil {
                shapes[type, default: []].insert(key)
                if let payload = value as? [String: Any] {
                    for child in payload.keys where child.range(of: "^[A-Za-z][A-Za-z0-9_]{0,63}$", options: .regularExpression) != nil {
                        shapes[type, default: []].insert(key + "." + child)
                    }
                }
            }
        }
        return "Inbox types/field names: " + shapes.keys.sorted().prefix(20).map { type in
            type + ": " + shapes[type]!.sorted().prefix(40).joined(separator: ",")
        }.joined(separator: "; ") + ". No values recorded."
    }

    public static func describe(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "Response was not a JSON object" }
        func keys(_ value: [String: Any]) -> String {
            value.keys.filter { $0.range(of: "^[A-Za-z][A-Za-z0-9_]{0,63}$", options: .regularExpression) != nil }.sorted().joined(separator: ",")
        }
        let first = (object["hits"] as? [[String: Any]])?.first
        return "root fields: \(keys(object)); first-record fields: \(first.map(keys) ?? "no records"). No values recorded."
    }
}
