import Foundation

// MARK: - Punishment event model

struct PunishmentEvent {
    let culprit: String
    let repo: String
    let runId: Int64
    let workflowURL: URL?
    let date: Date
}

class SignalRService: ObservableObject {
    @Published var isConnected = false
    @Published var lastEvent: PunishmentEvent?   // shown in menu bar popup

    private let baseUrl: String
    private var task: Task<Void, Never>?

    init(baseUrl: String) {
        self.baseUrl = baseUrl
    }

    func connect(gitHubId: Int64) {
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
              target == "TriggerPunishment",
              let args = json["arguments"] as? [[String: Any]],
              let data = args.first else { return }

        let culprit = data["culprit"] as? String ?? "unknown"
        let repo    = data["repo"]    as? String
        let runId   = data["runId"]   as? Int64 ?? 0

        let workflowURL: URL? = repo.flatMap { r in
            URL(string: "https://github.com/\(r)/actions/runs/\(runId)")
        }

        let event = PunishmentEvent(
            culprit: culprit,
            repo: repo ?? "unknown",
            runId: runId,
            workflowURL: workflowURL,
            date: Date()
        )

        Task { @MainActor in
            self.lastEvent = event
            showNotification(
                title: "⚠️ Blame the Guilty",
                body: "\(culprit) merged a failing workflow in \(repo ?? "unknown")",
                subtitle: "Run #\(runId)",
                actionURL: workflowURL
            )
        }
    }

    func disconnect() {
        task?.cancel()
        task = nil
        Task { @MainActor in isConnected = false }
    }

    enum SignalRError: Error {
        case handshakeFailed
    }
}
