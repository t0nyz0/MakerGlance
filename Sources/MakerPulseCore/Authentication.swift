import Foundation

public enum ConnectionStage: String, Sendable {
    case validating, saving, connected
    public var message: String { switch self { case .validating: "Validating your Bambu session…"; case .saving: "Saving the validated session to Keychain…"; case .connected: "Session saved securely. Private feeds are loading in the background." } }
}
public protocol SessionBackend: Sendable {
    func validate(token: String) async throws -> Profile
    func useSession(_ token: String?) async
}
public protocol SessionStorage: Sendable { func saveSession(_ token: String) async throws }

public enum SessionInput {
    public static func normalize(_ raw: String) throws -> String {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for _ in 0..<4 {
            if (token.hasPrefix("\"") && token.hasSuffix("\"")) || (token.hasPrefix("'") && token.hasSuffix("'")) { token = String(token.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
            if token.lowercased().hasPrefix("bearer ") { token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines); continue }
            if token.lowercased().hasPrefix("token=") { token = String(token.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines); continue }
            break
        }
        guard !token.isEmpty, !token.contains(";"), !token.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) else { throw PulseError.invalidTokenInput }
        // Opaque bearer tokens are supported. JWT shape, segment count, and
        // guessed token length are not used as validity checks.
        return token
    }
}

public enum SessionConnection {
    public static func connect(raw: String, expectedUserID: String, backend: any SessionBackend, storage: any SessionStorage,
        progress: @Sendable (ConnectionStage) async -> Void = { _ in }) async throws -> Profile {
        let token = try SessionInput.normalize(raw)
        await progress(.validating)
        let profile = try await backend.validate(token: token)
        guard expectedUserID.isEmpty ? ProfileSetup.validID(profile.id) : profile.id == expectedUserID else { throw PulseError.accountMismatch }
        await progress(.saving)
        try await storage.saveSession(token)
        await backend.useSession(token)
        await progress(.connected)
        return profile
    }
}
