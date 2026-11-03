import Foundation
import MakerPulseCore

// Explicit read-only integration verification. Runs inside this app using its
// existing Keychain item; never reads Studio, browser cookies or another app.
@MainActor enum PrintHistoryProbe {
    static func run(output: URL, library: URL) async {
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let store = try Storage(url: library), saved = try await store.load()
            guard let token = try await Task.detached(operation: { try SessionKeychain.read() }).value else { throw PulseError.authentication }
            let api = MakerWorldAPI(); let profile = try await api.validate(token: token)
            guard profile.id == saved.preferences.userID else { throw PulseError.accountMismatch }
            await api.useSession(token)
            let result = try await api.printTasks(known: nil, forceFull: true)
            var thumbnailChecks = 0
            for job in result.jobs.prefix(3) {
                if let url = ImageURLPolicy.thumbnail(job.cover), await ImageRenderer.load(url) != nil { thumbnailChecks += 1 }
            }
            let report: [String: Any] = ["nativeThumbnailsLoaded": thumbnailChecks, "verified": true, "accountMatches": true, "complete": result.complete, "rows": result.jobs.count,
                "cloudTotal": result.cloudTotal as Any, "statusCodes": Array(Set(result.jobs.compactMap(\.status))).sorted(),
                "allowedThumbnailURLs": result.jobs.filter { ImageURLPolicy.thumbnail($0.cover) != nil }.count,
                "thumbnailHosts": Array(Set(result.jobs.compactMap { $0.cover.flatMap(URL.init(string:))?.host })).sorted(),
                "withTitle": result.jobs.filter { $0.title != nil || $0.designTitle != nil }.count,
                "withCover": result.jobs.filter { $0.cover != nil }.count,
                "withPrinterName": result.jobs.filter { $0.deviceName != nil }.count,
                "withPlate": result.jobs.filter { $0.plateLabel != nil }.count,
                "withStart": result.jobs.filter { $0.startTime != nil }.count,
                "withEnd": result.jobs.filter { $0.endTime != nil }.count,
                "withEstimate": result.jobs.filter { $0.estimatedSeconds != nil }.count,
                "schema": await api.schemaDiagnostics["my-prints"] ?? "", "credentialSource": "existing app Keychain session; no credential exported"]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: output.appendingPathComponent("verification.json"), options: .atomic)
        } catch {
            let report: [String: Any] = ["verified": false, "error": error.localizedDescription, "credentialsExported": false]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]) { try? data.write(to: output.appendingPathComponent("verification.json"), options: .atomic) }
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.appendingPathComponent("verification.json").path)
    }
}
