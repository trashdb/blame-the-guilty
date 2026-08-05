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
        let client = LiveApiClient.fromCurrentSession()
        let result = await client.fetchPRDetails(prNumber: Int64(prNumber), repo: repository)
        switch result {
        case .success(let details):
            let status = details.draft == true ? "Draft" : (details.mergeableState ?? "Unknown")
            return .result(value: status)
        case .failure:
            return .result(value: "Unknown")
        }
    }
}

// MARK: - List My PRs Intent

struct ListMyPRsIntent: AppIntent {
    static var title: LocalizedStringResource = "List My Pull Requests"
    static var description = IntentDescription("Shows your active pull requests")

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let client = LiveApiClient.fromCurrentSession()
        guard let prs = await client.fetchActivePRs() else {
            return .result(value: [])
        }
        let summaries = prs.prefix(10).map { "PR #\($0.prNumber): \($0.title) (\($0.repo))" }
        return .result(value: Array(summaries))
    }
}

// MARK: - App Shortcuts

struct StatefalseShortcuts: AppShortcutsProvider {
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
