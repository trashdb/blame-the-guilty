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
    let id: Int64
    let workflowName: String
    let repo: String
    let actor: String
    let status: String
    let htmlUrl: String
    let startedAt: Date
}
