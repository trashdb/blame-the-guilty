import Combine
import Foundation

private struct ApiWorkflowRun: Decodable {
    let id: Int
    let runId: Int64
    let workflowName: String?
    let repo: String
    let actor: String
    let headBranch: String?
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
            status: status,
            htmlUrl: htmlUrl ?? "",
            startedAt: startedAt,
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

    private let baseUrl: String
    private var task: Task<Void, Never>?
    private var gitHubId: Int64 = 0

    init(baseUrl: String) {
        self.baseUrl = baseUrl
    }

    func restoreSession() {
        guard let session = KeychainService.load() else { return }
        userGitHubId = session.gitHubId
        username = session.username
        avatarUrl = session.avatarUrl
        isLoggedIn = true
        connect(gitHubId: session.gitHubId, username: session.username)
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
                let str = try container.decode(String.self)
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
                            ciStatus: pr.ciStatus ?? "ready"
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
                        status: "failure",
                        htmlUrl: run.htmlUrl, startedAt: run.startedAt,
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

        Task { @MainActor in
            runStatus = .running

            let run = WorkflowRun(
                id: UUID(), dbId: dbId,
                runId: runId, workflowName: name, repo: repo,
                actor: actor, headBranch: branch, status: "in_progress",
                htmlUrl: htmlUrl, startedAt: startedAt, targetGitHubIds: []
            )

            runningWorkflows.insert(run, at: 0)
            recentWorkflows.insert(run, at: 0)
            if recentWorkflows.count > 10 { recentWorkflows = Array(recentWorkflows.prefix(10)) }
        }
    }

    private func handleWorkflowCompleted(_ data: [String: Any]) {
        let runId      = data["runId"] as? Int64 ?? 0
        let succeeded  = data["succeeded"] as? Bool ?? false
        let name       = data["workflowName"] as? String
        let repo       = data["repo"] as? String ?? "unknown"
        let actor      = data["actor"] as? String ?? "someone"
        let htmlUrl    = data["htmlUrl"] as? String
        let workflowURL: URL? = URL(string: htmlUrl ?? "https://github.com/\(repo)/actions/runs/\(runId)")

        Task { @MainActor in
            runStatus = succeeded ? .success : .failure
            scheduleStatusReset()

            if let idx = runningWorkflows.firstIndex(where: { $0.runId == runId }) {
                runningWorkflows.remove(at: idx)
            }

            let existing = recentWorkflows.first(where: { $0.runId == runId && $0.status == "in_progress" })
            let originalStartedAt = existing?.startedAt ?? Date()
            let completedRun = WorkflowRun(
                id: UUID(), dbId: existing?.dbId,
                runId: runId,
                workflowName: name ?? "Workflow",
                repo: repo,
                actor: actor,
                headBranch: existing?.headBranch,
                status: succeeded ? "success" : "failure",
                htmlUrl: htmlUrl ?? "https://github.com/\(repo)/actions/runs/\(runId)",
                startedAt: originalStartedAt,
                targetGitHubIds: existing?.targetGitHubIds ?? []
            )

            if let idx = recentWorkflows.firstIndex(where: { $0.runId == runId && $0.status == "in_progress" }) {
                recentWorkflows[idx] = completedRun
            } else {
                recentWorkflows.insert(completedRun, at: 0)
            }
            if recentWorkflows.count > 10 { recentWorkflows = Array(recentWorkflows.prefix(10)) }
            persistHistory()

            let wfName = name ?? "Workflow"
            if !succeeded {
                lastEvent = PunishmentEvent(
                    culprit: actor, repo: repo, runId: runId,
                    workflowName: wfName,
                    workflowURL: workflowURL, date: Date()
                )
                showNotification(
                    title: "Workflow Failed",
                    body: "\(wfName) failed for \(actor) in \(repo)",
                    subtitle: "Run #\(runId)",
                    actionURL: workflowURL
                )
            }
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
                    actor: old.actor, headBranch: old.headBranch, status: old.status,
                    htmlUrl: old.htmlUrl, startedAt: old.startedAt,
                    targetGitHubIds: targetIds
                )
            }
            for i in runningWorkflows.indices where runningWorkflows[i].dbId == dbId {
                let old = runningWorkflows[i]
                runningWorkflows[i] = WorkflowRun(
                    id: old.id, dbId: old.dbId,
                    runId: old.runId,
                    workflowName: old.workflowName, repo: old.repo,
                    actor: old.actor, headBranch: old.headBranch, status: old.status,
                    htmlUrl: old.htmlUrl, startedAt: old.startedAt,
                    targetGitHubIds: targetIds
                )
            }
        }
    }

    func disconnect() {
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

    enum SignalRError: Error {
        case handshakeFailed
    }
}
