import AppIntents
import AppKit
import Foundation

// MARK: - Open PR Intent

struct OpenPRIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Pull Request"
    static var description = IntentDescription("Opens a pull request in your browser")
    static var parameterSummary: ParameterSummary { Summary("Open PR \(\.$prNumber) in \(\.$repository)") }

    @Parameter(title: "PR Number")
    var prNumber: Int

    @Parameter(title: "Repository (owner/repo)")
    var repository: String

    func perform() async throws -> some IntentResult {
        let url = URL(string: "https://github.com/\(repository)/pull/\(prNumber)")!
        await MainActor.run { NSWorkspace.shared.open(url) }
        return .result()
    }
}

// MARK: - Copy PR Link Intent

struct CopyPRLinkIntent: AppIntent {
    static var title: LocalizedStringResource = "Copy PR Link"
    static var description = IntentDescription("Copies the pull request URL to clipboard")
    static var parameterSummary: ParameterSummary { Summary("Copy link for PR \(\.$prNumber) in \(\.$repository)") }

    @Parameter(title: "PR Number")
    var prNumber: Int

    @Parameter(title: "Repository (owner/repo)")
    var repository: String

    func perform() async throws -> some IntentResult {
        let url = "https://github.com/\(repository)/pull/\(prNumber)"
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
        }
        return .result()
    }
}

// MARK: - Get PR Status Intent

struct GetPRStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get PR Status"
    static var description = IntentDescription("Returns the status of a pull request")
    static var parameterSummary: ParameterSummary { Summary("Get status of PR \(\.$prNumber) in \(\.$repository)") }

    @Parameter(title: "PR Number")
    var prNumber: Int

    @Parameter(title: "Repository (owner/repo)")
    var repository: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let urlString = await MainActor.run { "\(backendUrl)/api/pullrequests/\(prNumber)/detail?repo=\(repository)&gitHubId=0" }
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url) else {
            return .result(value: "Unknown")
        }
        struct DetailResponse: Decodable {
            let mergeableState: String?
            let draft: Bool?
        }
        if let decoded = try? JSONDecoder().decode(DetailResponse.self, from: data) {
            let status = decoded.draft == true ? "Draft" : (decoded.mergeableState ?? "Unknown")
            return .result(value: status)
        }
        return .result(value: "Unknown")
    }
}

// MARK: - List My PRs Intent

struct ListMyPRsIntent: AppIntent {
    static var title: LocalizedStringResource = "List My Pull Requests"
    static var description = IntentDescription("Shows your active pull requests")

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let urlString = await MainActor.run { "\(backendUrl)/api/pullrequests/active?gitHubId=0" }
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url) else {
            return .result(value: [])
        }
        struct PRResponse: Decodable {
            let prNumber: Int64
            let title: String
            let repo: String
        }
        if let prs = try? JSONDecoder().decode([PRResponse].self, from: data) {
            let summaries = prs.prefix(10).map { "PR #\($0.prNumber): \($0.title) (\($0.repo))" }
            return .result(value: Array(summaries))
        }
        return .result(value: [])
    }
}

// MARK: - App Shortcuts

struct BlameTheGuiltyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenPRIntent(),
            phrases: [
                "Open PR in \(.applicationName)",
                "Show PR in \(.applicationName)"
            ],
            shortTitle: "Open PR",
            systemImageName: "arrow.up.forward.app"
        )
        AppShortcut(
            intent: CopyPRLinkIntent(),
            phrases: [
                "Copy PR link in \(.applicationName)",
                "Copy PR link with \(.applicationName)"
            ],
            shortTitle: "Copy PR Link",
            systemImageName: "doc.on.doc"
        )
        AppShortcut(
            intent: GetPRStatusIntent(),
            phrases: [
                "Get PR status in \(.applicationName)",
                "Check PR status with \(.applicationName)"
            ],
            shortTitle: "PR Status",
            systemImageName: "questionmark.circle"
        )
        AppShortcut(
            intent: ListMyPRsIntent(),
            phrases: [
                "List my pull requests in \(.applicationName)",
                "Show my active PRs in \(.applicationName)"
            ],
            shortTitle: "My PRs",
            systemImageName: "list.bullet"
        )
    }
}
