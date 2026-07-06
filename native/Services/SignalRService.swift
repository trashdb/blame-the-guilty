import Combine
import Foundation

enum RunStatus: Equatable {
    case idle, running, success, failure
}

class SignalRService: ObservableObject {
    @Published var isConnected = false
    @Published var runStatus: RunStatus = .idle
    @Published var lastEvent: PunishmentEvent?
    @Published var runningWorkflows: [WorkflowRun] = []
    @Published var recentWorkflows: [WorkflowRun] = []

    private let baseUrl: String
    private var task: Task<Void, Never>?
    private var gitHubId: Int64 = 0

    init(baseUrl: String) {
        self.baseUrl = baseUrl
    }

    func connect(gitHubId: Int64) {
        self.gitHubId = gitHubId
        loadPersistedHistory()
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await connectAndListen(gitHubId: gitHubId)
                } catch {
                    await MainActor.run { self.isConnected = false }
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
    }

    private func loadPersistedHistory() {
        let saved = PersistenceService.load()
        if !saved.isEmpty {
            recentWorkflows = saved
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

    private func connectAndListen(gitHubId: Int64) async throws {
        let url = hubWebSocketUrl
        let ws = URLSession.shared.webSocketTask(with: url)
        ws.resume()
        defer { ws.cancel(with: .normalClosure, reason: nil) }

        try await ws.send(.string("{\"protocol\":\"json\",\"version\":1}\u{1e}"))
        guard case .string = try await ws.receive() else { throw SignalRError.handshakeFailed }

        let register = "{\"type\":1,\"target\":\"RegisterConnection\",\"arguments\":[\(gitHubId)],\"invocationId\":\"1\"}\u{1e}"
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
        case "WorkflowRunStarted":   handleWorkflowStarted(data)
        case "WorkflowRunCompleted": handleWorkflowCompleted(data)
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
                id: runId, workflowName: name, repo: repo,
                actor: actor, status: "in_progress",
                htmlUrl: htmlUrl, startedAt: startedAt
            )
            runningWorkflows.insert(run, at: 0)
            recentWorkflows.insert(run, at: 0)
            if recentWorkflows.count > 10 { recentWorkflows = Array(recentWorkflows.prefix(10)) }
            persistHistory()
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

            runningWorkflows.removeAll { $0.id == runId }

            let completedRun = WorkflowRun(
                id: runId,
                workflowName: name ?? "Workflow",
                repo: repo,
                actor: actor,
                status: succeeded ? "success" : "failure",
                htmlUrl: htmlUrl ?? "https://github.com/\(repo)/actions/runs/\(runId)",
                startedAt: Date()
            )

            if let idx = recentWorkflows.firstIndex(where: { $0.id == runId }) {
                recentWorkflows[idx] = completedRun
            } else {
                recentWorkflows.insert(completedRun, at: 0)
                if recentWorkflows.count > 10 { recentWorkflows = Array(recentWorkflows.prefix(10)) }
            }
            persistHistory()

            let wfName = name ?? "Workflow"
            if !succeeded {
                lastEvent = PunishmentEvent(
                    culprit: actor, repo: repo, runId: runId,
                    workflowName: wfName,
                    workflowURL: workflowURL, date: Date()
                )
                showNotification(
                    title: "❌ Workflow Failed",
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

    func disconnect() {
        task?.cancel()
        task = nil
        Task { @MainActor in
            isConnected = false
            runStatus = .idle
            lastEvent = nil
            runningWorkflows = []
        }
    }

    enum SignalRError: Error {
        case handshakeFailed
    }
}
