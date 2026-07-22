import Foundation

var backendUrl: String {
    UserDefaults.standard.string(forKey: "backendUrl") ?? TeamDefaults.backendUrl
}

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

struct PullRequest: Identifiable, Equatable, Codable {
    var id: String { "\(repo)#\(prNumber)" }
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
    let reviewApproved: Bool
    let lastCommentBy: String?
    let lastCommentBody: String?
    let lastCommentAt: Date?
    let lastCommentUrl: String?
    let lastReviewFilePath: String?
    let lastReviewLine: Int?

    var prUrl: URL { htmlUrl ?? URL(string: "https://github.com/\(repo)/pull/\(prNumber)")! }
    var isMerged: Bool { status == "merged" }

    static func == (lhs: PullRequest, rhs: PullRequest) -> Bool {
        lhs.prNumber == rhs.prNumber && lhs.repo == rhs.repo
    }
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

func extractTicketNumber(from branchName: String) -> String? {
    let pattern = try? NSRegularExpression(pattern: "[A-Z]+-\\d+")
    let range = NSRange(branchName.startIndex..., in: branchName)
    guard let match = pattern?.firstMatch(in: branchName, range: range) else { return nil }
    return String(branchName[Range(match.range, in: branchName)!])
}

struct BranchInfo: Identifiable {
    let id = UUID()
    let name: String
    let repoPath: String
    let repoName: String
    let isCurrent: Bool
    let isLocal: Bool
    let isMerged: Bool
    let isDefault: Bool

    var ticketNumber: String? { extractTicketNumber(from: name) }
    var jiraUrl: URL? {
        guard let ticket = ticketNumber else { return nil }
        let url = UserDefaults.standard.string(forKey: "jiraBoardUrl") ?? TeamDefaults.jiraBoardUrl
        return URL(string: "\(url)\(ticket)")
    }
}
