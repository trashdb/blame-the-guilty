import Foundation
import SwiftUI

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
    let targetGitHubId: Int64?

    var isRunning: Bool { status == "in_progress" }
}

struct GitHubUserInfo: Decodable, Identifiable {
    let gitHubId: Int64
    let login: String
    var id: Int64 { gitHubId }
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

    var isInProgress: Bool { status == "in_progress" }
    var isReadyToMerge: Bool { status == "open" && conclusion == "success" }
    var isFailed: Bool { conclusion == "failure" }
    var isMerged: Bool { status == "merged" }
}

enum NotificationType {
    case success, info, error

    var color: Color {
        switch self {
        case .success: return .green
        case .info:    return .white
        case .error:   return .red
        }
    }

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info:    return "info.circle.fill"
        case .error:   return "flame.fill"
        }
    }
}
