import Foundation

actor MockGitService: GitServiceProtocol {
    var branches: [(name: String, isCurrent: Bool)] = []
    var shouldThrow = false
    var pullResult: PullResult = .success

    func listBranches(repoPath: String) async throws -> [(name: String, isCurrent: Bool)] {
        if shouldThrow { throw GitError.commandFailed("mock error") }
        return branches
    }

    func checkoutBranch(repoPath: String, name: String) async throws {
        if shouldThrow { throw GitError.commandFailed("mock error") }
    }

    func hasUpstream(repoPath: String) async -> Bool { true }
    func hasUpstream(repoPath: String, branch: String) async -> Bool { true }

    func pullCurrentBranch(repoPath: String, token: String?) async -> PullResult { pullResult }

    func deleteLocalBranch(repoPath: String, name: String) async throws {
        if shouldThrow { throw GitError.commandFailed("mock error") }
    }

    func deleteRemoteBranch(repoPath: String, name: String) async throws {
        if shouldThrow { throw GitError.commandFailed("mock error") }
    }

    func currentBranchName(repoPath: String) async -> String? { "main" }

    func fetchRepo(repoPath: String) async {}

    func repoFullName(repoPath: String) async -> String? { "owner/repo" }

    func baseRefName(repoPath: String) async -> String? { "main" }

    func createPR(repoPath: String, branchName: String, backendUrl: String, gitHubId: Int64, overrideTitle: String?, overrideBody: String?) async throws -> CreatePRResult {
        if shouldThrow { throw GitError.commandFailed("mock error") }
        return CreatePRResult(url: URL(string: "https://github.com/owner/repo/pull/1")!, isExisting: false)
    }

    func pullBranch(repoPath: String, name: String, token: String?) async throws {
        if shouldThrow { throw GitError.commandFailed("mock error") }
    }

    func createBranch(repoPath: String, from sourceBranch: String, newName: String) async throws {
        if shouldThrow { throw GitError.commandFailed("mock error") }
    }

    func listMyBranches(repoPath: String) async throws -> [(name: String, isCurrent: Bool)] {
        if shouldThrow { throw GitError.commandFailed("mock error") }
        return branches
    }

    func listMyRemoteBranchesViaAPI(repoPath: String, backendUrl: String, gitHubId: Int64) async -> [(name: String, isMerged: Bool)] { [] }

    static func discoverRepos(workspacePath: String) -> [String] { [] }
    static func repoName(from path: String) -> String { URL(fileURLWithPath: path).lastPathComponent }
    static func fetchPAT(backendUrl: String, gitHubId: Int64) async -> String? { nil }
    static func storedPAT() -> String? { nil }

    func findRepoPath(ownerRepo: String, workspacePath: String) async -> String? { nil }
    func fetchMainAndGetDiff(repoPath: String, lastKnownSha: String?) async -> (currentSha: String, changedFiles: [String])? { nil }
    func getUncommittedFiles(repoPath: String) async -> [String] { [] }
    func getBranchFilesAgainstBase(repoPath: String, baseRef: String) async -> [String] { [] }
}

class MockSignalRService: SignalRServiceProtocol {
    var isConnected = false
    var isLoggedIn = false
    var username = ""
    var avatarUrl: String? = nil
    var userGitHubId: Int64 = 0
    var runStatus: RunStatus = .idle
    var lastEvent: PunishmentEvent? = nil
    var runningWorkflows: [WorkflowRun] = []
    var recentWorkflows: [WorkflowRun] = []
    var activePRs: [PullRequest] = []
    var mainBranchUpdate: (repo: String, prNumber: Int, mergedBy: String, headSha: String?)? = nil
    var onMainBranchUpdated: ((String, Int, String, String?) -> Void)? = nil
    let baseUrl: String = "https://mock.example.com"

    func restoreSession() {}
    func login(keepSignedIn: Bool) async throws {}
    func logout() {}
    func startPolling(gitHubId: Int64) {}
    func stopPolling() {}
}

// MARK: - Keychain Mock

class MockKeychainService: KeychainServiceProtocol {
    var savedSession: KeychainService.Session?
    var shouldReturnSession = true

    func save(gitHubId: Int64, username: String, avatarUrl: String?) {
        savedSession = KeychainService.Session(gitHubId: gitHubId, username: username, avatarUrl: avatarUrl)
    }

    func load() -> KeychainService.Session? {
        shouldReturnSession ? savedSession : nil
    }

    func delete() {
        savedSession = nil
    }
}

// MARK: - Persistence Mock

class MockPersistenceService: PersistenceServiceProtocol {
    var savedWorkflows: [WorkflowRun] = []
    var savedPRs: [PullRequest] = []

    func save(workflows: [WorkflowRun]) { savedWorkflows = workflows }
    func loadWorkflows() -> [WorkflowRun] { savedWorkflows }
    func save(prs: [PullRequest]) { savedPRs = prs }
    func loadPRs() -> [PullRequest] { savedPRs }
}

// MARK: - OAuth Mock

class MockOAuthService: OAuthServiceProtocol {
    var shouldThrow = false
    var loginResult = (id: Int64(12345), username: "testuser", avatarUrl: "https://example.com/avatar.png")

    func startLogin(backendUrl: String) async throws -> (id: Int64, username: String, avatarUrl: String?) {
        if shouldThrow { throw GitError.commandFailed("mock oauth error") }
        return loginResult
    }
}

// MARK: - ConflictWatcher Mock

class MockConflictWatcherService: ConflictWatcherServiceProtocol {
    var isRunning = false
    func start() { isRunning = true }
    func stop() { isRunning = false }
}
