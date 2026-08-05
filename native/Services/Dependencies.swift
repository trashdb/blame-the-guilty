import Foundation
import SwiftUI

struct Dependencies {
    let gitService: GitServiceProtocol
    let signalRService: SignalRServiceProtocol
    let keychainService: KeychainServiceProtocol
    let persistenceService: PersistenceServiceProtocol
    let oAuthService: OAuthServiceProtocol
    let apiClient: ApiClientProtocol

    static func live(signalRService: SignalRServiceProtocol) -> Dependencies {
        Dependencies(
            gitService: GitService(),
            signalRService: signalRService,
            keychainService: LiveKeychainService(),
            persistenceService: LivePersistenceService(),
            oAuthService: OAuthService(),
            apiClient: signalRService.api
        )
    }

    static func live() -> Dependencies {
        live(signalRService: SignalRService(baseUrl: backendUrl))
    }

    static func mock(
        git: GitServiceProtocol = MockGitService(),
        signalR: SignalRServiceProtocol = MockSignalRService(),
        keychain: KeychainServiceProtocol = MockKeychainService(),
        persistence: PersistenceServiceProtocol = MockPersistenceService(),
        oauth: OAuthServiceProtocol = MockOAuthService(),
        api: ApiClientProtocol = MockApiClient()
    ) -> Dependencies {
        Dependencies(
            gitService: git,
            signalRService: signalR,
            keychainService: keychain,
            persistenceService: persistence,
            oAuthService: oauth,
            apiClient: api
        )
    }
}

// MARK: - Environment injection

private struct DependenciesKey: EnvironmentKey {
    static let defaultValue: Dependencies = .live()
}

extension EnvironmentValues {
    var dependencies: Dependencies {
        get { self[DependenciesKey.self] }
        set { self[DependenciesKey.self] = newValue }
    }
}
