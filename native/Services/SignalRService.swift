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
    private var readyNotifiedPRs: Set<String> = []
    /// First PR sync seeds the ready set silently (no notification burst on launch).
    private var didSeedReadyPRs = false

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
        let mapped = runs.map { toWorkflowRun($0) }
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
            let newPRs = unique.map(toPullRequest)
            notifyNewlyReadyPRs(current: newPRs)
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
        readyNotifiedPRs = []
        didSeedReadyPRs = false
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

    // MARK: - Mapping

    private func toWorkflowRun(_ r: ApiWorkflowRun) -> WorkflowRun {
        WorkflowRun(
            id: UUID(),
            dbId: r.id,
            runId: r.runId,
            workflowName: r.workflowName ?? "Workflow",
            repo: r.repo,
            actor: r.actor,
            headBranch: r.headBranch,
            trigger: r.trigger,
            prNumber: r.prNumber,
            prTitle: r.prTitle,
            status: r.status,
            htmlUrl: r.htmlUrl ?? "",
            startedAt: r.startedAt,
            completedAt: nil,
            targetGitHubIds: r.targetGitHubIds ?? []
        )
    }

    private func toPullRequest(_ pr: ApiPullRequest) -> PullRequest {
        PullRequest(
            prNumber: pr.prNumber, title: pr.title,
            repo: pr.repo,
            headBranch: pr.headBranch ?? "",
            baseBranch: pr.baseBranch ?? "",
            htmlUrl: URL(string: pr.htmlUrl ?? ""),
            status: pr.status ?? "open",
            conclusion: pr.conclusion,
            draft: pr.draft ?? false,
            mergeableState: pr.mergeableState,
            ciStatus: pr.ciStatus ?? "ready",
            reviewApproved: pr.reviewApproved ?? false,
            lastCommentBy: pr.lastCommentBy,
            lastCommentBody: pr.lastCommentBody,
            lastCommentAt: pr.lastCommentAt,
            lastCommentUrl: nil,
            lastReviewFilePath: nil,
            lastReviewLine: nil,
            isSubscribed: pr.isSubscribed ?? false,
            subscriberIds: pr.subscriberIds ?? [],
            authorGitHubId: pr.authorGitHubId
        )
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
                htmlUrl: e.htmlUrl ?? "", startedAt: startedAt(from: e.startedAt), completedAt: nil, targetGitHubIds: []
            )

            runningWorkflows.insert(run, at: 0)
            recentWorkflows.insert(run, at: 0)
            if recentWorkflows.count > 10 { recentWorkflows = Array(recentWorkflows.prefix(10)) }
        }
    }

    private func handleWorkflowCompleted(_ e: WorkflowCompletedEvent) {
        let runId = e.runId
        let succeeded = e.succeeded ?? false
        let conclusion = e.conclusion
        let name = e.workflowName
        let repo = e.repo
        let actor = e.actor ?? "someone"
        let htmlUrl = e.htmlUrl
        let trigger = e.trigger
        let workflowURL: URL? = URL(string: htmlUrl ?? "https://github.com/\(repo)/actions/runs/\(runId)")

        let isActualFailure = !succeeded && (conclusion == nil || conclusion == "failure")

        Task { @MainActor in
            if isActualFailure {
                runStatus = .failure
            } else if succeeded {
                runStatus = .success
            }
            if isActualFailure || succeeded { scheduleStatusReset() }

            if let idx = runningWorkflows.firstIndex(where: { $0.runId == runId }) {
                runningWorkflows.remove(at: idx)
            }

            if runningWorkflows.isEmpty && runStatus == .running {
                runStatus = .idle
                resetTask?.cancel()
            }

            let existing = recentWorkflows.first(where: { $0.runId == runId && $0.status == "in_progress" })
            let originalStartedAt = existing?.startedAt ?? Date()
            let completedAt = Date()

            let statusString: String
            if succeeded { statusString = "success" }
            else if let c = conclusion, c != "failure" { statusString = "cancelled" }
            else { statusString = "failure" }

            let completedRun = WorkflowRun(
                id: UUID(), dbId: existing?.dbId,
                runId: runId,
                workflowName: name ?? "Workflow",
                repo: repo,
                actor: actor,
                headBranch: existing?.headBranch,
                trigger: trigger ?? existing?.trigger,
                prNumber: existing?.prNumber,
                prTitle: existing?.prTitle,
                status: statusString,
                htmlUrl: htmlUrl ?? "https://github.com/\(repo)/actions/runs/\(runId)",
                startedAt: originalStartedAt,
                completedAt: completedAt,
                targetGitHubIds: existing?.targetGitHubIds ?? []
            )

            if let idx = recentWorkflows.firstIndex(where: { $0.runId == runId && $0.status == "in_progress" }) {
                recentWorkflows[idx] = completedRun
            } else {
                recentWorkflows.insert(completedRun, at: 0)
            }
            if recentWorkflows.count > 10 { recentWorkflows = Array(recentWorkflows.prefix(10)) }
            persistHistory()

            if isActualFailure {
                let wfName = name ?? "Workflow"
                lastEvent = PunishmentEvent(
                    culprit: actor, repo: repo, runId: runId,
                    workflowName: wfName,
                    workflowURL: workflowURL, date: Date()
                )
                showNotification(
                    title: "Workflow Failed",
                    body: "\(wfName) failed for \(actor) in \(shortRepo(repo))",
                    subtitle: "Run #\(runId)",
                    actionURL: workflowURL
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

    // MARK: - Ready-to-merge notifications

    /// A PR is "ready to merge" when it's open, not a draft, and CI + review are
    /// green (`ciStatus == "ready"` means approved + checks passing), and GitHub
    /// doesn't report conflicts.
    private func isReadyToMerge(_ pr: PullRequest) -> Bool {
        guard pr.status == "open", !pr.draft, !pr.isMerged else { return false }
        guard pr.ciStatus == "ready" else { return false }
        // If GitHub gives us a mergeable state, don't fire on conflicts/behind base.
        if let state = pr.mergeableState, state == "dirty" || state == "behind" { return false }
        return true
    }

    /// Fires a notification when a PR transitions INTO a ready-to-merge state.
    /// Runs on every PR sync (30s poll + SignalR events). The first sync only
    /// seeds the set so we don't spam notifications for already-ready PRs on launch.
    @MainActor
    private func notifyNewlyReadyPRs(current: [PullRequest]) {
        let currentIds = Set(current.map { $0.id })

        if !didSeedReadyPRs {
            didSeedReadyPRs = true
            readyNotifiedPRs = Set(current.filter { isReadyToMerge($0) }.map { $0.id })
            return
        }

        for pr in current where isReadyToMerge(pr) {
            if readyNotifiedPRs.insert(pr.id).inserted {
                showNotification(
                    title: "PR #\(pr.prNumber) ready to merge 🚀",
                    body: pr.title,
                    subtitle: shortRepo(pr.repo),
                    actionURL: pr.prUrl,
                    style: .info
                )
            }
        }
        // Allow re-notification if a PR stops being ready (e.g. new commits), and
        // forget PRs that are gone (merged/closed).
        readyNotifiedPRs = readyNotifiedPRs.intersection(currentIds)
        for pr in current where !isReadyToMerge(pr) {
            readyNotifiedPRs.remove(pr.id)
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

    // MARK: - Helpers

    private func startedAt(from string: String?) -> Date {
        (string).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
    }
}
