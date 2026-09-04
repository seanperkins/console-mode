import Foundation
import Security

/// Where the DeepSeek API key lives. Injected so `UsageMonitor` never talks
/// to the Keychain directly and tests can swap in an in-memory fake — the
/// key is a real credential, unlike every other path/URL this app persists
/// in `UserDefaults`, and a test run must never touch the user's Keychain.
protocol DeepSeekCredentialStore: Sendable {
    func loadAPIKey() -> String?
    func saveAPIKey(_ key: String?) throws
}

enum DeepSeekCredentialError: LocalizedError, Equatable {
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainFailure(let status):
            let message = SecCopyErrorMessageString(status, nil) as String?
            return "Keychain error: \(message ?? "status \(status)")"
        }
    }
}

/// Stores the key as a generic password item, scoped to this app by service
/// name. `kSecAttrAccessibleAfterFirstUnlock` matches how a background poll
/// needs to read it (no user present, but the disk is unlocked).
struct KeychainDeepSeekCredentialStore: DeepSeekCredentialStore {
    private static let service = "com.seanperkins.ConsoleMode.DeepSeek"
    private static let account = "api-key"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func loadAPIKey() -> String? {
        var attributes = Self.query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveAPIKey(_ key: String?) throws {
        guard let key, !key.isEmpty else {
            let status = SecItemDelete(Self.query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw DeepSeekCredentialError.keychainFailure(status)
            }
            return
        }

        let data = Data(key.utf8)
        let updateStatus = SecItemUpdate(Self.query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = Self.query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw DeepSeekCredentialError.keychainFailure(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw DeepSeekCredentialError.keychainFailure(updateStatus)
        }
    }
}
