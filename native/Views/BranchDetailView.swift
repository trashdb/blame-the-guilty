import SwiftUI

struct BranchDetailView: View {
    let info: BranchInfo
    let gitHubId: Int64
    let backendUrl: String
    var onCheckout: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var deleting = false
    @State private var checkingOut = false
    @State private var checkoutSuccess = false
    @State private var deleteError: String?
    @State private var showCreatePR = false
    @State private var showCreateBranch = false
    @State private var newBranchName = ""
    @State private var creatingBranch = false
    @State private var createBranchError: String?
    @State private var createBranchSuccess = false
    private let git = GitService()

    var body: some View {
        if showCreatePR {
            CreatePRPreviewView(
                repoPath: info.repoPath, branchName: info.name,
                backendUrl: backendUrl, gitHubId: gitHubId,
                onComplete: { url in
                    dismiss()
                    NSWorkspace.shared.open(url)
                },
                onCancel: { showCreatePR = false }
            )
            .frame(width: 440, height: 420)
        } else {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text(info.name)
                        .font(DS.Font.mono(13))
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    HStack(spacing: DS.Spacing.sm) {
                        Circle()
                            .fill(info.isLocal ? .green : (info.isMerged ? .green : .orange))
                            .frame(width: 6, height: 6)
                        Text(info.isLocal
                             ? (info.isCurrent ? "current branch" : "local branch")
                             : (info.isMerged ? "merged" : "unmerged"))
                            .font(DS.Font.small)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }

                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "folder")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                    Text(info.repoName)
                        .font(DS.Font.mono(11))
                        .foregroundStyle(DS.Color.textSecondary)
                }

                if let ticket = info.ticketNumber {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "link")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.accent)
                        Text(ticket)
                            .font(DS.Font.mono(11).medium())
                            .foregroundStyle(DS.Color.accent)
                        if let url = info.jiraUrl {
                            actionButton("Open", color: .blue) {
                                dismiss()
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }

                if let error = deleteError {
                    Text(error)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.destructive)
                }

                if showCreateBranch {
                    VStack(spacing: DS.Spacing.sm) {
                        styledTextField("New branch name", text: $newBranchName, help: "Create a new branch from \"\(info.name)\"")
                            .frame(maxWidth: .infinity)

                        if let error = createBranchError {
                            Text(error)
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.destructive)
                        }

                        HStack(spacing: DS.Spacing.md) {
                            actionButton("Cancel", color: DS.Color.textSecondary) {
                                withAnimation(DS.Animation.default) {
                                    showCreateBranch = false
                                    createBranchError = nil
                                    newBranchName = ""
                                }
                            }
                            solidButton("Create", color: DS.Color.accent, disabled: newBranchName.trimmingCharacters(in: .whitespaces).isEmpty || creatingBranch) {
                                Task { await doCreateBranch() }
                            }
                            if creatingBranch {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 12)
                            }
                            if createBranchSuccess {
                                Text("✓ Created")
                                    .font(DS.Font.small.medium())
                                    .foregroundStyle(DS.Color.success)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    Divider()
                }

                Divider()

                HStack(spacing: DS.Spacing.lg) {
                    if info.isLocal {
                        actionButton("Create PR", color: .green) {
                            showCreatePR = true
                        }
                        actionButton("Branch from here", color: .blue) {
                            withAnimation(DS.Animation.default) {
                                showCreateBranch = true
                                createBranchSuccess = false
                                createBranchError = nil
                                newBranchName = ""
                            }
                        }
                    }

                    if info.isLocal && !info.isCurrent && !checkoutSuccess {
                        actionButton(checkingOut ? "Checking out…" : "Checkout", color: .blue) {
                            Task { await doCheckout() }
                        }
                        .disabled(checkingOut)
                    }

                    if checkoutSuccess {
                        Text("✓ Checked out")
                            .font(DS.Font.small.medium())
                            .foregroundStyle(DS.Color.success)
                    }

                    if info.isLocal && !info.isCurrent && !info.isDefault {
                        actionButton("Delete", color: .red) {
                            Task { await doDelete() }
                        }
                        .disabled(deleting)
                    }

                    if !info.isLocal && !info.isDefault && info.isMerged {
                        actionButton("Delete Remote", color: .red) {
                            Task { await doDeleteRemote() }
                        }
                        .disabled(deleting)
                    }

                    if checkingOut || deleting {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12)
                    }
                }

                Spacer()
            }
            .padding(DS.Spacing.xxl)
            .frame(width: 320, height: showCreateBranch ? 300 : 220)
            .animation(DS.Animation.default, value: showCreateBranch)
        }
    }

    private func doCreateBranch() async {
        creatingBranch = true
        createBranchError = nil
        do {
            try await git.createBranch(repoPath: info.repoPath, from: info.name, newName: newBranchName.trimmingCharacters(in: .whitespaces))
            createBranchSuccess = true
            try await git.checkoutBranch(repoPath: info.repoPath, name: newBranchName.trimmingCharacters(in: .whitespaces))
            openRider()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                dismiss()
            }
        } catch {
            createBranchError = (error as? GitService.GitError)?.localizedDescription ?? error.localizedDescription
        }
        creatingBranch = false
    }

    private func doCheckout() async {
        checkingOut = true
        do {
            try await git.checkoutBranch(repoPath: info.repoPath, name: info.name)
            _ = await git.pullCurrentBranch(repoPath: info.repoPath)
            openRider()
            checkoutSuccess = true
            await MainActor.run { onCheckout?() }
        } catch {}
        checkingOut = false
    }

    private func doDelete() async {
        deleting = true
        deleteError = nil
        do {
            try await git.deleteLocalBranch(repoPath: info.repoPath, name: info.name)
        } catch {
            deleteError = (error as? GitService.GitError)?.localizedDescription ?? error.localizedDescription
        }
        deleting = false
    }

    private func doDeleteRemote() async {
        deleting = true
        deleteError = nil
        do {
            try await git.deleteRemoteBranch(repoPath: info.repoPath, name: info.name)
        } catch {
            deleteError = (error as? GitService.GitError)?.localizedDescription ?? error.localizedDescription
        }
        deleting = false
    }

    private func openRider() {
        let repoURL = URL(fileURLWithPath: info.repoPath)
        let repoName = repoURL.lastPathComponent
        let file = solutionFile(named: repoName, in: repoURL)
            ?? findSolutionFile(in: repoURL, extension: "slnx")
            ?? findSolutionFile(in: repoURL, extension: "sln")
        IDEOpener.openSolution(repoPath: info.repoPath) { _ in file?.path }
    }

    private func solutionFile(named name: String, in dir: URL) -> URL? {
        let candidates = ["\(name).slnx", "\(name).sln"]
        for candidate in candidates {
            let url = dir.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func findSolutionFile(in dir: URL, extension ext: String = "slnx") -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else { return nil }
        while let item = enumerator.nextObject() as? URL {
            if item.pathExtension == ext { return item }
            if item.pathComponents.count - dir.pathComponents.count > 3 {
                enumerator.skipDescendants()
            }
        }
        return nil
    }
}
