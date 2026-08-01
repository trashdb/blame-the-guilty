import Foundation

// MARK: - Shared API DTOs

struct ApiWorkflowRun: Decodable {
    let id: Int
    let runId: Int64
    let workflowName: String?
    let repo: String
    let actor: String
    let headBranch: String?
    let trigger: String?
    let prNumber: Int?
    let prTitle: String?
    let status: String
    let htmlUrl: String?
    let startedAt: Date
    let targetGitHubIds: [Int64]?
}

struct ApiPullRequest: Decodable {
    let prNumber: Int64
    let title: String
    let repo: String
    let headBranch: String?
    let baseBranch: String?
    let htmlUrl: String?
    let status: String?
    let conclusion: String?
    let draft: Bool?
    let mergeableState: String?
    let ciStatus: String?
    let reviewApproved: Bool?
    let lastCommentBy: String?
    let lastCommentBody: String?
    let lastCommentAt: Date?
    let isSubscribed: Bool?
    let subscriberIds: [Int64]?
    let authorGitHubId: Int64?
}

struct ApiMe: Decodable {
    let id: Int64
    let username: String
    let avatarUrl: String?
}

// MARK: - Protocol

protocol ApiClientProtocol: AnyObject {
    var baseUrl: String { get }

    func fetchMe(gitHubId: Int64) async -> ApiMe?
    func fetchWorkflowRuns(gitHubId: Int64, limit: Int) async -> [ApiWorkflowRun]?
    func fetchActivePRs(gitHubId: Int64) async -> [ApiPullRequest]?
    func syncPRsFromGitHub(gitHubId: Int64) async -> Int
    func syncActiveWorkflows(gitHubId: Int64) async -> Int
    func subscribeToPR(prNumber: Int64, repo: String, gitHubId: Int64) async -> Bool
    func unsubscribeFromPR(prNumber: Int64, repo: String, gitHubId: Int64) async -> Bool
}

// MARK: - Live Implementation

final class LiveApiClient: ApiClientProtocol {
    let baseUrl: String

    init(baseUrl: String) {
        self.baseUrl = baseUrl
    }

    func fetchMe(gitHubId: Int64) async -> ApiMe? {
        guard let url = URL(string: "\(baseUrl)/api/auth/me?gitHubId=\(gitHubId)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return try? JSONDecoder().decode(ApiMe.self, from: data)
    }

    func fetchWorkflowRuns(gitHubId: Int64, limit: Int) async -> [ApiWorkflowRun]? {
        guard let url = URL(string: "\(baseUrl)/api/workflows/runs?gitHubId=\(gitHubId)&limit=\(limit)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return try? ApiJSON.decoder.decode([ApiWorkflowRun].self, from: data)
    }

    func fetchActivePRs(gitHubId: Int64) async -> [ApiPullRequest]? {
        guard let url = URL(string: "\(baseUrl)/api/pullrequests/active?gitHubId=\(gitHubId)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return try? JSONDecoder().decode([ApiPullRequest].self, from: data)
    }

    func syncPRsFromGitHub(gitHubId: Int64) async -> Int {
        guard let url = URL(string: "\(baseUrl)/api/pullrequests/sync?gitHubId=\(gitHubId)") else { return 0 }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            struct SyncResult: Decodable { let synced: Int }
            if let result = try? JSONDecoder().decode(SyncResult.self, from: data) {
                return result.synced
            }
        } catch {}
        return 0
    }

    func syncActiveWorkflows(gitHubId: Int64) async -> Int {
        guard let url = URL(string: "\(baseUrl)/api/workflows/sync-active?gitHubId=\(gitHubId)") else { return 0 }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            struct SyncResult: Decodable { let synced: Int }
            if let result = try? JSONDecoder().decode(SyncResult.self, from: data) {
                return result.synced
            }
        } catch {}
        return 0
    }

    func subscribeToPR(prNumber: Int64, repo: String, gitHubId: Int64) async -> Bool {
        let repoEncoded = repo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? repo
        guard let url = URL(string: "\(baseUrl)/api/pullrequests/\(prNumber)/subscribe?repo=\(repoEncoded)&gitHubId=\(gitHubId)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return false }
        return true
    }

    func unsubscribeFromPR(prNumber: Int64, repo: String, gitHubId: Int64) async -> Bool {
        let repoEncoded = repo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? repo
        guard let url = URL(string: "\(baseUrl)/api/pullrequests/\(prNumber)/unsubscribe?repo=\(repoEncoded)&gitHubId=\(gitHubId)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return false }
        return true
    }
}

// MARK: - Shared JSON decoding

enum ApiJSON {
    /// Decoder that tolerates the backend's ISO-8601 date formats:
    /// fractional seconds, plain "T" separators, and missing timezone (assumed UTC).
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let withoutFrac = ISO8601DateFormatter()
        withoutFrac.formatOptions = .withInternetDateTime
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            var str = try container.decode(String.self)
            str = str.replacingOccurrences(of: " ", with: "T")
            if !str.contains("Z") && !str.contains("+") {
                str += "Z"
            }
            guard let date = withFrac.date(from: str) ?? withoutFrac.date(from: str) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(str)")
            }
            return date
        }
        return decoder
    }()
}
