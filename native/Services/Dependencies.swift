import Foundation

struct Dependencies {
    let gitService: GitServiceProtocol
    let signalRService: SignalRServiceProtocol

    static func live() -> Dependencies {
        Dependencies(
            gitService: GitService(),
            signalRService: SignalRService(baseUrl: backendUrl)
        )
    }

    static func mock(
        git: GitServiceProtocol = MockGitService(),
        signalR: SignalRServiceProtocol = MockSignalRService()
    ) -> Dependencies {
        Dependencies(gitService: git, signalRService: signalR)
    }
}

nonisolated(unsafe) var currentDependencies = Dependencies.live()
