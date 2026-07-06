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
    let targetGitHubId: Int64?

    var isRunning: Bool { status == "in_progress" }
}

struct GitHubUserInfo: Decodable, Identifiable {
    let gitHubId: Int64
    let login: String
    var id: Int64 { gitHubId }
}
