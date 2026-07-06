import Foundation

let backendUrl = "https://moonlike-silenced-sprung.ngrok-free.dev"

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
    let runId: Int64
    let workflowName: String
    let repo: String
    let actor: String
    let status: String
    let htmlUrl: String
    let startedAt: Date
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

    var prUrl: URL { htmlUrl ?? URL(string: "https://github.com/\(repo)/pull/\(prNumber)")! }

    var isReadyToMerge: Bool {
        status == "open" && conclusion == "success"
    }

    var isFailed: Bool {
        conclusion == "failure"
    }

    var isMerged: Bool {
        status == "merged"
    }
}
