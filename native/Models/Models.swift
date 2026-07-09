import Foundation

let backendUrl = "https://moonlike-silenced-sprung.ngrok-free.dev"

func shortRepo(_ full: String) -> String {
    if let slash = full.firstIndex(of: "/") {
        return String(full[full.index(after: slash)...])
    }
    return full
}

struct PunishmentEvent {
    let culprit: String
    let repo: String
    let runId: Int64
    let workflowName: String?
    let workflowURL: URL?
    let date: Date
}

struct WorkflowRun: Identifiable, Codable {
    let id: UUID
    let dbId: Int?
    let runId: Int64
    let workflowName: String
    let repo: String
    let actor: String
    let headBranch: String?
    let trigger: String?
    let prNumber: Int?
    let prTitle: String?
    let status: String
    let htmlUrl: String
    let startedAt: Date
    let completedAt: Date?
    let targetGitHubIds: [Int64]

    var isRunning: Bool { status == "in_progress" }

    var duration: TimeInterval? {
        guard let completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }
}

struct PullRequest: Identifiable {
    let id = UUID()
    let prNumber: Int64
    let title: String
    let repo: String
    let headBranch: String
    let baseBranch: String
    let htmlUrl: URL?
    let status: String
    let conclusion: String?
    let draft: Bool
    let mergeableState: String?
    let ciStatus: String

    var prUrl: URL { htmlUrl ?? URL(string: "https://github.com/\(repo)/pull/\(prNumber)")! }

    var isMerged: Bool { status == "merged" }
}

struct WebhookLogEntry: Decodable, Identifiable {
    let id = UUID()
    let eventType: String
    let action: String?
    let repo: String?
    let workflowName: String?
    let outcome: String
    let message: String?
    let occurredAt: Date

    enum CodingKeys: String, CodingKey {
        case eventType, action, repo, workflowName, outcome, message, occurredAt
    }
}

struct GitHubUserInfo: Decodable, Identifiable {
    let gitHubId: Int64
    let login: String
    var id: Int64 { gitHubId }
}
