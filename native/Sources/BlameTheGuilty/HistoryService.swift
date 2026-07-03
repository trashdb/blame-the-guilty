import Foundation

struct HistoryEvent: Decodable, Identifiable {
    var id: Int64 { runId }
    let runId: Int64
    let culpritLogin: String
    let repoFullName: String
    let workflowName: String?
    let workflowUrl: String?
    let occurredAt: Date
    let wasNotified: Bool
}

class HistoryService {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = formatter.date(from: str) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(str)")
        }
        return d
    }()

    func fetchRecent(days: Int = 7, limit: Int = 20, baseUrl: String) async throws -> [HistoryEvent] {
        let url = URL(string: "\(baseUrl)/api/punishments?days=\(days)&limit=\(limit)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decoder.decode([HistoryEvent].self, from: data)
    }
}
