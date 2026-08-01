import Foundation

// MARK: - Hub events

/// Typed events delivered by the SignalR client. Payloads are decoded into
/// concrete types so consumers never touch raw JSON dicts.
enum HubEvent {
    case workflowStarted(WorkflowStartedEvent)
    case workflowCompleted(WorkflowCompletedEvent)
    case pullRequestsUpdated
    case prApproved(PrEvent)
    case prCommented(PrCommentedEvent)
    case mainBranchUpdated(MainBranchUpdatedEvent)
    case connectionClosed
}

struct WorkflowStartedEvent: Decodable {
    let id: Int?
    let runId: Int64
    let workflowName: String?
    let repo: String
    let actor: String?
    let htmlUrl: String?
    let startedAt: String?
    let branch: String?
    let trigger: String?
}

struct WorkflowCompletedEvent: Decodable {
    let runId: Int64
    let succeeded: Bool?
    let conclusion: String?
    let workflowName: String?
    let repo: String
    let actor: String?
    let htmlUrl: String?
    let trigger: String?
}

struct PrEvent: Decodable {
    let prNumber: Int?
    let repo: String?
    let reviewerLogin: String?
    let title: String?
}

struct PrCommentedEvent: Decodable {
    let prNumber: Int?
    let repo: String?
    let commenterLogin: String?
    let title: String?
    let commentBody: String?
    let commentUrl: String?
}

struct MainBranchUpdatedEvent: Decodable {
    let repo: String?
    let prNumber: Int?
    let mergedBy: String?
    let headSha: String?
}

// MARK: - Protocol

protocol SignalRClientProtocol: AnyObject {
    func connectAndListen(gitHubId: Int64, username: String, onEvent: @escaping (HubEvent) -> Void) async throws
}

// MARK: - Live Implementation

/// Raw SignalR-over-websocket transport. Handles handshake, ping frames and
/// frame-splitting; parses invocations into `HubEvent` values and forwards them
/// via the `onEvent` callback.
final class LiveSignalRClient: SignalRClientProtocol {
    private let baseUrl: String

    init(baseUrl: String) {
        self.baseUrl = baseUrl
    }

    private var hubWebSocketUrl: URL {
        let wsUrl = baseUrl
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        return URL(string: "\(wsUrl)/hub/punishment")!
    }

    func connectAndListen(gitHubId: Int64, username: String, onEvent: @escaping (HubEvent) -> Void) async throws {
        let ws = URLSession.shared.webSocketTask(with: hubWebSocketUrl)
        ws.resume()
        defer { ws.cancel(with: .normalClosure, reason: nil) }

        try await ws.send(.string("{\"protocol\":\"json\",\"version\":1}\u{1e}"))
        guard case .string = try await ws.receive() else { throw SignalRClientError.handshakeFailed }

        let register = "{\"type\":1,\"target\":\"RegisterConnection\",\"arguments\":[\(gitHubId),\"\(username)\"],\"invocationId\":\"1\"}\u{1e}"
        try await ws.send(.string(register))

        while !Task.isCancelled {
            let message = try await ws.receive()
            if case .string(let text) = message {
                handleText(text, ws: ws, onEvent: onEvent)
            }
        }
    }

    private func handleText(_ text: String, ws: URLSessionWebSocketTask, onEvent: (HubEvent) -> Void) {
        for part in text.components(separatedBy: "\u{1e}").filter({ !$0.isEmpty }) {
            guard let data = part.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? Int else { continue }

            switch type {
            case 1:
                if let event = parseInvocation(json) {
                    onEvent(event)
                }
            case 6:
                Task { try? await ws.send(.string("{\"type\":6}\u{1e}")) }
            case 7:
                onEvent(.connectionClosed)
            default:
                break
            }
        }
    }

    private func parseInvocation(_ json: [String: Any]) -> HubEvent? {
        guard let target = json["target"] as? String,
              let args = json["arguments"] as? [[String: Any]],
              let data = args.first else { return nil }

        let decoder = JSONDecoder()
        func decode<T: Decodable>(_ type: T.Type) -> T? {
            guard let d = try? JSONSerialization.data(withJSONObject: data) else { return nil }
            return try? decoder.decode(T.self, from: d)
        }

        switch target {
        case "WorkflowRunStarted":
            return decode(WorkflowStartedEvent.self).map { .workflowStarted($0) }
        case "WorkflowRunCompleted":
            return decode(WorkflowCompletedEvent.self).map { .workflowCompleted($0) }
        case "PullRequestsUpdated":
            return .pullRequestsUpdated
        case "PrApproved":
            return decode(PrEvent.self).map { .prApproved($0) }
        case "PrCommented":
            return decode(PrCommentedEvent.self).map { .prCommented($0) }
        case "MainBranchUpdated":
            return decode(MainBranchUpdatedEvent.self).map { .mainBranchUpdated($0) }
        default:
            return nil
        }
    }

    enum SignalRClientError: Error {
        case handshakeFailed
    }
}
