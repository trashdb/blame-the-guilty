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

// MARK: - PR detail DTOs

struct ApiPRDetails: Decodable {
    let mergeableState: String?
    let behindBy: Int?
    let aheadBy: Int?
    let draft: Bool?
}

struct ApiMergeResponse: Decodable {
    let merged: Bool
    let sha: String?
    let message: String?
    let error: String?
}

struct ApiCommitInfo: Decodable, Identifiable {
    var id: String { sha ?? UUID().uuidString }
    let sha: String?
    let message: String?
    let authorName: String?
    let authorLogin: String?
    let date: String?
    let url: String?
}

struct ApiFileInfo: Decodable, Identifiable {
    var id: String { filename ?? UUID().uuidString }
    let filename: String?
    let status: String?
    let additions: Int?
    let deletions: Int?
}

struct ApiCheckInfo: Decodable, Identifiable {
    var id: String { name ?? UUID().uuidString }
    let name: String?
    let status: String?
    let conclusion: String?
    let startedAt: String?
    let completedAt: String?
    let url: String?
}

struct ApiSubscriberInfo: Identifiable, Decodable {
    var id: Int64 { gitHubId }
    let gitHubId: Int64
    let gitHubUsername: String
    let avatarUrl: String
}

struct ApiPRPreview: Decodable {
    let summary: String
    let suggestedBody: String
    let summaryError: String?
}

struct ApiBranch {
    let name: String
}
nonisolated extension ApiBranch: Decodable {}

struct ApiCreatePRResult: Decodable {
    let prNumber: Int64
    let url: String
    let existing: Bool?
}

struct ApiAvailableUser: Identifiable {
    var id: Int64 { gitHubId }
    let gitHubId: Int64
    let login: String
    let avatarUrl: String?
}
nonisolated extension ApiAvailableUser: Decodable {}

struct ApiError: Decodable {
    let error: String?
}

enum ApiFetch<T> {
    case success(T)
    case failure(String)

    func get() throws -> T {
        switch self {
        case .success(let value): return value
        case .failure(let message): throw NSError(domain: "ApiFetch", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}

enum ApiUpdateBranchResult {
    case updated(String)
    case sent
    case failed(String)
}

// MARK: - Protocol

protocol ApiClientProtocol: AnyObject {
    var baseUrl: String { get }

    /// Session JWT used as `Authorization: Bearer` on every request.
    var authToken: String? { get set }

    /// Fired (at most once per token) when the backend rejects the JWT with 401.
    /// The owner reacts by forcing a fresh login.
    var onUnauthorized: (() -> Void)? { get set }

    func fetchMe() async -> ApiMe?
    func fetchWorkflowRuns(limit: Int) async -> [ApiWorkflowRun]?
    func fetchActivePRs() async -> [ApiPullRequest]?
    func syncPRsFromGitHub() async -> Int
    func syncActiveWorkflows() async -> Int
    func subscribeToPR(prNumber: Int64, repo: String) async -> Bool
    func unsubscribeFromPR(prNumber: Int64, repo: String) async -> Bool

    func fetchPRDetails(prNumber: Int64, repo: String) async -> ApiFetch<ApiPRDetails>
    func mergePR(prNumber: Int64, repo: String, method: String) async -> ApiMergeResponse?
    func setDraft(prNumber: Int64, repo: String, draft: Bool) async -> String?
    func updateBranch(prNumber: Int64, repo: String) async -> ApiUpdateBranchResult
    func fetchCommits(prNumber: Int64, repo: String) async -> ApiFetch<[ApiCommitInfo]>
    func fetchFiles(prNumber: Int64, repo: String) async -> ApiFetch<[ApiFileInfo]>
    func fetchChecks(prNumber: Int64, repo: String) async -> ApiFetch<[ApiCheckInfo]>
    func fetchSubscribers(prNumber: Int64, repo: String) async -> ApiFetch<[ApiSubscriberInfo]>
    func fetchAvailableUsers() async -> ApiFetch<[ApiAvailableUser]>
    func addSubscriber(prNumber: Int64, repo: String, subscriberId: Int64) async -> String?
    func removeSubscriber(prNumber: Int64, repo: String, subscriberId: Int64) async -> String?

    func rerunWorkflow(runId: Int64) async -> String?
    func setTargetGitHubIds(dbId: Int, targetIds: [Int64]) async -> Bool
    func fetchWebhookLogs(limit: Int) async -> [WebhookLogEntry]?
    func savePAT(patToken: String, to backendUrl: String?) async -> Bool
    func fetchPRPreview(repo: String, head: String, baseBranch: String, title: String, useAI: Bool) async -> ApiFetch<ApiPRPreview>

    func fetchMyBranches(repo: String) async -> ApiFetch<[ApiBranch]>
    func createPR(repo: String, head: String, baseBranch: String, title: String, body: String?, subscribers: String?) async -> ApiFetch<ApiCreatePRResult>
    func fetchPAT() async -> String?
}

// MARK: - Live Implementation

final class LiveApiClient: ApiClientProtocol {
    let baseUrl: String
    var onUnauthorized: (() -> Void)?
    var authToken: String? {
        didSet { didFireUnauthorized = false }
    }
    private let session: URLSession
    private var didFireUnauthorized = false

    init(baseUrl: String, session: URLSession = .shared) {
        self.baseUrl = baseUrl
        self.session = session
    }

    /// Creates a client authenticated with the stored Keychain session for hosts
    /// that run outside the SwiftUI hierarchy (App Intents, Widgets).
    static func fromCurrentSession() -> LiveApiClient {
        let client = LiveApiClient(baseUrl: backendUrl)
        client.authToken = KeychainService.load()?.token
        return client
    }

    private func makeRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Runs a request, detecting JWT rejection so the owner can force a re-login.
    /// The callback fires only once per token to avoid a storm of logouts.
    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let urlSession = session
        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401, !didFireUnauthorized {
            didFireUnauthorized = true
            onUnauthorized?()
        }
        return (data, response)
    }

    func fetchMe() async -> ApiMe? {
        guard let url = URL(string: "\(baseUrl)/api/auth/me") else { return nil }
        guard let (data, _) = try? await perform(makeRequest(url)) else { return nil }
        return try? JSONDecoder().decode(ApiMe.self, from: data)
    }

    func fetchWorkflowRuns(limit: Int) async -> [ApiWorkflowRun]? {
        guard let url = URL(string: "\(baseUrl)/api/workflows/runs?limit=\(limit)") else { return nil }
        guard let (data, _) = try? await perform(makeRequest(url)) else { return nil }
        return try? ApiJSON.decoder.decode([ApiWorkflowRun].self, from: data)
    }

    func fetchActivePRs() async -> [ApiPullRequest]? {
        guard let url = URL(string: "\(baseUrl)/api/pullrequests/active") else { return nil }
        guard let (data, _) = try? await perform(makeRequest(url)) else { return nil }
        return try? JSONDecoder().decode([ApiPullRequest].self, from: data)
    }

    func syncPRsFromGitHub() async -> Int {
        guard let url = URL(string: "\(baseUrl)/api/pullrequests/sync") else { return 0 }
        var request = makeRequest(url)
        request.httpMethod = "POST"
        do {
            let (data, _) = try await perform(request)
            struct SyncResult: Decodable { let synced: Int }
            if let result = try? JSONDecoder().decode(SyncResult.self, from: data) {
                return result.synced
            }
        } catch {}
        return 0
    }

    func syncActiveWorkflows() async -> Int {
        guard let url = URL(string: "\(baseUrl)/api/workflows/sync-active") else { return 0 }
        var request = makeRequest(url)
        request.httpMethod = "POST"
        do {
            let (data, _) = try await perform(request)
            struct SyncResult: Decodable { let synced: Int }
            if let result = try? JSONDecoder().decode(SyncResult.self, from: data) {
                return result.synced
            }
        } catch {}
        return 0
    }

    func subscribeToPR(prNumber: Int64, repo: String) async -> Bool {
        let repoEncoded = repo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? repo
        guard let url = URL(string: "\(baseUrl)/api/pullrequests/\(prNumber)/subscribe?repo=\(repoEncoded)") else { return false }
        var req = makeRequest(url)
        req.httpMethod = "POST"
        guard let (_, resp) = try? await perform(req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return false }
        return true
    }

    func unsubscribeFromPR(prNumber: Int64, repo: String) async -> Bool {
        let repoEncoded = repo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? repo
        guard let url = URL(string: "\(baseUrl)/api/pullrequests/\(prNumber)/unsubscribe?repo=\(repoEncoded)") else { return false }
        var req = makeRequest(url)
        req.httpMethod = "POST"
        guard let (_, resp) = try? await perform(req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return false }
        return true
    }

    // MARK: - PR detail actions

    private func url(_ path: String, query: [String: String] = [:]) -> URL? {
        var components = URLComponents(string: "\(baseUrl)\(path)")
        components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components?.url
    }

    func fetchPRDetails(prNumber: Int64, repo: String) async -> ApiFetch<ApiPRDetails> {
        guard let url = url("/api/pullrequests/\(prNumber)/detail", query: ["repo": repo]) else {
            return .failure("Invalid URL")
        }
        var req = makeRequest(url)
        req.timeoutInterval = 15
        do {
            let (data, _) = try await perform(req)
            guard let decoded = try? JSONDecoder().decode(ApiPRDetails.self, from: data) else {
                let raw = String(data: data, encoding: .utf8) ?? "non-utf8"
                return .failure("Parse error: \(raw.prefix(200))")
            }
            return .success(decoded)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func mergePR(prNumber: Int64, repo: String, method: String) async -> ApiMergeResponse? {
        guard let url = url("/api/pullrequests/\(prNumber)/merge", query: ["repo": repo, "method": method]) else { return nil }
        var request = makeRequest(url)
        request.httpMethod = "POST"
        guard let (data, _) = try? await perform(request) else { return nil }
        return try? JSONDecoder().decode(ApiMergeResponse.self, from: data)
    }

    func setDraft(prNumber: Int64, repo: String, draft: Bool) async -> String? {
        guard let url = url("/api/pullrequests/\(prNumber)/draft", query: ["repo": repo, "draft": draft ? "true" : "false"]) else {
            return "Invalid URL"
        }
        var request = makeRequest(url)
        request.httpMethod = "POST"
        do {
            let (_, resp) = try await perform(request)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return status >= 400 ? "HTTP \(status)" : nil
        } catch {
            return error.localizedDescription
        }
    }

    func updateBranch(prNumber: Int64, repo: String) async -> ApiUpdateBranchResult {
        guard let url = url("/api/pullrequests/\(prNumber)/update-branch", query: ["repo": repo]) else {
            return .failed("Invalid URL")
        }
        var request = makeRequest(url)
        request.httpMethod = "POST"
        do {
            let (data, resp) = try await perform(request)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            struct MessageResponse: Decodable { let message: String? }
            if let decoded = try? JSONDecoder().decode(MessageResponse.self, from: data), let message = decoded.message {
                return .updated(message)
            }
            if let decoded = try? JSONDecoder().decode(ApiError.self, from: data), let message = decoded.error, status >= 400 {
                return .failed(message)
            }
            if status >= 200 && status < 300 {
                return .sent
            }
            let raw = String(data: data, encoding: .utf8) ?? "non-utf8"
            return .failed("\(raw.prefix(200))")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func fetchCommits(prNumber: Int64, repo: String) async -> ApiFetch<[ApiCommitInfo]> {
        await fetchList("/api/pullrequests/\(prNumber)/commits", prNumber: prNumber, repo: repo)
    }

    func fetchFiles(prNumber: Int64, repo: String) async -> ApiFetch<[ApiFileInfo]> {
        await fetchList("/api/pullrequests/\(prNumber)/files", prNumber: prNumber, repo: repo)
    }

    func fetchChecks(prNumber: Int64, repo: String) async -> ApiFetch<[ApiCheckInfo]> {
        await fetchList("/api/pullrequests/\(prNumber)/checks", prNumber: prNumber, repo: repo)
    }

    private func fetchList<T: Decodable>(_ path: String, prNumber: Int64, repo: String) async -> ApiFetch<[T]> {
        guard let url = url(path, query: ["repo": repo]) else {
            return .failure("Invalid URL")
        }
        var req = makeRequest(url)
        req.timeoutInterval = 15
        do {
            let (data, _) = try await perform(req)
            guard let decoded = try? JSONDecoder().decode([T].self, from: data) else {
                return .failure("Parse error: \(errorLocalized(from: data))")
            }
            return .success(decoded)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func errorLocalized(from data: Data) -> String {
        (try? JSONDecoder().decode(ApiError.self, from: data))?.error
            ?? String(data: data, encoding: .utf8).map { "\($0.prefix(200))" }
            ?? "non-utf8"
    }

    func fetchSubscribers(prNumber: Int64, repo: String) async -> ApiFetch<[ApiSubscriberInfo]> {
        guard let url = url("/api/pullrequests/\(prNumber)/subscribers", query: ["repo": repo]) else {
            return .failure("Invalid URL")
        }
        do {
            let (data, _) = try await perform(makeRequest(url))
            struct Wrapper: Decodable { let subscribers: [ApiSubscriberInfo] }
            guard let decoded = try? JSONDecoder().decode(Wrapper.self, from: data) else {
                return .failure("Parse error: \(errorLocalized(from: data))")
            }
            return .success(decoded.subscribers)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func fetchAvailableUsers() async -> ApiFetch<[ApiAvailableUser]> {
        guard let url = url("/api/users") else { return .failure("Invalid URL") }
        do {
            let (data, _) = try await perform(makeRequest(url))
            guard let decoded = try? JSONDecoder().decode([ApiAvailableUser].self, from: data) else {
                return .failure("Parse error: \(errorLocalized(from: data))")
            }
            return .success(decoded)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func addSubscriber(prNumber: Int64, repo: String, subscriberId: Int64) async -> String? {
        await mutateSubscriber("/api/pullrequests/\(prNumber)/add-subscriber", prNumber: prNumber, repo: repo, subscriberId: subscriberId)
    }

    func removeSubscriber(prNumber: Int64, repo: String, subscriberId: Int64) async -> String? {
        await mutateSubscriber("/api/pullrequests/\(prNumber)/remove-subscriber", prNumber: prNumber, repo: repo, subscriberId: subscriberId)
    }

    private func mutateSubscriber(_ path: String, prNumber: Int64, repo: String, subscriberId: Int64) async -> String? {
        guard let url = url(path, query: ["repo": repo, "subscriberId": "\(subscriberId)"]) else {
            return "Invalid URL"
        }
        var req = makeRequest(url)
        req.httpMethod = "POST"
        do {
            let (data, resp) = try await perform(req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                if let err = try? JSONDecoder().decode(ApiError.self, from: data), let msg = err.error {
                    return msg
                }
                return "HTTP \(http.statusCode)"
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Workflow run management

    func rerunWorkflow(runId: Int64) async -> String? {
        guard let url = URL(string: "\(baseUrl)/api/workflows/runs/\(runId)/rerun") else { return "Invalid URL" }
        var request = makeRequest(url)
        request.httpMethod = "POST"
        do {
            let (data, response) = try await perform(request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                return "HTTP \(status): \(body)"
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func setTargetGitHubIds(dbId: Int, targetIds: [Int64]) async -> Bool {
        guard let url = URL(string: "\(baseUrl)/api/workflows/runs/\(dbId)/target") else { return false }
        var request = makeRequest(url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["targetGitHubIds": targetIds])
        guard let (_, response) = try? await perform(request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    // MARK: - Webhook logs

    func fetchWebhookLogs(limit: Int) async -> [WebhookLogEntry]? {
        guard let url = URL(string: "\(baseUrl)/api/webhook/logs?limit=\(limit)") else { return nil }
        guard let (data, _) = try? await perform(makeRequest(url)) else { return nil }
        return try? ApiJSON.decoder.decode([WebhookLogEntry].self, from: data)
    }

    // MARK: - Auth helpers

    func savePAT(patToken: String, to backendUrl: String?) async -> Bool {
        let target = backendUrl ?? baseUrl
        guard let url = URL(string: "\(target)/api/auth/pat") else { return false }
        var request = makeRequest(url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["patToken": patToken])
        guard let (_, response) = try? await perform(request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    // MARK: - PR preview

    func fetchPRPreview(repo: String, head: String, baseBranch: String, title: String, useAI: Bool) async -> ApiFetch<ApiPRPreview> {
        let repoEncoded = repo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? repo
        let headEncoded = head.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? head
        let baseEncoded = baseBranch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? baseBranch
        let titleEncoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        guard let url = URL(string: "\(baseUrl)/api/github/pr-preview?repo=\(repoEncoded)&head=\(headEncoded)&baseBranch=\(baseEncoded)&title=\(titleEncoded)&useAI=\(useAI)") else {
            return .failure("Invalid URL")
        }
        var request = makeRequest(url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        do {
            let (data, response) = try await perform(request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failure(errorLocalized(from: data))
            }
            guard let decoded = try? JSONDecoder().decode(ApiPRPreview.self, from: data) else {
                return .failure("Parse error: \(errorLocalized(from: data))")
            }
            return .success(decoded)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - GitHub REST via backend

    func fetchMyBranches(repo: String) async -> ApiFetch<[ApiBranch]> {
        guard let url = url("/api/github/my-branches", query: ["repo": repo]) else {
            return .failure("Invalid URL")
        }
        do {
            let (data, _) = try await perform(makeRequest(url))
            guard let decoded = try? JSONDecoder().decode([ApiBranch].self, from: data) else {
                return .failure("Parse error: \(errorLocalized(from: data))")
            }
            return .success(decoded)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func createPR(repo: String, head: String, baseBranch: String, title: String, body: String?, subscribers: String?) async -> ApiFetch<ApiCreatePRResult> {
        var query: [String: String] = [
            "repo": repo,
            "head": head,
            "baseBranch": baseBranch,
            "title": title
        ]
        if let body, !body.isEmpty { query["body"] = body }
        if let subscribers, !subscribers.isEmpty { query["subscribers"] = subscribers }
        guard let url = url("/api/github/create-pr", query: query) else {
            return .failure("Invalid URL")
        }
        var request = makeRequest(url)
        request.httpMethod = "POST"
        do {
            let (data, response) = try await perform(request)
            guard let http = response as? HTTPURLResponse else {
                return .failure("No response from server")
            }
            if let decoded = try? JSONDecoder().decode(ApiCreatePRResult.self, from: data) {
                return .success(decoded)
            }
            return .failure("HTTP \(http.statusCode): \(errorLocalized(from: data))")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func fetchPAT() async -> String? {
        guard let url = URL(string: "\(baseUrl)/api/auth/token") else { return nil }
        guard let (data, _) = try? await perform(makeRequest(url)) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let token = json["token"], !token.isEmpty else { return nil }
        return token
    }
}

// MARK: - Shared JSON decoding

enum ApiJSON {
    private static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = .withInternetDateTime
        return formatter
    }()

    /// Decoder that tolerates the backend's ISO-8601 date formats:
    /// fractional seconds, plain "T" separators, and missing timezone (assumed UTC).
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            let str = try container.decode(String.self)
            guard let date = parseISO8601(str) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(str)")
            }
            return date
        }
        return decoder
    }()

    /// Parses the backend's ISO-8601 date strings: fractional seconds or plain
    /// internet date-time, " " separators, and missing timezone assumed UTC.
    static func parseISO8601(_ raw: String) -> Date? {
        var str = raw.replacingOccurrences(of: " ", with: "T")
        if !str.contains("Z") && !str.contains("+") {
            str += "Z"
        }
        return withFractional.date(from: str) ?? plain.date(from: str)
    }
}
