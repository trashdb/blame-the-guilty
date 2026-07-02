import Foundation
import Security

/// Persists the GitHub session in the system Keychain so the user
/// doesn't need to log in again after restarting the app or the Mac.
enum KeychainService {

    private static let service = "com.blametheguilty.app"
    private static let account = "github-session"

    struct Session: Codable {
        let gitHubId: Int64
        let username: String
    }

    // MARK: - Save

    static func save(gitHubId: Int64, username: String) {
        guard let data = try? JSONEncoder().encode(Session(gitHubId: gitHubId, username: username)) else { return }

        // Delete any existing entry first
        SecItemDelete(baseQuery() as CFDictionary)

        var query = baseQuery()
        query[kSecValueData] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    // MARK: - Load

    static func load() -> Session? {
        var query = baseQuery()
        query[kSecReturnData]  = kCFBooleanTrue
        query[kSecMatchLimit]  = kSecMatchLimitOne

        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    // MARK: - Delete

    static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    // MARK: - Helpers

    private static func baseQuery() -> [CFString: Any] {
        [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}

