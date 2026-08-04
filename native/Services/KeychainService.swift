import Foundation
import Security

enum KeychainService {
    static let service = "com.statefalse.app"
    private static let account = "github-session"
    private static let oldService = "com.personal.btg"

    struct Session: Codable {
        let gitHubId: Int64
        let username: String
        let avatarUrl: String?
        let token: String?
    }

    static func save(gitHubId: Int64, username: String, avatarUrl: String? = nil, token: String? = nil) {
        guard let data = try? JSONEncoder().encode(Session(gitHubId: gitHubId, username: username, avatarUrl: avatarUrl, token: token)) else { return }
        SecItemDelete(baseQuery(service: service) as CFDictionary)
        var query = baseQuery(service: service)
        query[kSecValueData] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> Session? {
        if let session = loadFrom(service: service) { return session }
        if let session = loadFrom(service: oldService) {
            save(gitHubId: session.gitHubId, username: session.username, avatarUrl: session.avatarUrl, token: session.token)
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

// MARK: - Protocol Wrapper for DI

final class LiveKeychainService: KeychainServiceProtocol {
    func save(gitHubId: Int64, username: String, avatarUrl: String?, token: String? = nil) {
        KeychainService.save(gitHubId: gitHubId, username: username, avatarUrl: avatarUrl, token: token)
    }

    func load() -> KeychainService.Session? {
        KeychainService.load()
    }

    func delete() {
        KeychainService.delete()
    }
}
