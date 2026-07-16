import Combine
import Foundation

private struct ApiWorkflowRun: Decodable {
    let id: Int
    let runId: Int64
    let workflowName: String?
    let repo: String
    let actor: String
    let headBranch: String?
    let trigger: String?
    let prNumber: Int?
    let prTitle: String?
    let status: String
    let htmlUrl: String?
    let startedAt: Date
    let targetGitHubIds: [Int64]?

    func toWorkflowRun() -> WorkflowRun {
        WorkflowRun(
            id: UUID(),
            dbId: id,
            runId: runId,
            workflowName: workflowName ?? "Workflow",
            repo: repo,
            actor: actor,
            headBranch: headBranch,
            trigger: trigger,
            prNumber: prNumber,
            prTitle: prTitle,
            status: status,
            htmlUrl: htmlUrl ?? "",
            startedAt: startedAt,
            completedAt: nil,
            targetGitHubIds: targetGitHubIds ?? []
        )
    }
}

enum RunStatus: Equatable {
    case idle, running, success, failure
}

class SignalRService: ObservableObject {
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
    private var task: Task<Void, Never>?
    private var gitHubId: Int64 = 0
    private var pollTask: Task<Void, Never>?

    init(baseUrl: String) {
        self.baseUrl = baseUrl
    }

    func restoreSession() {
        guard let session = KeychainService.load() else { return }
        userGitHubId = session.gitHubId
        username = session.username
        avatarUrl = session.avatarUrl
        isLoggedIn = true
        let gid = session.gitHubId

        // Refresh workflows + avatar on every popover open
        Task {
            await syncFromApi(gitHubId: gid)
            await syncPRsFromApi(gitHubId: gid)

            if let fresh = await fetchMe(gitHubId: gid), let url = fresh.avatarUrl {
                await MainActor.run { avatarUrl = url }
                KeychainService.save(gitHubId: gid, username: session.username, avatarUrl: url)
            }
        }

        guard task == nil else { return }
        connect(gitHubId: gid, username: session.username)
    }

    private struct MeResponse: Decodable {
        let id: Int64
        let username: String
        let avatarUrl: String?
    }

    private func fetchMe(gitHubId: Int64) async -> MeResponse? {
        guard let url = URL(string: "\(baseUrl)/api/auth/me?gitHubId=\(gitHubId)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return try? JSONDecoder().decode(MeResponse.self, from: data)
    }

    func login(keepSignedIn: Bool) async throws {
        let oauth = OAuthService()
        let result = try await oauth.startLogin(backendUrl: baseUrl)
        await MainActor.run {
            userGitHubId = result.id
            username = result.username
            avatarUrl = result.avatarUrl
            isLoggedIn = true
            connect(gitHubId: result.id, username: result.username)
            if keepSignedIn {
                KeychainService.save(gitHubId: result.id, username: result.username, avatarUrl: result.avatarUrl)
            }
        }
    }

    func logout() {
        disconnect()
        KeychainService.delete()
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

            await syncFromApi(gitHubId: gitHubId)
            await syncPRsFromApi(gitHubId: gitHubId)
            startPolling(gitHubId: gitHubId)

            while !Task.isCancelled {
                do {
                    try await connectAndListen(gitHubId: gitHubId, username: username)
                } catch {
                    await MainActor.run { self.isConnected = false }
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
    }

    func syncFromApi(gitHubId: Int64) async {
        guard let url = URL(string: "\(baseUrl)/api/workflows/runs?gitHubId=\(gitHubId)&limit=20") else {
            await MainActor.run { loadPersistedHistory() }
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let withoutFrac = ISO8601DateFormatter()
            withoutFrac.formatOptions = .withInternetDateTime
            decoder.dateDecodingStrategy = .custom { d in
                let container = try d.singleValueContainer()
                var str = try container.decode(String.self)
                // Normalize: replace space separator with T, append Z if no timezone
                str = str.replacingOccurrences(of: " ", with: "T")
                if !str.contains("Z") && !str.contains("+") {
                    // No timezone indicator — assume UTC
                    str += "Z"
                }
                guard let date = withFrac.date(from: str) ?? withoutFrac.date(from: str) else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(str)")
                }
                return date
            }
            if let runs = try? decoder.decode([ApiWorkflowRun].self, from: data) {
                let mapped = runs.map { $0.toWorkflowRun() }
                await MainActor.run {
                    runningWorkflows = mapped.filter { $0.status == "in_progress" }
                    recentWorkflows = mapped
                    persistHistory()
                }
                return
            }
        } catch {}
        await MainActor.run { loadPersistedHistory() }
    }

    private func syncPRsFromApi(gitHubId: Int64) async {
        guard let url = URL(string: "\(baseUrl)/api/pullrequests/active?gitHubId=\(gitHubId)") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct ApiPR: Decodable {
                let prNumber: Int64
                let title: String
                let repo: String
                let headBranch: String?
                let baseBranch: String?
                let htmlUrl: String?
                let status: String?
                let conclusion: String?
                let draft: Bool?
                let mergeableState: String?
                let ciStatus: String?
                let reviewApproved: Bool?
                let lastCommentBy: String?
                let lastCommentBody: String?
                let lastCommentAt: Date?
            }
            if let prs = try? JSONDecoder().decode([ApiPR].self, from: data) {
                await MainActor.run {
                    activePRs = prs.map { pr in
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
                            lastCommentAt: pr.lastCommentAt
                        )
                    }
                }
            }
        } catch {}
    }

    private func loadPersistedHistory() {
        let saved = PersistenceService.load()
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
        PersistenceService.save(workflows: recentWorkflows)
    }

    private var hubWebSocketUrl: URL {
        let wsUrl = baseUrl
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        return URL(string: "\(wsUrl)/hub/punishment")!
    }

    private func connectAndListen(gitHubId: Int64, username: String) async throws {
        await syncFromApi(gitHubId: gitHubId)
        await syncPRsFromApi(gitHubId: gitHubId)
        let url = hubWebSocketUrl
        let ws = URLSession.shared.webSocketTask(with: url)
        ws.resume()
        defer { ws.cancel(with: .normalClosure, reason: nil) }

        try await ws.send(.string("{\"protocol\":\"json\",\"version\":1}\u{1e}"))
        guard case .string = try await ws.receive() else { throw SignalRError.handshakeFailed }

        let register = "{\"type\":1,\"target\":\"RegisterConnection\",\"arguments\":[\(gitHubId),\"\(username)\"],\"invocationId\":\"1\"}\u{1e}"
        try await ws.send(.string(register))

        await MainActor.run { self.isConnected = true }

        try await listen(ws)
    }

    private func listen(_ ws: URLSessionWebSocketTask) async throws {
        while !Task.isCancelled {
            let message = try await ws.receive()
            handleMessage(message, webSocket: ws)
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message, webSocket ws: URLSessionWebSocketTask) {
        guard case .string(let text) = message else { return }

        for part in text.components(separatedBy: "\u{1e}").filter({ !$0.isEmpty }) {
            guard let data = part.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? Int else { continue }

            switch type {
            case 1:
                handleInvocation(json)
            case 6:
                Task { try? await ws.send(.string("{\"type\":6}\u{1e}")) }
            case 7:
                Task { @MainActor in self.isConnected = false }
            default:
                break
            }
        }
    }

    private func handleInvocation(_ json: [String: Any]) {
        guard let target = json["target"] as? String else { return }

        switch target {
        case "WorkflowRunStarted", "WorkflowRunCompleted":
            guard let args = json["arguments"] as? [[String: Any]],
                  let data = args.first else { return }
            if target == "WorkflowRunStarted" { handleWorkflowStarted(data) }
            else { handleWorkflowCompleted(data) }
        case "PullRequestsUpdated":
            Task { await self.syncPRsFromApi(gitHubId: self.gitHubId) }
        case "PrApproved":
            guard let args = json["arguments"] as? [[String: Any]],
                  let data = args.first else { return }
            handlePrApproved(data)
        case "PrCommented":
            guard let args = json["arguments"] as? [[String: Any]],
                  let data = args.first else { return }
            handlePrCommented(data)
        case "MainBranchUpdated":
            guard let args = json["arguments"] as? [[String: Any]],
                  let data = args.first else { return }
            handleMainBranchUpdated(data)
        default: break
        }
    }

    private func handleWorkflowStarted(_ data: [String: Any]) {
        let runId      = data["runId"] as? Int64 ?? 0
        let dbId       = data["id"] as? Int
        let name       = data["workflowName"] as? String ?? "Unknown"
        let repo       = data["repo"] as? String ?? "unknown"
        let actor      = data["actor"] as? String ?? "someone"
        let htmlUrl    = data["htmlUrl"] as? String ?? ""
        let startedAt  = (data["startedAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        let branch     = data["branch"] as? String
        let trigger    = data["trigger"] as? String

        Task { @MainActor in
            runStatus = .running

            let run = WorkflowRun(
                id: UUID(), dbId: dbId,
                runId: runId, workflowName: name, repo: repo,
                actor: actor, headBranch: branch,
                trigger: trigger, prNumber: nil, prTitle: nil,
                status: "in_progress",
                htmlUrl: htmlUrl, startedAt: startedAt, completedAt: nil, targetGitHubIds: []
            )

            runningWorkflows.insert(run, at: 0)
            recentWorkflows.insert(run, at: 0)
            if recentWorkflows.count > 10 { recentWorkflows = Array(recentWorkflows.prefix(10)) }
        }
    }

    private func handleWorkflowCompleted(_ data: [String: Any]) {
        let runId      = data["runId"] as? Int64 ?? 0
        let succeeded  = data["succeeded"] as? Bool ?? false
        let conclusion = data["conclusion"] as? String
        let name       = data["workflowName"] as? String
        let repo       = data["repo"] as? String ?? "unknown"
        let actor      = data["actor"] as? String ?? "someone"
        let htmlUrl    = data["htmlUrl"] as? String
        let trigger    = data["trigger"] as? String
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

    private func handlePrApproved(_ data: [String: Any]) {
        let prNumber = data["prNumber"] as? Int ?? 0
        let repo = data["repo"] as? String ?? "unknown"
        let reviewerLogin = data["reviewerLogin"] as? String ?? "someone"
        let title = data["title"] as? String ?? ""

        Task { @MainActor in
            let body = "\(title) — approved by \(reviewerLogin)"
            showNotification(
                title: "PR #\(prNumber) Approved ✅",
                body: body,
                subtitle: shortRepo(repo),
                actionURL: URL(string: "https://github.com/\(repo)/pull/\(prNumber)"),
                style: .info
            )
            await syncPRsFromApi(gitHubId: gitHubId)
        }
    }

    private func handlePrCommented(_ data: [String: Any]) {
        let prNumber = data["prNumber"] as? Int ?? 0
        let repo = data["repo"] as? String ?? "unknown"
        let commenterLogin = data["commenterLogin"] as? String ?? "someone"
        let title = data["title"] as? String ?? ""
        let commentBody = data["commentBody"] as? String ?? ""

        Task { @MainActor in
            let preview = String(commentBody.prefix(120)).replacingOccurrences(of: "\n", with: " ")
            let body = "\(title) — \(commenterLogin): \(preview)"
            showNotification(
                title: "PR #\(prNumber) Commented 💬",
                body: body,
                subtitle: shortRepo(repo),
                actionURL: URL(string: "https://github.com/\(repo)/pull/\(prNumber)"),
                style: .info
            )
            await syncPRsFromApi(gitHubId: gitHubId)
        }
    }

    private func handleMainBranchUpdated(_ data: [String: Any]) {
        let repo = data["repo"] as? String ?? ""
        let prNumber = data["prNumber"] as? Int ?? 0
        let mergedBy = data["mergedBy"] as? String ?? ""
        let headSha = data["headSha"] as? String

        Task { @MainActor in
            mainBranchUpdate = (repo, prNumber, mergedBy, headSha)
            onMainBranchUpdated?(repo, prNumber, mergedBy, headSha)
        }
    }

    private var resetTask: Task<Void, Never>?
    private func scheduleStatusReset() {
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            runStatus = .idle
        }
    }

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

    func syncActiveWorkflows(gitHubId: Int64) async -> Int {
        guard let url = URL(string: "\(baseUrl)/api/workflows/sync-active?gitHubId=\(gitHubId)") else { return 0 }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            struct SyncResult: Decodable { let synced: Int }
            if let result = try? JSONDecoder().decode(SyncResult.self, from: data) {
                await syncFromApi(gitHubId: gitHubId)
                await syncPRsFromApi(gitHubId: gitHubId)
                return result.synced
            }
        } catch {}
        return 0
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        task?.cancel()
        task = nil
        Task { @MainActor in
            isConnected = false
            runStatus = .idle
            lastEvent = nil
            runningWorkflows = []
            activePRs = []
        }
    }

    private func startPolling(gitHubId: Int64) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled, let self else { return }
                await syncPRsFromApi(gitHubId: gitHubId)
            }
        }
    }

    enum SignalRError: Error {
        case handshakeFailed
    }
}
