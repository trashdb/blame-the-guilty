import Foundation
import Security

enum KeychainService {
    static let service = "com.blametheguilty.app"
    private static let account = "github-session"
    private static let oldService = "com.personal.btg"

    struct Session: Codable {
        let gitHubId: Int64
        let username: String
        let avatarUrl: String?
    }

    static func save(gitHubId: Int64, username: String, avatarUrl: String? = nil) {
        guard let data = try? JSONEncoder().encode(Session(gitHubId: gitHubId, username: username, avatarUrl: avatarUrl)) else { return }
        SecItemDelete(baseQuery(service: service) as CFDictionary)
        var query = baseQuery(service: service)
        query[kSecValueData] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> Session? {
        if let session = loadFrom(service: service) { return session }
        if let session = loadFrom(service: oldService) {
            save(gitHubId: session.gitHubId, username: session.username, avatarUrl: session.avatarUrl)
            SecItemDelete(baseQuery(service: oldService) as CFDictionary)
            return session
        }
        return nil
    }

    static func delete() {
        SecItemDelete(baseQuery(service: service) as CFDictionary)
    }

    private static func loadFrom(service: String) -> Session? {
        var query = baseQuery(service: service)
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    private static func baseQuery(service: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}
