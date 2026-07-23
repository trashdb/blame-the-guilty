import Foundation

// MARK: - Shared Types

struct CreatePRResult {
    let url: URL
    let isExisting: Bool
}

enum PullResult {
    case success, noUpstream, noToken, conflict, failed
}

enum GitError: LocalizedError {
    case gitNotFound
    case commandFailed(String)
    var errorDescription: String? {
        switch self {
        case .gitNotFound: return "Git not found"
        case .commandFailed(let s): return s
        }
    }
}

// MARK: - GitServiceProtocol

protocol GitServiceProtocol: AnyObject {
    func listBranches(repoPath: String) async throws -> [(name: String, isCurrent: Bool)]
    func checkoutBranch(repoPath: String, name: String) async throws
    func hasUpstream(repoPath: String) async -> Bool
    func hasUpstream(repoPath: String, branch: String) async -> Bool
    func pullCurrentBranch(repoPath: String, token: String?) async -> PullResult
    func deleteLocalBranch(repoPath: String, name: String) async throws
    func deleteRemoteBranch(repoPath: String, name: String) async throws
    func currentBranchName(repoPath: String) async -> String?
    func fetchRepo(repoPath: String) async
    func repoFullName(repoPath: String) async -> String?
    func baseRefName(repoPath: String) async -> String?
    func createPR(repoPath: String, branchName: String, backendUrl: String, gitHubId: Int64, overrideTitle: String?, overrideBody: String?) async throws -> CreatePRResult
    func pullBranch(repoPath: String, name: String, token: String?) async throws
    func createBranch(repoPath: String, from sourceBranch: String, newName: String) async throws
    func listMyBranches(repoPath: String) async throws -> [(name: String, isCurrent: Bool)]
    func listMyRemoteBranchesViaAPI(repoPath: String, backendUrl: String, gitHubId: Int64) async -> [(name: String, isMerged: Bool)]
    static func discoverRepos(workspacePath: String) -> [String]
    static func repoName(from path: String) -> String
    static func fetchPAT(backendUrl: String, gitHubId: Int64) async -> String?
    static func storedPAT() -> String?
    func findRepoPath(ownerRepo: String, workspacePath: String) async -> String?
    func fetchMainAndGetDiff(repoPath: String, lastKnownSha: String?) async -> (currentSha: String, changedFiles: [String])?
    func getUncommittedFiles(repoPath: String) async -> [String]
    func getBranchFilesAgainstBase(repoPath: String, baseRef: String) async -> [String]
}

// MARK: - SignalRServiceProtocol

protocol SignalRServiceProtocol: AnyObject {
    var isConnected: Bool { get set }
    var isLoggedIn: Bool { get set }
    var username: String { get set }
    var avatarUrl: String? { get set }
    var userGitHubId: Int64 { get set }
    var runStatus: RunStatus { get set }
    var lastEvent: PunishmentEvent? { get set }
    var runningWorkflows: [WorkflowRun] { get set }
    var recentWorkflows: [WorkflowRun] { get set }
    var activePRs: [PullRequest] { get set }
    var mainBranchUpdate: (repo: String, prNumber: Int, mergedBy: String, headSha: String?)? { get set }
    var onMainBranchUpdated: ((String, Int, String, String?) -> Void)? { get set }
    var baseUrl: String { get }

    func restoreSession()
    func login(keepSignedIn: Bool) async throws
    func logout()
    func startPolling(gitHubId: Int64)
    func stopPolling()
}

// MARK: - KeychainServiceProtocol

protocol KeychainServiceProtocol: AnyObject {
    func save(gitHubId: Int64, username: String, avatarUrl: String?)
    func load() -> KeychainService.Session?
    func delete()
}

// MARK: - PersistenceServiceProtocol

protocol PersistenceServiceProtocol: AnyObject {
    func save(workflows: [WorkflowRun])
    func loadWorkflows() -> [WorkflowRun]
    func save(prs: [PullRequest])
    func loadPRs() -> [PullRequest]
}

// MARK: - OAuthServiceProtocol

protocol OAuthServiceProtocol: AnyObject {
    func startLogin(backendUrl: String) async throws -> (id: Int64, username: String, avatarUrl: String?)
}

// MARK: - ConflictWatcherServiceProtocol

protocol ConflictWatcherServiceProtocol: AnyObject {
    func start()
    func stop()
}
