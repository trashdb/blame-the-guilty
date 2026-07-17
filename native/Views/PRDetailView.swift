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

    var mergeableInfo: (label: String, color: Color) {
        guard let state = pr.mergeableState else {
            return ("UNKNOWN", .gray)
        }
        switch state {
        case "clean":        return ("READY TO MERGE", .green)
        case "behind":       return ("BEHIND BASE", .orange)
        case "dirty":        return ("HAS CONFLICTS", .red)
        case "unstable":     return ("CHECKS FAILING", .yellow)
        case "has_hooks":    return ("PENDING", .blue)
        case "unknown":      return ("CHECKING...", .gray)
        default:             return (state.uppercased(), .gray)
        }
    }

    var ciInfo: (label: String, color: Color) {
        switch pr.ciStatus {
        case "waiting": return ("CI WAITING", .orange)
        case "failed":  return ("CI FAIL", .red)
        case "review":  return ("CI READY", .blue)
        default:        return ("CI READY", .green)
        }
    }

    var approvalInfo: (label: String, color: Color)? {
        if pr.reviewApproved {
            return ("APPROVED", .green)
        }
        if pr.ciStatus == "ready" && !pr.reviewApproved {
            return nil // already green
        }
        return nil
    }

    var conclusionInfo: (label: String, color: Color)? {
        guard let c = pr.conclusion else { return nil }
        switch c {
        case "success": return ("CHECKS PASS", .green)
        case "failure": return ("CHECKS FAIL", .red)
        case "neutral": return ("CHECKS NEUTRAL", .gray)
        default:        return (c.uppercased(), .secondary)
        }
    }

    var compareUrl: URL {
        URL(string: "https://github.com/\(pr.repo)/compare/\(pr.baseBranch)...\(pr.headBranch)")!
    }

    var checksUrl: URL {
        URL(string: "\(pr.prUrl)/checks")!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Spacer()
                linkButton("Open PR", url: pr.prUrl)
                if !pr.isMerged {
                    linkButton("Compare", url: compareUrl)
                    linkButton("Checks", url: checksUrl)
                }
            }

            if !pr.isMerged {
                HStack(spacing: 6) {
                        let m = mergeableInfo
                        Text(m.label)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(m.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(m.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))

                        let c = ciInfo
                        Text(c.label)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(c.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(c.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))

                        if let cl = conclusionInfo {
                            Text(cl.label)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(cl.color)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(cl.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                        }

                        if let a = approvalInfo {
                            Text(a.label)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(a.color)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(a.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                        }

                        Spacer()
                    }
                }

                Text(pr.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.9))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text(shortRepo(pr.repo))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("→")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(pr.baseBranch)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.blue)
                }

                HStack(spacing: 4) {
                Text("head:")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(pr.headBranch)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("PR #\(pr.prNumber)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if !pr.isMerged {
                HStack(spacing: 6) {
                    if localDraft {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 9))
                                .foregroundStyle(.gray)
                            Text("Draft")
                                .font(.system(size: 10))
                                .foregroundStyle(.gray)
                        }
                        draftButton(makeDraft: false, label: "Mark Ready", color: .blue)
                    } else {
                        draftButton(makeDraft: true, label: "Convert to Draft", color: .gray)
                    }
                    if let err = draftError {
                        Text(err)
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                    }
                }

                if let commenter = pr.lastCommentBy, let body = pr.lastCommentBody {
                    HStack(spacing: 4) {
                        Button {
                            let urlString = pr.lastCommentUrl ?? "https://github.com/\(pr.repo)/pull/\(pr.prNumber)"
                            if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bubble.left")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text("@\(commenter)")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.blue)
                                        if let file = pr.lastReviewFilePath {
                                            Text(shortFile(file))
                                                .font(.system(size: 8, design: .monospaced))
                                                .foregroundStyle(.tertiary)
                                            if let line = pr.lastReviewLine {
                                                Text(":\(line)")
                                                    .font(.system(size: 8, design: .monospaced))
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }
                                    }
                                    Text(String(body.prefix(120)).replacingOccurrences(of: "\n", with: " "))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
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

                if let behind = behindBy, let ahead = aheadBy {
                    Divider()
                    HStack(spacing: 12) {
                        if behind > 0 {
                            Label("\(behind) behind", systemImage: "arrow.down")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.orange)
                        } else {
                            Label("Up to date", systemImage: "checkmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.green)
                        }
                        if ahead > 0 {
                            Label("\(ahead) ahead", systemImage: "arrow.up")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.blue)
                        }
                        Spacer()
                        if behind > 0 {
                            if updatingBranch {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 12)
                            } else if let result = branchUpdateResult {
                                Text(result)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.green)
                            } else {
                                Button {
                                    performUpdateBranch()
                                } label: {
                                    Text("Update branch")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.orange, in: RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                                .cursor(.pointingHand)
                            }
                        }
                    }
                    if let err = branchUpdateError {
                        Text(err)
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                    }
                }
                if let error = detailError {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                }

                if canMerge {
                    Divider()
                    if let result = mergeResult {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                            Text(result)
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                        }
                    } else if let err = mergeError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                            Text(err)
                                .font(.system(size: 9))
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                    }
                    HStack(spacing: 6) {
                        if merging {
                            ProgressView()
                                .scaleEffect(0.4)
                                .frame(width: 12)
                        }
                        mergeMethodPicker
                        mergeButton
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .frame(width: 320, height: 300)
        .onAppear { loadDetails() }
    }

    private func linkButton(_ label: String, url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }

    @State private var mergeMethod = "squash"

    private var mergeMethodPicker: some View {
        Picker("", selection: $mergeMethod) {
            Text("Squash").tag("squash")
            Text("Rebase").tag("rebase")
            Text("Merge").tag("merge")
        }
        .pickerStyle(.segmented)
        .scaleEffect(0.75)
        .frame(width: 140)
        .disabled(merging)
    }

    private var mergeButton: some View {
        Button {
            performMerge()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 10))
                Text("Merge")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.green.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
        .disabled(merging)
    }

    private func draftButton(makeDraft: Bool, label: String, color: Color) -> some View {
        Button {
            performToggleDraft(makeDraft)
        } label: {
            if togglingDraft {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12)
            } else {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(makeDraft ? Color.gray : Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color.opacity(makeDraft ? 0.15 : 0.8), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
        .disabled(togglingDraft)
    }

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
        // Optimistic update: flip immediately before the API call
        let previousDraft = localDraft
        localDraft = makeDraft
        onDraftChanged?(makeDraft)
        draftError = nil
        togglingDraft = true

        let repoStr = pr.repo
        let repoEscaped = repoStr.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repoStr
        let urlStr = "\(backendUrl)/api/pullrequests/\(pr.prNumber)/draft?repo=\(repoEscaped)&gitHubId=\(gitHubId)&draft=\(makeDraft ? "true" : "false")"
        os_log("[Draft] URL: %{public}@", log: draftLog, type: .debug, urlStr)
        guard let url = URL(string: urlStr) else {
            localDraft = previousDraft
            onDraftChanged?(previousDraft)
            draftError = "Invalid URL"
            os_log("[Draft] Invalid URL: %{public}@", log: draftLog, type: .error, urlStr)
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
                    os_log("[Draft] ❌ Network error, reverted to %d: %{public}@", log: draftLog, type: .error, previousDraft, err.localizedDescription)
                    return
                }
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "nil"
                os_log("[Draft] HTTP %d: %{public}@", log: draftLog, type: .debug, status, String(body.prefix(500)))
                if status >= 400 {
                    self.localDraft = previousDraft
                    self.onDraftChanged?(previousDraft)
                    self.draftError = "HTTP \(status): \(body.prefix(200))"
                    os_log("[Draft] ❌ HTTP %d, reverted to %d", log: draftLog, type: .error, status, previousDraft)
                }
                // 2xx success → localDraft stays as makeDraft (already set optimistically)
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
                // Try to decode the response
                if let decoded = try? JSONDecoder().decode(UpdateBranchResponse.self, from: data) {
                    self.branchUpdateResult = decoded.message ?? "Branch updated"
                    // Reload PR details after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        self.loadDetails()
                    }
                } else {
                    let raw = String(data: data, encoding: .utf8) ?? "non-utf8"
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    // If status is not 2xx, show as error
                    if status >= 200 && status < 300 {
                        self.branchUpdateResult = "Update sent (check PR on GitHub)"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            self.loadDetails()
                        }
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
        URLSession.shared.dataTask(with: url) { data, resp, err in
            DispatchQueue.main.async {
                if let err { self.detailError = err.localizedDescription; return }
                guard let data else { return }
                if let decoded = try? JSONDecoder().decode(PRDetailsResponse.self, from: data) {
                    self.behindBy = decoded.behindBy
                    self.aheadBy = decoded.aheadBy
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
                os_log("[PRDetail] Could not find repo %{public}@ in workspace", log: draftLog, type: .error, pr.repo)
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
