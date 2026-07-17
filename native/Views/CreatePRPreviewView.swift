import SwiftUI

struct CreatePRPreviewView: View {
    let repoPath: String
    let branchName: String
    let backendUrl: String
    let gitHubId: Int64
    let onComplete: (URL) -> Void
    var onCancel: (() -> Void)?

    @State private var title: String
    @State private var bodyText: String
    @State private var isLoading = true
    @State private var isCreating = false
    @State private var suggestedBody: String?
    @State private var summary: String?
    @State private var errorMessage: String?

    private let git = GitService()

    init(repoPath: String, branchName: String, backendUrl: String, gitHubId: Int64, onComplete: @escaping (URL) -> Void, onCancel: (() -> Void)? = nil) {
        self.repoPath = repoPath
        self.branchName = branchName
        self.backendUrl = backendUrl
        self.gitHubId = gitHubId
        self.onComplete = onComplete
        self.onCancel = onCancel
        let ticketMatch = branchName.range(of: #"[A-Z]+-\d+"#, options: .regularExpression)
        let ticket = ticketMatch.map { String(branchName[$0]) }
        let cleaned = branchName
            .replacingOccurrences(of: #"^(feature|fix|hotfix|bugfix|chore|release)/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[A-Z]+-\d+[-_]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let desc = cleaned.split(separator: "/").map { $0.capitalized }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if let t = ticket {
            _title = State(initialValue: "[\(t)] \(desc)")
        } else {
            _title = State(initialValue: desc)
        }
        _bodyText = State(initialValue: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create Pull Request")
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 3) {
                Text("Title").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(6)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.1), lineWidth: 1))
            }

            if isLoading {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.5)
                    Text("Loading template…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if let summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 9))
                            .foregroundStyle(.purple)
                        Text("Copilot Summary")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.purple)
                    }
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.8))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Description").font(.system(size: 10)).foregroundStyle(.secondary)
                    if isLoading {
                        ProgressView().scaleEffect(0.4)
                    }
                }
                ScrollView {
                    TextEditor(text: $bodyText)
                        .font(.system(size: 10, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 200)
                }
                .padding(6)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.1), lineWidth: 1))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                if let summary, !summary.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 8))
                            .foregroundStyle(.purple)
                        Text("Copilot summary included")
                            .font(.system(size: 9))
                            .foregroundStyle(.purple)
                    }
                }
                Spacer()
                if isCreating {
                    ProgressView().scaleEffect(0.5).frame(width: 12)
                }
                Button("Cancel") { onCancel?() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                Button("Create PR") { Task { await createPR() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                    .disabled(isCreating)
            }
        }
        .padding(12)
        .frame(width: 440, height: 380)
        .onAppear { Task { await loadPreview() } }
    }

    private func loadPreview() async {
        guard let fullName = await git.repoFullName(repoPath: repoPath) else {
            errorMessage = "Could not determine repo owner/name"
            isLoading = false
            return
        }
        let base = await git.baseRefName(repoPath: repoPath) ?? "main"
        let cleanBase = base.hasPrefix("origin/") ? String(base.dropFirst(7)) : base
        let repoEncoded = fullName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fullName
        let headEncoded = branchName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? branchName

        guard let url = URL(string: "\(backendUrl)/api/github/pr-preview?gitHubId=\(gitHubId)&repo=\(repoEncoded)&head=\(headEncoded)&baseBranch=\(cleanBase)&title=\(title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title)") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                struct ErrResp: Decodable { let error: String? }
                if let err = try? JSONDecoder().decode(ErrResp.self, from: data), let msg = err.error {
                    errorMessage = msg
                } else {
                    errorMessage = "Server error"
                }
                isLoading = false
                return
            }
            struct PreviewData: Decodable { let summary: String; let suggestedBody: String }
            let decoded = try JSONDecoder().decode(PreviewData.self, from: data)
            summary = decoded.summary.isEmpty ? nil : decoded.summary
            if !decoded.suggestedBody.isEmpty {
                bodyText = decoded.suggestedBody
                suggestedBody = decoded.suggestedBody
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func createPR() async {
        isCreating = true
        do {
            let result = try await git.createPR(
                repoPath: repoPath, branchName: branchName,
                backendUrl: backendUrl, gitHubId: gitHubId,
                overrideTitle: title, overrideBody: bodyText
            )
            onComplete(result.url)
        } catch {
            errorMessage = (error as? GitService.GitError)?.localizedDescription ?? error.localizedDescription
        }
        isCreating = false
    }
}
