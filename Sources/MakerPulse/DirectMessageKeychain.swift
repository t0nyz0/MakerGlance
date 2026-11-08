import Foundation
import Security
import MakerPulseCore

enum DirectMessageKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: AppIdentity.keychainService,
            kSecAttrAccount as String: "makerworld-direct-messages-v1"]
    }
    static func read() throws -> DirectMessageCredential? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw AccessError(status: status) }
        guard let session = try? JSONDecoder().decode(DirectMessageCredential.self, from: data) else { throw AccessError(status: errSecDecode) }
        return session
    }
    static func save(_ session: DirectMessageCredential) throws {
        let data = try JSONEncoder().encode(session)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var entry = query; entry[kSecValueData as String] = data
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(entry as CFDictionary, nil)
            guard added == errSecSuccess else { throw AccessError(status: added) }
        } else if status != errSecSuccess { throw AccessError(status: status) }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccessError(status: status) }
    }
    private struct AccessError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Direct-message Keychain access failed (\(status)). Saved activity is preserved." }
    }
}
