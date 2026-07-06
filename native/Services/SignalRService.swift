import Combine
import Foundation

private struct ApiWorkflowRun: Decodable {
    let runId: Int64
    let workflowName: String?
    let repo: String
    let actor: String
    let status: String
    let htmlUrl: String?
    let startedAt: Date

    func toWorkflowRun() -> WorkflowRun {
        WorkflowRun(
            id: UUID(),
            runId: runId,
            workflowName: workflowName ?? "Workflow",
            repo: repo,
            actor: actor,
            status: status,
            htmlUrl: htmlUrl ?? "",
            startedAt: startedAt
        )
    }
}

enum RunStatus: Equatable {
    case idle, running, success, failure
}

class SignalRService: ObservableObject {
    @Published var isConnected = false
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

    private func syncPRsFromApi(gitHubId: Int64) async {
        guard let url = URL(string: "\(baseUrl)/api/pullrequests/active?gitHubId=\(gitHubId)") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct ApiPR: Decodable {
                let prNumber: Int64
                let title: String
                let repoFullName: String
                let headBranch: String?
                let baseBranch: String?
                let prUrl: String?
                let status: String?
                let conclusion: String?
            }
            if let prs = try? JSONDecoder().decode([ApiPR].self, from: data) {
                await MainActor.run {
                    activePRs = prs.map { pr in
                        PullRequest(
                            prNumber: pr.prNumber, title: pr.title,
                            repo: pr.repoFullName,
                            headBranch: pr.headBranch ?? "",
                            baseBranch: pr.baseBranch ?? "",
                            htmlUrl: URL(string: pr.prUrl ?? ""),
                            status: pr.status ?? "open",
                            conclusion: pr.conclusion
                        )
                    }
                }
            }
        } catch {}
    }

    private func syncFromApi(gitHubId: Int64) async {
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

    private func loadPersistedHistory() {
        let saved = PersistenceService.load()
        if !saved.isEmpty {
            recentWorkflows = saved.map { run in
                if run.status == "in_progress" {
                    return WorkflowRun(
                        id: run.id, runId: run.runId,
                        workflowName: run.workflowName,
                        repo: run.repo, actor: run.actor,
                        status: "failure",
                        htmlUrl: run.htmlUrl, startedAt: run.startedAt
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
        guard let target = json["target"] as? String,
              let args = json["arguments"] as? [[String: Any]],
              let data = args.first else { return }

        switch target {
        case "WorkflowRunStarted":       handleWorkflowStarted(data)
        case "WorkflowRunCompleted":     handleWorkflowCompleted(data)
        case "PullRequestOpened":        handlePROpened(data)
        case "PullRequestChecksCompleted": handlePRChecksCompleted(data)
        case "PullRequestMerged":        handlePRMerged(data)
        case "PullRequestClosed":        handlePRClosed(data)
        case "PullRequestReviewRequested": handlePRReviewRequested(data)
        case "PullRequestComment":       handlePRComment(data)
        default: break
        }
    }

    private func handleWorkflowStarted(_ data: [String: Any]) {
        let runId      = data["runId"] as? Int64 ?? 0
        let name       = data["workflowName"] as? String ?? "Unknown"
        let repo       = data["repo"] as? String ?? "unknown"
        let actor      = data["actor"] as? String ?? "someone"
        let htmlUrl    = data["htmlUrl"] as? String ?? ""
        let startedAt  = (data["startedAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()

        Task { @MainActor in
            runStatus = .running

            let run = WorkflowRun(
                id: UUID(), runId: runId, workflowName: name, repo: repo,
                actor: actor, status: "in_progress",
                htmlUrl: htmlUrl, startedAt: startedAt
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

            let originalStartedAt = recentWorkflows.first(where: { $0.runId == runId })?.startedAt ?? Date()
            let completedRun = WorkflowRun(
                id: UUID(), runId: runId,
                workflowName: name ?? "Workflow",
                repo: repo,
                actor: actor,
                status: succeeded ? "success" : "failure",
                htmlUrl: htmlUrl ?? "https://github.com/\(repo)/actions/runs/\(runId)",
                startedAt: originalStartedAt
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

    // MARK: - PR handlers

    private func makePR(from data: [String: Any]) -> PullRequest? {
        guard let prNumber = data["prNumber"] as? Int64,
              let title = data["title"] as? String,
              let repo = data["repo"] as? String else { return nil }
        let headBranch = data["headBranch"] as? String ?? ""
        let baseBranch = data["baseBranch"] as? String ?? ""
        let htmlUrl = (data["htmlUrl"] as? String).flatMap { URL(string: $0) }
        let status = data["status"] as? String ?? "open"
        let conclusion = data["conclusion"] as? String
        return PullRequest(
            prNumber: prNumber, title: title, repo: repo,
            headBranch: headBranch, baseBranch: baseBranch,
            htmlUrl: htmlUrl, status: status, conclusion: conclusion
        )
    }

    private func handlePROpened(_ data: [String: Any]) {
        guard let pr = makePR(from: data) else { return }
        Task { @MainActor in
            if !activePRs.contains(where: { $0.prNumber == pr.prNumber && $0.repo == pr.repo }) {
                activePRs.insert(pr, at: 0)
            }
            showNotification(
                title: "PR Opened",
                body: "\(pr.title) — \(pr.repo)#\(pr.prNumber)",
                subtitle: "Targeting \(pr.baseBranch)",
                actionURL: pr.prUrl
            )
        }
    }

    private func handlePRChecksCompleted(_ data: [String: Any]) {
        let prNumber = data["prNumber"] as? Int64 ?? 0
        let conclusion = data["conclusion"] as? String ?? "unknown"
        let repo = data["repo"] as? String ?? "unknown"
        let prStatus = data["status"] as? String ?? "open"

        let url = URL(string: "https://github.com/\(repo)/pull/\(prNumber)")
        let titleText = "PR \(conclusion == "success" ? "Ready for Merge" : "Checks Failed")"
        let body = "PR #\(prNumber) in \(repo) — \(conclusion)"

        Task { @MainActor in
            if let idx = activePRs.firstIndex(where: { $0.prNumber == prNumber && $0.repo == repo }) {
                let pr = activePRs[idx]
                activePRs[idx] = PullRequest(
                    prNumber: pr.prNumber, title: pr.title, repo: pr.repo,
                    headBranch: pr.headBranch, baseBranch: pr.baseBranch,
                    htmlUrl: pr.htmlUrl, status: prStatus, conclusion: conclusion
                )
            }
            showNotification(title: titleText, body: body, actionURL: url)
        }
    }

    private func handlePRMerged(_ data: [String: Any]) {
        guard let pr = makePR(from: data) else { return }
        Task { @MainActor in
            activePRs.removeAll { $0.prNumber == pr.prNumber && $0.repo == pr.repo }
            showNotification(
                title: "PR Merged 🎉",
                body: "\(pr.title) — \(pr.repo)#\(pr.prNumber)",
                actionURL: pr.prUrl
            )
        }
    }

    private func handlePRClosed(_ data: [String: Any]) {
        guard let pr = makePR(from: data) else { return }
        Task { @MainActor in
            activePRs.removeAll { $0.prNumber == pr.prNumber && $0.repo == pr.repo }
            showNotification(
                title: "PR Closed Without Merge",
                body: "\(pr.title) — \(pr.repo)#\(pr.prNumber)",
                actionURL: pr.prUrl
            )
        }
    }

    private func handlePRReviewRequested(_ data: [String: Any]) {
        let prNumber = data["prNumber"] as? Int64 ?? 0
        let title = data["title"] as? String ?? ""
        let repo = data["repo"] as? String ?? "unknown"
        let reviewer = data["reviewer"] as? String ?? "someone"
        let htmlUrl = (data["htmlUrl"] as? String).flatMap { URL(string: $0) }

        Task { @MainActor in
            showNotification(
                title: "Changes Requested",
                body: "\(reviewer) requested changes on \"\(title)\"",
                subtitle: "\(repo)#\(prNumber)",
                actionURL: htmlUrl
            )
        }
    }

    private func handlePRComment(_ data: [String: Any]) {
        let prNumber = data["prNumber"] as? Int64 ?? 0
        let repo = data["repo"] as? String ?? "unknown"
        let commenter = data["commenter"] as? String ?? "someone"
        let body = data["commentBody"] as? String ?? ""
        let prUrl = (data["prUrl"] as? String).flatMap { URL(string: $0) }

        let preview = body.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let truncated = preview.count > 80 ? String(preview.prefix(80)) + "…" : preview

        Task { @MainActor in
            showNotification(
                title: "New Comment on PR #\(prNumber)",
                body: "\(commenter): \(truncated)",
                subtitle: repo,
                actionURL: prUrl
            )
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
