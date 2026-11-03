import Foundation

public enum SchemaDiagnostics {
    public static func describe(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "Response was not a JSON object" }
        func keys(_ value: [String: Any]) -> String {
            value.keys.filter { $0.range(of: "^[A-Za-z][A-Za-z0-9_]{0,63}$", options: .regularExpression) != nil }.sorted().joined(separator: ",")
        }
        let first = (object["hits"] as? [[String: Any]])?.first
        return "root fields: \(keys(object)); first-record fields: \(first.map(keys) ?? "no records"). No values recorded."
    }
}
