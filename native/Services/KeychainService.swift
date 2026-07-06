import Foundation
import Security

enum KeychainService {
    private static let service = "com.personal.btg"
    private static let account = "github-session"

    struct Session: Codable {
        let gitHubId: Int64
        let username: String
    }

    static func save(gitHubId: Int64, username: String) {
        guard let data = try? JSONEncoder().encode(Session(gitHubId: gitHubId, username: username)) else { return }
        SecItemDelete(baseQuery() as CFDictionary)
        var query = baseQuery()
        query[kSecValueData] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> Session? {
        var query = baseQuery()
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}
