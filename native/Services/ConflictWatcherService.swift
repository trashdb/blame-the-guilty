import Foundation
import OSLog

private let conflictLog = OSLog(subsystem: "com.blametheguilty", category: "conflicts")

class ConflictWatcherService {
    private weak var signalR: SignalRService?
    private let gitService = GitService()
    private var pollTask: Task<Void, Never>?
    private var lastKnownMainSha: [String: String] = [:]
    private var recentlyNotified: Set<String> = []
    private var notifyResetTask: Task<Void, Never>?

    init(signalR: SignalRService) {
        self.signalR = signalR
    }

    func start() {
        // Listen for real-time updates from SignalR
        signalR?.onMainBranchUpdated = { [weak self] repo, prNumber, mergedBy, headSha in
            os_log("[ConflictWatcher] MainBranchUpdated: %{public}@ PR #%d by %{public}@",
                   log: conflictLog, type: .debug, repo, prNumber, mergedBy)
            self?.handleMerge(repo: repo)
        }

        // Background polling every 60s as fallback
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await self?.checkAllRepos()
            }
        }

        os_log("[ConflictWatcher] Started", log: conflictLog, type: .info)
    }

    func stop() {
        signalR?.onMainBranchUpdated = nil
        pollTask?.cancel()
        pollTask = nil
        notifyResetTask?.cancel()
        notifyResetTask = nil
    }

    // Called when a real-time merge event arrives
    private func handleMerge(repo: String) {
        let workspacePath = UserDefaults.standard.string(forKey: "workspacePath") ?? "\(NSHomeDirectory())/Desktop/dev"
        Task {
            guard let repoPath = await gitService.findRepoPath(ownerRepo: repo, workspacePath: workspacePath) else {
                os_log("[ConflictWatcher] Repo not found locally: %{public}@", log: conflictLog, type: .debug, repo)
                return
            }
            await checkRepo(repoPath: repoPath, fullName: repo)
        }
    }

    private func checkAllRepos() async {
        let workspacePath = UserDefaults.standard.string(forKey: "workspacePath") ?? "\(NSHomeDirectory())/Desktop/dev"
        let repos = GitService.discoverRepos(workspacePath: workspacePath)
        for repoPath in repos {
            let fullName = await gitService.repoFullName(repoPath: repoPath) ?? GitService.repoName(from: repoPath)
            await checkRepo(repoPath: repoPath, fullName: fullName)
        }
    }

    private func checkRepo(repoPath: String, fullName: String) async {
        os_log("[ConflictWatcher] Checking %{public}@", log: conflictLog, type: .debug, fullName)

        // Try to compute current main SHA even if fetch fails
        let result = await gitService.fetchMainAndGetDiff(repoPath: repoPath, lastKnownSha: lastKnownMainSha[repoPath])

        if let (currentSha, changedFiles) = result {
            lastKnownMainSha[repoPath] = currentSha

            if !changedFiles.isEmpty {
                os_log("[ConflictWatcher] %{public}@: %d files changed in main since last check",
                       log: conflictLog, type: .debug, fullName, changedFiles.count)

                let uncommitted = await gitService.getUncommittedFiles(repoPath: repoPath)
                let currentBranch = await gitService.currentBranchName(repoPath: repoPath)

                // 1. Check uncommitted changes overlap
                if !uncommitted.isEmpty {
                    let overlap = Set(uncommitted).intersection(changedFiles)
                    for file in overlap.sorted() {
                        notifyConflict(repo: fullName, file: file, kind: .uncommitted)
                    }
                }

                // 2. Check branch diff overlap (if not on main)
                if let branch = currentBranch, branch != "main" && branch != "master" {
                    let baseRef = await gitService.baseRefName(repoPath: repoPath) ?? "origin/main"
                    let branchFiles = await gitService.getBranchFilesAgainstBase(repoPath: repoPath, baseRef: baseRef)
                    if !branchFiles.isEmpty {
                        let overlap = Set(branchFiles).intersection(changedFiles)
                        for file in overlap.sorted() {
                            notifyConflict(repo: fullName, file: file, kind: .branch(branch))
                        }
                    }
                }
            }
        }
        // If fetchMainAndGetDiff returned nil (e.g. no origin/main yet), just skip silently.
        // Next poll will retry.
    }

    private enum ConflictKind {
        case uncommitted
        case branch(String)

        var title: String {
            switch self {
            case .uncommitted:
                return "⚠️ Possible conflict — local changes"
            case .branch(let name):
                return "⚠️ Possible conflict — \(name)"
            }
        }

        func body(repo: String, file: String) -> String {
            switch self {
            case .uncommitted:
                return "\(shortRepo(repo)): someone merged changes in \(file) — you have uncommitted changes there"
            case .branch:
                return "\(shortRepo(repo)): someone merged changes in \(file) — your branch also touches it"
            }
        }
    }

    private func notifyConflict(repo: String, file: String, kind: ConflictKind) {
        let key = "\(repo):\(file):\(kind.title)"
        guard !recentlyNotified.contains(key) else { return }
        recentlyNotified.insert(key)

        // Reset dedup after 5 minutes
        notifyResetTask?.cancel()
        notifyResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000_000)
            await MainActor.run { self?.recentlyNotified.remove(key) }
        }

        Task { @MainActor in
            showNotification(
                title: kind.title,
                body: kind.body(repo: repo, file: file),
                style: .info
            )
        }

        os_log("[ConflictWatcher] Notification: %{public}@ — %{public}@",
               log: conflictLog, type: .info, kind.title, kind.body(repo: repo, file: file))
    }
}
