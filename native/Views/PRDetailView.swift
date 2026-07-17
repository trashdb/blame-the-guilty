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

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            // Top links
            HStack(spacing: DS.Spacing.sm) {
                Spacer()
                linkButton("Open PR", url: pr.prUrl)
                if !pr.isMerged {
                    linkButton("Compare", url: compareUrl)
                    linkButton("Checks", url: checksUrl)
                }
            }

            // Badges (non-merged only)
            if !pr.isMerged {
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
                draftSection
                commentSection
                behindAheadSection
                mergeSection
            }

            Spacer()
        }
        .padding(DS.Spacing.xxl)
        .frame(width: 320, height: 300)
        .onAppear { loadDetails() }
    }

    // MARK: - Draft Toggle
    @ViewBuilder
    private var draftSection: some View {
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
                solidButton("Mark Ready", color: .blue, disabled: togglingDraft) {
                    performToggleDraft(false)
                }
            } else {
                actionButton("Convert to Draft", color: .gray) {
                    performToggleDraft(true)
                }
            }
            if let err = draftError {
                Text(err)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.destructive)
            }
            if togglingDraft {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12)
            }
        }
    }

    // MARK: - Comment
    @ViewBuilder
    private var commentSection: some View {
        if let commenter = pr.lastCommentBy, let body = pr.lastCommentBody {
            HStack(spacing: DS.Spacing.sm) {
                Button {
                    let urlString = pr.lastCommentUrl ?? "https://github.com/\(pr.repo)/pull/\(pr.prNumber)"
                    if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
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
                                if let file = pr.lastReviewFilePath {
                                    Text(shortFile(file))
                                        .font(DS.Font.mono(8))
                                        .foregroundStyle(DS.Color.textTertiary)
                                    if let line = pr.lastReviewLine {
                                        Text(":\(line)")
                                            .font(DS.Font.mono(8))
                                            .foregroundStyle(DS.Color.textTertiary)
                                    }
                                }
                            }
                            Text(String(body.prefix(120)).replacingOccurrences(of: "\n", with: " "))
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Color.accent.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)

                if let file = pr.lastReviewFilePath {
                    Button {
                        openInRider(file: file, line: pr.lastReviewLine)
                    } label: {
                        Image(systemName: "arrowtriangle.right.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                    .help("Open in \(UserDefaults.standard.string(forKey: "defaultIDE") ?? "Rider")")
                }
            }
        }
    }

    // MARK: - Behind / Ahead
    @ViewBuilder
    private var behindAheadSection: some View {
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
                        } else if let result = branchUpdateResult {
                            Text(result)
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.success)
                        } else {
                            solidButton("Update branch", color: .orange) {
                                performUpdateBranch()
                            }
                        }
                    }
                }
                if let err = branchUpdateError {
                    Text(err)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.destructive)
                }
            }
        }
        if let error = detailError {
            Text(error)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.destructive)
        }
    }

    // MARK: - Merge
    @ViewBuilder
    private var mergeSection: some View {
        if canMerge {
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
                }
                HStack(spacing: DS.Spacing.md) {
                    if merging {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 12)
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

                    solidButton("Merge", color: .green, disabled: merging) {
                        performMerge()
                    }
                }
            }
        }
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

    private func openInRider(file: String, line: Int?) {
        Task {
            let gitService = GitService()
            guard let repoPath = await gitService.findRepoPath(ownerRepo: pr.repo, workspacePath: workspacePath) else {
                return
            }
            let fullPath = (repoPath as NSString).appendingPathComponent(file)
            IDEOpener.openFile(filePath: fullPath, line: line)
        }
    }
}

private func shortFile(_ path: String) -> String {
    let parts = path.split(separator: "/")
    return parts.suffix(2).joined(separator: "/")
}
