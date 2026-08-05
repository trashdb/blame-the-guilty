import SwiftUI

struct CreatePRPreviewView: View {
    let repoPath: String
    let branchName: String
    let backendUrl: String
    let gitHubId: Int64
    let token: String?
    let api: ApiClientProtocol
    let onComplete: (URL) -> Void
    var onCancel: (() -> Void)?

    @State private var title: String
    @State private var bodyText: String
    @State private var subscribersText: String = ""
    @State private var isLoading = true
    @State private var isCreating = false
    @State private var suggestedBody: String?
    @State private var summary: String?
    @State private var errorMessage: String?
    
    // Subscriber dropdown
    @State private var availableUsers: [ApiAvailableUser] = []
    @State private var isLoadingUsers = false
    @State private var selectedUserIds: Set<Int64> = []
    @State private var showSubscriberPicker = false

    @State private var isGeneratingAI = false
    @Environment(\.dependencies) private var deps

    private var git: GitServiceProtocol { deps.gitService }

    init(repoPath: String, branchName: String, backendUrl: String, gitHubId: Int64, token: String?, api: ApiClientProtocol, onComplete: @escaping (URL) -> Void, onCancel: (() -> Void)? = nil) {
        self.repoPath = repoPath
        self.branchName = branchName
        self.backendUrl = backendUrl
        self.gitHubId = gitHubId
        self.token = token
        self.api = api
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
        ZStack {
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
                        Text(isGeneratingAI ? "Generating AI summary…" : "Loading template…")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("Description").font(.system(size: 10)).foregroundStyle(.secondary)
                        if isLoading {
                            ProgressView().scaleEffect(0.4)
                        }
                        Spacer()
                        if isGeneratingAI {
                            ProgressView().scaleEffect(0.5).frame(width: 12)
                        } else if (summary?.isEmpty ?? true) {
                            Button {
                                Task { await generateWithAI() }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkle")
                                        .font(.system(size: 9))
                                    Text("Generate with AI")
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoading)
                            .cursor(.pointingHand)
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

                VStack(alignment: .leading, spacing: 3) {
                    Text("Subscribers").font(.system(size: 10)).foregroundStyle(.secondary)
                    
                    if !selectedUserIds.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(availableUsers.filter { selectedUserIds.contains($0.gitHubId) }) { user in
                                    HStack(spacing: 4) {
                                        Text("@\(user.login)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(DS.Color.textPrimary)
                                        Button {
                                            selectedUserIds.remove(user.gitHubId)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 10))
                                                .foregroundStyle(DS.Color.textTertiary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(DS.Color.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }
                    }
                    
                    Button {
                        Task { await loadAvailableUsers() }
                        showSubscriberPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 10))
                            Text(selectedUserIds.isEmpty ? "Add subscribers" : "\(selectedUserIds.count) selected")
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .foregroundStyle(selectedUserIds.isEmpty ? DS.Color.textSecondary : DS.Color.accent)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(selectedUserIds.isEmpty ? DS.Color.textTertiary.opacity(0.3) : DS.Color.accent.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
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
                        .cursor(.pointingHand)
                    Button("Create PR") { Task { await createPR() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                        .disabled(isCreating)
                        .cursor(.pointingHand)
                }
            }
            .padding(EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16))
            .frame(width: 440, height: 440)
            
            if showSubscriberPicker {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { showSubscriberPicker = false }
                    .allowsHitTesting(true)
                
                SubscriberPickerView(
                    availableUsers: availableUsers,
                    selectedIds: $selectedUserIds,
                    onDone: { showSubscriberPicker = false },
                    onCancel: { showSubscriberPicker = false }
                )
                .frame(width: 220)
                .background(Color(NSColor.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 16)
                .padding(.bottom, 88)
                .allowsHitTesting(true)
            }
        }
        .frame(width: 440, height: 440)
        .onAppear { Task { await loadPreview(useAI: false) } }
    }

    private func loadPreview(useAI: Bool) async {
        guard let fullName = await git.repoFullName(repoPath: repoPath) else {
            errorMessage = "Could not determine repo owner/name"
            isLoading = false
            return
        }
        summary = nil
        errorMessage = nil
        let base = await git.baseRefName(repoPath: repoPath) ?? "main"
        let cleanBase = base.hasPrefix("origin/") ? String(base.dropFirst(7)) : base

        guard api.authToken != nil else {
            errorMessage = "Not signed in"
            isLoading = false
            return
        }
        let result = await api.fetchPRPreview(
            repo: fullName, head: branchName,
            baseBranch: cleanBase, title: title, useAI: useAI
        )
        switch result {
        case .success(let decoded):
            summary = decoded.summary.isEmpty ? nil : decoded.summary
            if let err = decoded.summaryError, !err.isEmpty {
                errorMessage = err
            }
            if !decoded.suggestedBody.isEmpty {
                bodyText = decoded.suggestedBody
                suggestedBody = decoded.suggestedBody
            }
        case .failure(let message):
            errorMessage = message
        }
        isLoading = false
    }

    private func generateWithAI() async {
        isGeneratingAI = true
        errorMessage = nil
        await loadPreview(useAI: true)
        isGeneratingAI = false
    }

    private func createPR() async {
        isCreating = true
        do {
            let subsString = selectedUserIds.isEmpty ? nil : selectedUserIds.map(String.init).joined(separator: ",")
            let result = try await git.createPR(
                repoPath: repoPath, branchName: branchName,
                backendUrl: backendUrl, token: token ?? "",
                overrideTitle: title, overrideBody: bodyText, subscribers: subsString
            )
            onComplete(result.url)
        } catch {
            errorMessage = (error as? GitError)?.localizedDescription ?? error.localizedDescription
        }
        isCreating = false
    }
    
    private func loadAvailableUsers() async {
        isLoadingUsers = true
        guard api.authToken != nil else { return }

        let result = await api.fetchAvailableUsers()
        let fetched = (try? result.get()) ?? []
        await MainActor.run {
            self.availableUsers = fetched.filter { $0.gitHubId != gitHubId }
        }
        isLoadingUsers = false
    }
}

struct SubscriberPickerView: View {
    let availableUsers: [ApiAvailableUser]
    @Binding var selectedIds: Set<Int64>
    let onDone: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Subscribers")
                    .font(DS.Font.small.medium())
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
            }
            .padding(DS.Spacing.md)
            
            Divider()
            
            if availableUsers.filter({ !selectedIds.contains($0.gitHubId) }).isEmpty {
                VStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "person.2")
                        .font(.title2)
                        .foregroundStyle(DS.Color.textTertiary)
                    Text("No other users available")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(DS.Spacing.xl)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(availableUsers.filter { !selectedIds.contains($0.gitHubId) }) { user in
                            Button {
                                selectedIds.insert(user.gitHubId)
                            } label: {
                                HStack(spacing: DS.Spacing.md) {
                                    Image(systemName: selectedIds.contains(user.gitHubId) ? "checkmark.square.fill" : "square")
                                        .font(DS.Font.small)
                                        .foregroundStyle(selectedIds.contains(user.gitHubId) ? DS.Color.accent : DS.Color.textTertiary)
                                    
                                    if let avatarUrl = user.avatarUrl, !avatarUrl.isEmpty {
                                        AsyncImage(url: URL(string: avatarUrl)) { img in
                                            img.resizable()
                                        } placeholder: {
                                            Image(systemName: "person.circle.fill")
                                                .foregroundStyle(DS.Color.textTertiary)
                                        }
                                        .frame(width: 22, height: 22)
                                        .clipShape(Circle())
                                    } else {
                                        Image(systemName: "person.circle.fill")
                                            .font(DS.Font.body)
                                            .foregroundStyle(DS.Color.textTertiary)
                                            .frame(width: 22, height: 22)
                                    }
                                    
                                    Text("@\(user.login)")
                                        .font(DS.Font.body)
                                        .foregroundStyle(selectedIds.contains(user.gitHubId) ? DS.Color.textPrimary : DS.Color.textSecondary)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, DS.Spacing.xxl)
                                .padding(.vertical, DS.Spacing.lg)
                                .background(
                                    selectedIds.contains(user.gitHubId) ? DS.Color.accent.opacity(0.08) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: DS.Radius.sm)
                                )
                            }
                            .buttonStyle(.plain)
                            .cursor(.pointingHand)
                            Divider()
                        }
                    }
                }
            }
            
            Divider()
            
            HStack(spacing: DS.Spacing.sm) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(DS.Font.small)
                    .foregroundStyle(DS.Color.textSecondary)
                    .cursor(.pointingHand)
                solidButton("Add Selected", color: DS.Color.accent, disabled: selectedIds.isEmpty) {
                    onDone()
                }
            }
            .padding(DS.Spacing.md)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(width: 220)
    }
}
