import Foundation

struct Dependencies {
    let gitService: GitServiceProtocol
    let signalRService: SignalRServiceProtocol
    let keychainService: KeychainServiceProtocol
    let persistenceService: PersistenceServiceProtocol
    let oAuthService: OAuthServiceProtocol

    static func live() -> Dependencies {
        Dependencies(
            gitService: GitService(),
            signalRService: SignalRService(baseUrl: backendUrl),
            keychainService: LiveKeychainService(),
            persistenceService: LivePersistenceService(),
            oAuthService: OAuthService()
        )
    }

    static func mock(
        git: GitServiceProtocol = MockGitService(),
        signalR: SignalRServiceProtocol = MockSignalRService(),
        keychain: KeychainServiceProtocol = MockKeychainService(),
        persistence: PersistenceServiceProtocol = MockPersistenceService(),
        oauth: OAuthServiceProtocol = MockOAuthService()
    ) -> Dependencies {
        Dependencies(
            gitService: git,
            signalRService: signalR,
            keychainService: keychain,
            persistenceService: persistence,
            oAuthService: oauth
        )
    }
}

nonisolated(unsafe) var currentDependencies = Dependencies.live()
