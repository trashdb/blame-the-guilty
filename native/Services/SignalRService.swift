import Combine
import Foundation

enum RunStatus: Equatable {
    case idle, running, success, failure
}

/// Facade orchestrator: owns observable UI state and domain rules, delegates
/// transport to `ApiClient` (REST) and `SignalRClient` (websocket).
class SignalRService: ObservableObject, SignalRServiceProtocol {
    @Published var isConnected = false
    @Published var isLoggedIn = false
    @Published var username = ""
    @Published var avatarUrl: String?
    @Published var userGitHubId: Int64 = 0
    @Published var runStatus: RunStatus = .idle
    @Published var lastEvent: PunishmentEvent?
    @Published var runningWorkflows: [WorkflowRun] = []
    @Published var recentWorkflows: [WorkflowRun] = []
    @Published var activePRs: [PullRequest] = []
    @Published var mainBranchUpdate: (repo: String, prNumber: Int, mergedBy: String, headSha: String?)?
    var onMainBranchUpdated: ((String, Int, String, String?) -> Void)?

    let baseUrl: String
    private let api: ApiClientProtocol
    private let signalRClient: SignalRClientProtocol
    private var task: Task<Void, Never>?
    private var gitHubId: Int64 = 0
    private var pollTask: Task<Void, Never>?
    /// Tracks PRs we've already notified as "ready to merge" so we don't re-notify
    /// on every 30s poll. A PR is removed once it's no longer ready, so it can
    /// notify again if it regresses (new commits) and becomes ready once more.
    private let readyNotifier: ReadyMergeNotifier

    private let keychain: KeychainServiceProtocol
    private let persistence: PersistenceServiceProtocol
    private let oauth: OAuthServiceProtocol

    init(
        baseUrl: String,
        keychain: KeychainServiceProtocol = LiveKeychainService(),
        persistence: PersistenceServiceProtocol = LivePersistenceService(),
        oauth: OAuthServiceProtocol = LiveOAuthService(),
        api: ApiClientProtocol? = nil,
        signalRClient: SignalRClientProtocol? = nil
    ) {
        self.baseUrl = baseUrl
        self.keychain = keychain
        self.persistence = persistence
        self.oauth = oauth
        self.api = api ?? LiveApiClient(baseUrl: baseUrl)
        self.signalRClient = signalRClient ?? LiveSignalRClient(baseUrl: baseUrl)
        self.readyNotifier = ReadyMergeNotifier { title, body, subtitle, url in
            showNotification(
                title: title,
                body: body,
                subtitle: subtitle,
                actionURL: url,
                style: .info
            )
        }
    }

    func restoreSession() {
        guard let session = keychain.load() else { return }
        userGitHubId = session.gitHubId
        username = session.username
        avatarUrl = session.avatarUrl
        isLoggedIn = true
        let gid = session.gitHubId

        // Show cached PRs immediately so the UI is not empty while loading
        activePRs = persistence.loadPRs()

        // Refresh workflows + avatar on every popover open
        Task {
            _ = await syncPRsFromGitHub(gitHubId: gid)
            await syncFromApi(gitHubId: gid)
            await syncPRsFromApi(gitHubId: gid)

            if let fresh = await api.fetchMe(gitHubId: gid), let url = fresh.avatarUrl {
                await MainActor.run { avatarUrl = url }
                keychain.save(gitHubId: gid, username: session.username, avatarUrl: url)
            }
        }

        guard task == nil else { return }
        connect(gitHubId: gid, username: session.username)
    }

    func login(keepSignedIn: Bool) async throws {
        let result = try await oauth.startLogin(backendUrl: baseUrl)
        await MainActor.run {
            userGitHubId = result.id
            username = result.username
            avatarUrl = result.avatarUrl
            isLoggedIn = true
            connect(gitHubId: result.id, username: result.username)
            if keepSignedIn {
                keychain.save(gitHubId: result.id, username: result.username, avatarUrl: result.avatarUrl)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func logout() {
        stopPolling()
        disconnect()
        keychain.delete()
        isLoggedIn = false
        username = ""
        avatarUrl = nil
        userGitHubId = 0
    }

    func connect(gitHubId: Int64, username: String = "") {
        self.gitHubId = gitHubId
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }

            _ = await syncPRsFromGitHub(gitHubId: gitHubId)
            await syncFromApi(gitHubId: gitHubId)
            await syncPRsFromApi(gitHubId: gitHubId)
            startPolling(gitHubId: gitHubId)

            while !Task.isCancelled {
                do {
                    try await self.signalRClient.connectAndListen(gitHubId: gitHubId, username: username) { [weak self] event in
                        self?.handle(event)
                    }
                } catch {
                    await MainActor.run { self.isConnected = false }
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
    }

    func syncFromApi(gitHubId: Int64) async {
        guard let runs = await api.fetchWorkflowRuns(gitHubId: gitHubId, limit: 20) else {
            await MainActor.run { loadPersistedHistory() }
            return
        }
        let mapped = runs.map(DTOMapper.workflowRun)
        await MainActor.run {
            runningWorkflows = mapped.filter { $0.status == "in_progress" }
            recentWorkflows = mapped
            persistHistory()
        }
    }

    func syncPRsFromApi(gitHubId: Int64) async {
        guard let prs = await api.fetchActivePRs(gitHubId: gitHubId) else { return }
        var seen = Set<String>()
        let unique = prs.filter { seen.insert("\($0.repo)#\($0.prNumber)").inserted }
        await MainActor.run {
            let newPRs = unique.map(DTOMapper.pullRequest)
            readyNotifier.process(current: newPRs)
            activePRs = newPRs
            persistence.save(prs: newPRs)
        }
    }

    func syncPRsFromGitHub(gitHubId: Int64) async -> Int {
        await api.syncPRsFromGitHub(gitHubId: gitHubId)
    }

    func subscribeToPR(prNumber: Int64, repo: String, gitHubId: Int64) async -> Bool {
        let ok = await api.subscribeToPR(prNumber: prNumber, repo: repo, gitHubId: gitHubId)
        if ok { await syncFromApi(gitHubId: gitHubId) }
        return ok
    }

    func unsubscribeFromPR(prNumber: Int64, repo: String, gitHubId: Int64) async -> Bool {
        let ok = await api.unsubscribeFromPR(prNumber: prNumber, repo: repo, gitHubId: gitHubId)
        if ok { await syncFromApi(gitHubId: gitHubId) }
        return ok
    }

    func syncActiveWorkflows(gitHubId: Int64) async -> Int {
        let synced = await api.syncActiveWorkflows(gitHubId: gitHubId)
        if synced > 0 {
            await syncFromApi(gitHubId: gitHubId)
            await syncPRsFromApi(gitHubId: gitHubId)
        }
        return synced
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        task?.cancel()
        task = nil
        readyNotifier.reset()
        Task { @MainActor in
            isConnected = false
            runStatus = .idle
            lastEvent = nil
            runningWorkflows = []
            activePRs = []
        }
    }

    func startPolling(gitHubId: Int64) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.syncPRsFromApi(gitHubId: gitHubId)
            }
        }
    }

    // MARK: - SignalR events

    private func handle(_ event: HubEvent) {
        switch event {
        case .workflowStarted(let e): handleWorkflowStarted(e)
        case .workflowCompleted(let e): handleWorkflowCompleted(e)
        case .pullRequestsUpdated:
            Task { await self.syncPRsFromApi(gitHubId: self.gitHubId) }
        case .prApproved(let e): handlePrApproved(e)
        case .prCommented(let e): handlePrCommented(e)
        case .mainBranchUpdated(let e): handleMainBranchUpdated(e)
        case .connectionClosed:
            Task { @MainActor in self.isConnected = false }
        }
    }

    private func handleWorkflowStarted(_ e: WorkflowStartedEvent) {
        Task { @MainActor in
            runStatus = .running

            let run = WorkflowRun(
                id: UUID(), dbId: e.id,
                runId: e.runId, workflowName: e.workflowName ?? "Workflow", repo: e.repo,
                actor: e.actor ?? "someone", headBranch: e.branch,
                trigger: e.trigger, prNumber: nil, prTitle: nil,
                status: "in_progress",
                htmlUrl: e.htmlUrl ?? "", startedAt: DTOMapper.startedDate(from: e.startedAt), completedAt: nil, targetGitHubIds: []
            )

            runningWorkflows.insert(run, at: 0)
            recentWorkflows.insert(run, at: 0)
            if recentWorkflows.count > 10 { recentWorkflows = Array(recentWorkflows.prefix(10)) }
        }
    }

    private func handleWorkflowCompleted(_ e: WorkflowCompletedEvent) {
        Task { @MainActor in
            let update = WorkflowEventReducer.reduceCompleted(
                e,
                runningWorkflows: runningWorkflows,
                recentWorkflows: recentWorkflows
            )

            if let status = update.runStatus {
                runStatus = status
            }
            if update.shouldResetStatus { scheduleStatusReset() }

            runningWorkflows = update.runningWorkflows
            recentWorkflows = update.recentWorkflows
            persistHistory()

            if runningWorkflows.isEmpty && runStatus == .running {
                runStatus = .idle
                resetTask?.cancel()
            }

            if let event = update.lastEvent {
                lastEvent = event
            }
            if let n = update.notification {
                showNotification(
                    title: n.title,
                    body: n.body,
                    subtitle: n.subtitle,
                    actionURL: n.url
                )
            }
        }
    }

    private func handlePrApproved(_ e: PrEvent) {
        let prNumber = e.prNumber ?? 0
        let repo = e.repo ?? "unknown"
        let reviewerLogin = e.reviewerLogin ?? "someone"
        let title = e.title ?? ""

        Task { @MainActor in
            let body = "\(title) — approved by \(reviewerLogin)"
            showNotification(
                title: "PR #\(prNumber) Approved ✅",
                body: body,
                subtitle: shortRepo(repo),
                actionURL: URL(string: "https://github.com/\(repo)/pull/\(prNumber)"),
                style: .info
            )
            await self.syncPRsFromApi(gitHubId: self.gitHubId)
        }
    }

    private func handlePrCommented(_ e: PrCommentedEvent) {
        let prNumber = e.prNumber ?? 0
        let repo = e.repo ?? "unknown"
        let commenterLogin = e.commenterLogin ?? "someone"
        let title = e.title ?? ""
        let commentUrl = e.commentUrl.flatMap { URL(string: $0) }

        Task { @MainActor in
            let preview = String((e.commentBody ?? "").prefix(120)).replacingOccurrences(of: "\n", with: " ")
            let body = "\(title) — \(commenterLogin): \(preview)"
            showNotification(
                title: "PR #\(prNumber) Commented 💬",
                body: body,
                subtitle: shortRepo(repo),
                actionURL: commentUrl ?? URL(string: "https://github.com/\(repo)/pull/\(prNumber)"),
                style: .info
            )
            await self.syncPRsFromApi(gitHubId: self.gitHubId)
        }
    }

    private func handleMainBranchUpdated(_ e: MainBranchUpdatedEvent) {
        let repo = e.repo ?? ""
        let prNumber = e.prNumber ?? 0
        let mergedBy = e.mergedBy ?? ""
        let headSha = e.headSha

        Task { @MainActor in
            mainBranchUpdate = (repo, prNumber, mergedBy, headSha)
            onMainBranchUpdated?(repo, prNumber, mergedBy, headSha)
        }
    }

    // MARK: - Persistence

    func setTargetGitHubIds(for dbId: Int, targetIds: [Int64]) {
        Task { @MainActor in
            for i in recentWorkflows.indices where recentWorkflows[i].dbId == dbId {
                let old = recentWorkflows[i]
                recentWorkflows[i] = WorkflowRun(
                    id: old.id, dbId: old.dbId,
                    runId: old.runId,
                    workflowName: old.workflowName, repo: old.repo,
                    actor: old.actor, headBranch: old.headBranch,
                    trigger: old.trigger, prNumber: old.prNumber, prTitle: old.prTitle,
                    status: old.status,
                    htmlUrl: old.htmlUrl, startedAt: old.startedAt,
                    completedAt: old.completedAt,
                    targetGitHubIds: targetIds
                )
            }
            for i in runningWorkflows.indices where runningWorkflows[i].dbId == dbId {
                let old = runningWorkflows[i]
                runningWorkflows[i] = WorkflowRun(
                    id: old.id, dbId: old.dbId,
                    runId: old.runId,
                    workflowName: old.workflowName, repo: old.repo,
                    actor: old.actor, headBranch: old.headBranch,
                    trigger: old.trigger, prNumber: old.prNumber, prTitle: old.prTitle,
                    status: old.status,
                    htmlUrl: old.htmlUrl, startedAt: old.startedAt,
                    completedAt: old.completedAt,
                    targetGitHubIds: targetIds
                )
            }
        }
    }

    private func loadPersistedHistory() {
        let saved = persistence.loadWorkflows()
        if !saved.isEmpty {
            recentWorkflows = saved.map { run in
                if run.status == "in_progress" {
                    return WorkflowRun(
                        id: run.id, dbId: run.dbId,
                        runId: run.runId,
                        workflowName: run.workflowName,
                        repo: run.repo, actor: run.actor,
                        headBranch: run.headBranch,
                        trigger: run.trigger,
                        prNumber: run.prNumber,
                        prTitle: run.prTitle,
                        status: "cancelled",
                        htmlUrl: run.htmlUrl, startedAt: run.startedAt,
                        completedAt: nil,
                        targetGitHubIds: run.targetGitHubIds
                    )
                }
                return run
            }
        }
    }

    private func persistHistory() {
        persistence.save(workflows: recentWorkflows)
    }

    // MARK: - Status reset

    private var resetTask: Task<Void, Never>?
    private func scheduleStatusReset() {
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            runStatus = .idle
        }
    }
}
