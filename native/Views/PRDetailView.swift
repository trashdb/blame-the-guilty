import SwiftUI
import OSLog

private let draftLog = OSLog(subsystem: "com.blametheguilty", category: "draft")

private struct PRDetailsResponse: Decodable {
    let mergeableState: String?
    let behindBy: Int?
    let aheadBy: Int?
    let draft: Bool?
}

private struct MergeResponse: Decodable {
    let merged: Bool
    let sha: String?
    let message: String?
    let error: String?
}

private struct UpdateBranchResponse: Decodable {
    let message: String?
}

private struct CommitInfo: Decodable, Identifiable {
    var id: String { sha ?? UUID().uuidString }
    let sha: String?
    let message: String?
    let authorName: String?
    let authorLogin: String?
    let date: String?
    let url: String?
}

private struct FileInfo: Decodable, Identifiable {
    var id: String { filename ?? UUID().uuidString }
    let filename: String?
    let status: String?
    let additions: Int?
    let deletions: Int?
}

private struct CheckInfo: Decodable, Identifiable {
    var id: String { name ?? UUID().uuidString }
    let name: String?
    let status: String?
    let conclusion: String?
    let startedAt: String?
    let completedAt: String?
    let url: String?
}

struct PRDetailView: View {
    let pr: PullRequest
    let gitHubId: Int64
    let onDraftChanged: ((Bool) -> Void)?

    @State private var behindBy: Int?
    @State private var aheadBy: Int?
    @State private var detailError: String?
    @State private var merging = false
    @State private var mergeResult: String?
    @State private var mergeError: String?

    @State private var updatingBranch = false
    @State private var branchUpdateResult: String?
    @State private var branchUpdateError: String?

    @State private var togglingDraft = false
    @State private var draftError: String?
    @State private var localDraft: Bool

    @State private var selectedTab = 0

    @State private var commits: [CommitInfo] = []
    @State private var files: [FileInfo] = []
    @State private var checks: [CheckInfo] = []
    @State private var loadingCommits = false
    @State private var loadingFiles = false
    @State private var loadingChecks = false
    @State private var commitsError: String?
    @State private var filesError: String?
    @State private var checksError: String?

    init(pr: PullRequest, gitHubId: Int64, optimisticDraft: Bool? = nil, onDraftChanged: ((Bool) -> Void)? = nil) {
        self.pr = pr
        self.gitHubId = gitHubId
        self.onDraftChanged = onDraftChanged
        _localDraft = State(initialValue: optimisticDraft ?? pr.draft)
    }

    @AppStorage("workspacePath") private var workspacePath = TeamDefaults.workspacePath

    var canMerge: Bool {
        !localDraft && pr.ciStatus == "ready" && pr.reviewApproved
    }

    var compareUrl: URL {
        URL(string: "https://github.com/\(pr.repo)/compare/\(pr.baseBranch)...\(pr.headBranch)")!
    }

    var checksUrl: URL {
        URL(string: "\(pr.prUrl)/checks")!
    }

    @State private var mergeMethod = "squash"

    var hasComment: Bool {
        pr.lastCommentBy != nil && pr.lastCommentBody != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Picker("", selection: $selectedTab) {
                Text("Details").tag(0)
                Text("Commits").tag(1)
                Text("Files").tag(2)
                Text("Checks").tag(3)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
            .cursor(.pointingHand)

            switch selectedTab {
            case 0: detailsTab
            case 1: commitsTab
            case 2: filesTab
            case 3: checksTab
            default: detailsTab
            }
        }
        .padding(DS.Spacing.xxl)
        .frame(width: 320, height: 340)
        .animation(DS.Animation.default, value: selectedTab)
        .onAppear { loadDetails() }
        .onChange(of: selectedTab) { newTab in
            switch newTab {
            case 1 where commits.isEmpty && !loadingCommits: loadCommits()
            case 2 where files.isEmpty && !loadingFiles: loadFiles()
            case 3 where checks.isEmpty && !loadingChecks: loadChecks()
            default: break
            }
        }
        .closeOnEscape { PRDetailPanelManager.shared.close() }
        .closeOnCmdW { PRDetailPanelManager.shared.close() }
    }

    // MARK: - Details Tab
    @ViewBuilder
    private var detailsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                // Top links
                HStack(spacing: DS.Spacing.sm) {
                    Spacer()
                    linkButton("Open PR", url: pr.prUrl, help: "Open this pull request on GitHub")
                    if !pr.isMerged {
                        linkButton("Compare", url: compareUrl, help: "Compare base and head branches on GitHub")
                        linkButton("Checks", url: checksUrl, help: "View CI checks for this pull request")
                    }
                }

                // Badges
                if !pr.isMerged {
                    PRDetailBadges(pr: pr)
                }

                // Title
                Text(pr.title)
                    .font(DS.Font.title)
                    .foregroundStyle(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                // Repo → branch
                HStack(spacing: DS.Spacing.sm) {
                    Text(shortRepo(pr.repo))
                        .font(DS.Font.mono(11))
                        .foregroundStyle(DS.Color.textSecondary)
                    Text("→")
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textTertiary)
                    Text(pr.baseBranch)
                        .font(DS.Font.mono(11))
                        .foregroundStyle(DS.Color.accent)
                }

                // Head + PR number
                HStack(spacing: DS.Spacing.sm) {
                    Text("head:")
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.textTertiary)
                    Text(pr.headBranch)
                        .font(DS.Font.mono(10))
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text("PR #\(pr.prNumber)")
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.textSecondary)
                }

                if !pr.isMerged {
                    PRDetailDraftSection(
                        localDraft: $localDraft,
                        togglingDraft: togglingDraft,
                        draftError: draftError,
                        onToggle: performToggleDraft
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    PRDetailBehindAhead(
                        behindBy: behindBy,
                        aheadBy: aheadBy,
                        detailError: detailError,
                        updatingBranch: updatingBranch,
                        branchUpdateResult: branchUpdateResult,
                        branchUpdateError: branchUpdateError,
                        onUpdateBranch: performUpdateBranch
                    )

                    if canMerge {
                        PRDetailMergeSection(
                            merging: merging,
                            mergeResult: mergeResult,
                            mergeError: mergeError,
                            mergeMethod: $mergeMethod,
                            onMerge: performMerge
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                Divider()
                    .padding(.top, DS.Spacing.sm)

                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    Text("Latest Comment")
                        .font(DS.Font.small.medium())
                        .foregroundStyle(DS.Color.textSecondary)

                    if let commenter = pr.lastCommentBy, let body = pr.lastCommentBody {
                        PRDetailCommentCard(
                            commenter: commenter,
                            commentBody: body,
                            file: pr.lastReviewFilePath,
                            line: pr.lastReviewLine,
                            url: pr.lastCommentUrl ?? "https://github.com/\(pr.repo)/pull/\(pr.prNumber)",
                            pr: pr,
                            onOpenInIDE: openInRider
                        )
                    } else {
                        VStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "bubble.left")
                                .font(.title2)
                                .foregroundStyle(DS.Color.textTertiary)
                            Text("No comments yet")
                                .font(DS.Font.small)
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.xl)
                    }
                }
            }
            .animation(DS.Animation.default, value: canMerge)
            .animation(DS.Animation.default, value: localDraft)
        }
    }

    // MARK: - Commits Tab
    @ViewBuilder
    private var commitsTab: some View {
        Group {
            if loadingCommits {
                Spacer()
                ProgressView()
                Spacer()
            } else if let error = commitsError {
                VStack(spacing: DS.Spacing.md) {
                    Spacer()
                    Image(systemName: "exclamationmark.circle")
                        .font(.title2)
                        .foregroundStyle(DS.Color.destructive)
                    Text(error)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.destructive)
                        .multilineTextAlignment(.center)
                    solidButton("Retry", color: .blue) {
                        commitsError = nil
                        loadCommits()
                    }
                    Spacer()
                }
            } else if commits.isEmpty {
                VStack(spacing: DS.Spacing.sm) {
                    Spacer()
                    Image(systemName: "git.commit")
                        .font(.title2)
                        .foregroundStyle(DS.Color.textTertiary)
                    Text("No commits found")
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                }
            } else {
                List(commits) { commit in
                    Button {
                        if let urlStr = commit.url, let url = URL(string: urlStr) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(commit.message?.trimmingCharacters(in: .newlines) ?? "")
                                    .font(DS.Font.small.medium())
                                    .foregroundStyle(DS.Color.textPrimary)
                                    .lineLimit(2)
                                HStack(spacing: DS.Spacing.sm) {
                                    Text(commit.authorName ?? commit.authorLogin ?? "unknown")
                                        .font(DS.Font.caption)
                                        .foregroundStyle(DS.Color.accent)
                                    if let date = commit.date {
                                        Text(date)
                                            .font(DS.Font.caption)
                                            .foregroundStyle(DS.Color.textTertiary)
                                    }
                                }
                            }
                            Spacer()
                            if let sha = commit.sha, sha.count >= 7 {
                                Text(String(sha.prefix(7)))
                                    .font(DS.Font.mono(8))
                                    .foregroundStyle(DS.Color.textTertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Files Tab
    @ViewBuilder
    private var filesTab: some View {
        Group {
            if loadingFiles {
                Spacer()
                ProgressView()
                Spacer()
            } else if let error = filesError {
                VStack(spacing: DS.Spacing.md) {
                    Spacer()
                    Image(systemName: "exclamationmark.circle")
                        .font(.title2)
                        .foregroundStyle(DS.Color.destructive)
                    Text(error)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.destructive)
                        .multilineTextAlignment(.center)
                    solidButton("Retry", color: .blue) {
                        filesError = nil
                        loadFiles()
                    }
                    Spacer()
                }
            } else if files.isEmpty {
                VStack(spacing: DS.Spacing.sm) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.title2)
                        .foregroundStyle(DS.Color.textTertiary)
                    Text("No files changed")
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                }
            } else {
                List(files) { file in
                    Button {
                        if let filename = file.filename {
                            openInRider(file: filename, line: nil)
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: statusIcon(file.status))
                                .font(DS.Font.caption)
                                .foregroundStyle(statusColor(file.status))
                            Text(file.filename ?? "")
                                .font(DS.Font.small)
                                .foregroundStyle(DS.Color.textPrimary)
                            Spacer()
                            if let adds = file.additions, adds > 0 {
                                Text("+\(adds)")
                                    .font(DS.Font.mono(8))
                                    .foregroundStyle(DS.Color.success)
                            }
                            if let dels = file.deletions, dels > 0 {
                                Text("-\(dels)")
                                    .font(DS.Font.mono(8))
                                    .foregroundStyle(DS.Color.destructive)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Checks Tab
    @ViewBuilder
    private var checksTab: some View {
        Group {
            if loadingChecks {
                Spacer()
                ProgressView()
                Spacer()
            } else if let error = checksError {
                VStack(spacing: DS.Spacing.md) {
                    Spacer()
                    Image(systemName: "exclamationmark.circle")
                        .font(.title2)
                        .foregroundStyle(DS.Color.destructive)
                    Text(error)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.destructive)
                        .multilineTextAlignment(.center)
                    solidButton("Retry", color: .blue) {
                        checksError = nil
                        loadChecks()
                    }
                    Spacer()
                }
            } else if checks.isEmpty {
                VStack(spacing: DS.Spacing.sm) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(DS.Color.textTertiary)
                    Text("No checks found")
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                }
            } else {
                List(checks) { check in
                    Button {
                        if let urlStr = check.url, let url = URL(string: urlStr) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: checkIcon(check.conclusion))
                                .font(DS.Font.small)
                                .foregroundStyle(checkColor(check.conclusion))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.name ?? "")
                                    .font(DS.Font.small.medium())
                                    .foregroundStyle(DS.Color.textPrimary)
                                HStack(spacing: DS.Spacing.sm) {
                                    Text(check.status ?? "")
                                        .font(DS.Font.caption)
                                        .foregroundStyle(DS.Color.textTertiary)
                                    if let conclusion = check.conclusion {
                                        Text(conclusion)
                                            .font(DS.Font.caption)
                                            .foregroundStyle(checkColor(conclusion))
                                    }
                                }
                            }
                            Spacer()
                            if let started = parseDate(check.startedAt ?? "") {
                                Text(started, style: .relative)
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Color.textTertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers
    private func statusIcon(_ status: String?) -> String {
        switch status {
        case "added": return "plus.circle"
        case "modified": return "pencil.circle"
        case "removed": return "minus.circle"
        case "renamed": return "arrow.right.circle"
        default: return "doc.circle"
        }
    }

    private func statusColor(_ status: String?) -> Color {
        switch status {
        case "added": return DS.Color.success
        case "removed": return DS.Color.destructive
        case "modified": return DS.Color.accent
        default: return DS.Color.textSecondary
        }
    }

    private func checkIcon(_ conclusion: String?) -> String {
        switch conclusion {
        case "success": return "checkmark.circle.fill"
        case "failure": return "xmark.circle.fill"
        case "cancelled": return "slash.circle"
        case "neutral": return "minus.circle"
        default: return "questionmark.circle"
        }
    }

    private func checkColor(_ conclusion: String?) -> Color {
        switch conclusion {
        case "success": return DS.Color.success
        case "failure": return DS.Color.destructive
        case "cancelled": return DS.Color.textTertiary
        case "neutral": return DS.Color.textSecondary
        default: return DS.Color.textTertiary
        }
    }

    private func parseDate(_ str: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: str) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: str)
    }

    // MARK: - Actions
    private func performMerge() {
        merging = true
        mergeResult = nil
        mergeError = nil
        let repoEscaped = pr.repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pr.repo
        guard let url = URL(string: "\(backendUrl)/api/pullrequests/\(pr.prNumber)/merge?repo=\(repoEscaped)&gitHubId=\(gitHubId)&method=\(mergeMethod)") else {
            mergeError = "Invalid URL"
            merging = false
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request) { data, _, err in
            DispatchQueue.main.async {
                merging = false
                if let err { mergeError = err.localizedDescription; return }
                guard let data else { return }
                if let resp = try? JSONDecoder().decode(MergeResponse.self, from: data) {
                    if resp.merged {
                        mergeResult = resp.message ?? "Merged"
                    } else {
                        mergeError = resp.error ?? resp.message ?? "Merge failed"
                    }
                } else {
                    mergeError = "Invalid response"
                }
            }
        }.resume()
    }

    private func performToggleDraft(_ makeDraft: Bool) {
        let previousDraft = localDraft
        localDraft = makeDraft
        onDraftChanged?(makeDraft)
        draftError = nil
        togglingDraft = true

        let repoStr = pr.repo
        let repoEscaped = repoStr.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repoStr
        let urlStr = "\(backendUrl)/api/pullrequests/\(pr.prNumber)/draft?repo=\(repoEscaped)&gitHubId=\(gitHubId)&draft=\(makeDraft ? "true" : "false")"
        guard let url = URL(string: urlStr) else {
            localDraft = previousDraft
            onDraftChanged?(previousDraft)
            draftError = "Invalid URL"
            togglingDraft = false
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request) { data, resp, err in
            DispatchQueue.main.async {
                self.togglingDraft = false
                if let err {
                    self.localDraft = previousDraft
                    self.onDraftChanged?(previousDraft)
                    self.draftError = err.localizedDescription
                    return
                }
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if status >= 400 {
                    self.localDraft = previousDraft
                    self.onDraftChanged?(previousDraft)
                    self.draftError = "HTTP \(status)"
                }
            }
        }.resume()
    }

    private func performUpdateBranch() {
        updatingBranch = true
        branchUpdateResult = nil
        branchUpdateError = nil
        let repoEscaped = pr.repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pr.repo
        guard let url = URL(string: "\(backendUrl)/api/pullrequests/\(pr.prNumber)/update-branch?repo=\(repoEscaped)&gitHubId=\(gitHubId)") else {
            branchUpdateError = "Invalid URL"
            updatingBranch = false
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request) { data, resp, err in
            DispatchQueue.main.async {
                self.updatingBranch = false
                if let err { self.branchUpdateError = err.localizedDescription; return }
                guard let data else { return }
                if let decoded = try? JSONDecoder().decode(UpdateBranchResponse.self, from: data) {
                    self.branchUpdateResult = decoded.message ?? "Branch updated"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.loadDetails() }
                } else {
                    let raw = String(data: data, encoding: .utf8) ?? "non-utf8"
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    if status >= 200 && status < 300 {
                        self.branchUpdateResult = "Update sent (check PR on GitHub)"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.loadDetails() }
                    } else {
                        self.branchUpdateError = "\(raw.prefix(200))"
                    }
                }
            }
        }.resume()
    }

    private func loadDetails() {
        let repoEscaped = pr.repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pr.repo
        guard let url = URL(string: "\(backendUrl)/api/pullrequests/\(pr.prNumber)/detail?repo=\(repoEscaped)&gitHubId=\(gitHubId)") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err { self.detailError = err.localizedDescription; return }
                guard let data else { return }
                if let decoded = try? JSONDecoder().decode(PRDetailsResponse.self, from: data) {
                    withAnimation(DS.Animation.default) {
                        self.behindBy = decoded.behindBy
                        self.aheadBy = decoded.aheadBy
                    }
                    if decoded.behindBy == 0 {
                        self.branchUpdateResult = nil
                        self.branchUpdateError = nil
                    }
                    if let backendDraft = decoded.draft, !self.togglingDraft {
                        if backendDraft != self.localDraft {
                            self.localDraft = backendDraft
                            self.onDraftChanged?(backendDraft)
                        }
                    }
                } else {
                    let raw = String(data: data, encoding: .utf8) ?? "non-utf8"
                    self.detailError = "Parse error: \(raw.prefix(200))"
                }
            }
        }.resume()
    }

    private func loadCommits() {
        loadingCommits = true
        commitsError = nil
        let repoEscaped = pr.repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pr.repo
        guard let url = URL(string: "\(backendUrl)/api/pullrequests/\(pr.prNumber)/commits?repo=\(repoEscaped)&gitHubId=\(gitHubId)") else {
            loadingCommits = false; commitsError = "Invalid URL"; return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                loadingCommits = false
                if let err { commitsError = err.localizedDescription; return }
                guard let data else { commitsError = "No data"; return }
                do {
                    let decoded = try JSONDecoder().decode([CommitInfo].self, from: data)
                    commits = decoded
                } catch {
                    commitsError = "Parse error: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    private func loadFiles() {
        loadingFiles = true
        filesError = nil
        let repoEscaped = pr.repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pr.repo
        guard let url = URL(string: "\(backendUrl)/api/pullrequests/\(pr.prNumber)/files?repo=\(repoEscaped)&gitHubId=\(gitHubId)") else {
            loadingFiles = false; filesError = "Invalid URL"; return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                loadingFiles = false
                if let err { filesError = err.localizedDescription; return }
                guard let data else { filesError = "No data"; return }
                do {
                    let decoded = try JSONDecoder().decode([FileInfo].self, from: data)
                    files = decoded
                } catch {
                    filesError = "Parse error: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    private func loadChecks() {
        loadingChecks = true
        checksError = nil
        let repoEscaped = pr.repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pr.repo
        guard let url = URL(string: "\(backendUrl)/api/pullrequests/\(pr.prNumber)/checks?repo=\(repoEscaped)&gitHubId=\(gitHubId)") else {
            loadingChecks = false; checksError = "Invalid URL"; return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                loadingChecks = false
                if let err { checksError = err.localizedDescription; return }
                guard let data else { checksError = "No data"; return }
                do {
                    let decoded = try JSONDecoder().decode([CheckInfo].self, from: data)
                    checks = decoded
                } catch {
                    checksError = "Parse error: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    private func openInRider(file: String, line: Int?) {
        Task {
            let gitService = currentDependencies.gitService
            guard let repoPath = await gitService.findRepoPath(ownerRepo: pr.repo, workspacePath: workspacePath) else {
                return
            }
            let fullPath = (repoPath as NSString).appendingPathComponent(file)
            IDEOpener.openFile(filePath: fullPath, line: line)
        }
    }
}

// MARK: - Extracted Subviews

struct PRDetailBadges: View {
    let pr: PullRequest

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            let mergeColor = DS.Color.mergeableColor(pr.mergeableState)
            Text(DS.Color.mergeableLabel(pr.mergeableState))
                .badge(DS.Color.mergeableLabel(pr.mergeableState), color: mergeColor)

            let ciColor: SwiftUI.Color = pr.ciStatus == "failed" ? DS.Color.statusRed
                : pr.ciStatus == "waiting" ? DS.Color.statusOrange
                : pr.ciStatus == "review" ? DS.Color.statusBlue
                : DS.Color.statusGreen
            let ciLabel: String = pr.ciStatus == "waiting" ? "CI WAITING"
                : pr.ciStatus == "failed" ? "CI FAIL"
                : pr.ciStatus == "review" ? "CI READY"
                : "CI READY"
            Text(ciLabel)
                .badge(ciLabel, color: ciColor)

            if let c = pr.conclusion {
                let clColor: SwiftUI.Color = c == "success" ? DS.Color.statusGreen : c == "failure" ? DS.Color.statusRed : DS.Color.statusGray
                let clLabel: String = c == "success" ? "CHECKS PASS"
                    : c == "failure" ? "CHECKS FAIL"
                    : c == "neutral" ? "CHECKS NEUTRAL"
                    : c.uppercased()
                Text(clLabel)
                    .badge(clLabel, color: clColor)
            }

            if pr.reviewApproved {
                Text("APPROVED")
                    .badge("APPROVED", color: DS.Color.statusGreen)
            }

            Spacer()
        }
        .transition(.scale.combined(with: .opacity))
    }
}

struct PRDetailDraftSection: View {
    @Binding var localDraft: Bool
    let togglingDraft: Bool
    let draftError: String?
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            if localDraft {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "pencil")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.badgeGray)
                    Text("Draft")
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.badgeGray)
                }
                .transition(.opacity)
                solidButton("Mark Ready", color: .blue, disabled: togglingDraft, help: "Mark this pull request as ready for review") {
                    onToggle(false)
                }
            } else {
                actionButton("Convert to Draft", color: .gray, help: "Convert this pull request back to draft") {
                    onToggle(true)
                }
                .transition(.opacity)
            }
            if let err = draftError {
                Text(err)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.destructive)
                    .transition(.opacity)
            }
            if togglingDraft {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.5)))
            }
        }
        .animation(DS.Animation.default, value: localDraft)
        .animation(DS.Animation.default, value: togglingDraft)
        .animation(DS.Animation.default, value: draftError != nil)
    }
}

struct PRDetailBehindAhead: View {
    let behindBy: Int?
    let aheadBy: Int?
    let detailError: String?
    let updatingBranch: Bool
    let branchUpdateResult: String?
    let branchUpdateError: String?
    let onUpdateBranch: () -> Void

    var body: some View {
        if let behind = behindBy, let ahead = aheadBy {
            Divider()
            VStack(spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.xl) {
                    if behind > 0 {
                        Label("\(behind) behind", systemImage: "arrow.down")
                            .font(DS.Font.small.medium())
                            .foregroundStyle(DS.Color.badgeOrange)
                    } else {
                        Label("Up to date", systemImage: "checkmark")
                            .font(DS.Font.small.medium())
                            .foregroundStyle(DS.Color.success)
                    }
                    if ahead > 0 {
                        Label("\(ahead) ahead", systemImage: "arrow.up")
                            .font(DS.Font.small.medium())
                            .foregroundStyle(DS.Color.accent)
                    }
                    Spacer()
                    if behind > 0 {
                        if updatingBranch {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12)
                                .transition(.opacity)
                        } else if let result = branchUpdateResult {
                            Text(result)
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.success)
                                .transition(.opacity)
                        } else {
                            solidButton("Update branch", color: .orange, help: "Merge the latest base branch into this PR") {
                                onUpdateBranch()
                            }
                            .transition(.opacity)
                        }
                    }
                }
                if let err = branchUpdateError {
                    Text(err)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.destructive)
                        .transition(.opacity)
                }
            }
            .animation(DS.Animation.default, value: updatingBranch)
            .animation(DS.Animation.default, value: branchUpdateResult != nil)
            .animation(DS.Animation.default, value: branchUpdateError != nil)
        }
        if let error = detailError {
            Text(error)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.destructive)
                .transition(.opacity)
        }
    }
}

struct PRDetailMergeSection: View {
    let merging: Bool
    let mergeResult: String?
    let mergeError: String?
    @Binding var mergeMethod: String
    let onMerge: () -> Void

    var body: some View {
        Divider()
        VStack(spacing: DS.Spacing.md) {
            if let result = mergeResult {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.success)
                    Text(result)
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.success)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if let err = mergeError {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.destructive)
                    Text(err)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.destructive)
                        .lineLimit(2)
                }
                .transition(.opacity)
            }
            HStack(spacing: DS.Spacing.md) {
                if merging {
                    ProgressView()
                        .scaleEffect(0.4)
                        .frame(width: 12)
                        .transition(.opacity)
                }
                Picker("", selection: $mergeMethod) {
                    Text("Squash").tag("squash")
                    Text("Rebase").tag("rebase")
                    Text("Merge").tag("merge")
                }
                .pickerStyle(.segmented)
                .scaleEffect(0.75)
                .frame(width: 140)
                .disabled(merging)
                .cursor(.pointingHand)

                solidButton("Merge", color: .green, disabled: merging, help: "Merge this pull request") {
                    onMerge()
                }
            }
        }
        .animation(DS.Animation.default, value: merging)
        .animation(DS.Animation.default, value: mergeResult != nil)
        .animation(DS.Animation.default, value: mergeError != nil)
    }
}

struct PRDetailCommentCard: View {
    let commenter: String
    let commentBody: String
    let file: String?
    let line: Int?
    let url: String
    let pr: PullRequest
    let onOpenInIDE: (String, Int?) -> Void

    var body: some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "bubble.left")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.accent)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    HStack(spacing: DS.Spacing.sm) {
                        Text("@\(commenter)")
                            .font(DS.Font.small.medium())
                            .foregroundStyle(DS.Color.accent)
                        if let file = file {
                            Text(shortFile(file))
                                .font(DS.Font.mono(8))
                                .foregroundStyle(DS.Color.textTertiary)
                            if let line = line {
                                Text(":\(line)")
                                    .font(DS.Font.mono(8))
                                    .foregroundStyle(DS.Color.textTertiary)
                            }
                        }
                    }
                    Text(String(commentBody.prefix(200)).replacingOccurrences(of: "\n", with: " "))
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(4)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Color.accent.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }
}

private func shortFile(_ path: String) -> String {
    let parts = path.split(separator: "/")
    return parts.suffix(2).joined(separator: "/")
}
