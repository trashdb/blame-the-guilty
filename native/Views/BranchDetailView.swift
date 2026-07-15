import SwiftUI

struct BranchDetailView: View {
    let info: BranchInfo
    let gitHubId: Int64
    let backendUrl: String
    var onCheckout: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var deleting = false
    @State private var checkingOut = false
    @State private var deleteError: String?
    @State private var showCreatePR = false
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
            .frame(width: 460, height: 420)
        } else {
            VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(info.name)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(white: 0.9))
                    .lineLimit(2)
                    .textSelection(.enabled)

                HStack(spacing: 4) {
                    Circle()
                        .fill(info.isLocal ? .green : (info.isMerged ? .green : .orange))
                        .frame(width: 6, height: 6)
                    Text(info.isLocal
                         ? (info.isCurrent ? "current branch" : "local branch")
                         : (info.isMerged ? "merged" : "unmerged"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(info.repoName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let ticket = info.ticketNumber {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 9))
                        .foregroundStyle(.blue)
                    Text(ticket)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.blue)
                    if let url = info.jiraUrl {
                        Button("Open") {
                            dismiss()
                            NSWorkspace.shared.open(url)
                        }
                        .font(.system(size: 9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        .buttonStyle(.plain)
                        .cursor(.pointingHand)
                    }
                }
            }

            if let error = deleteError {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
            }

            Divider()

            HStack(spacing: 8) {
                if info.isLocal {
                    actionButton("Create PR", color: .green) {
                        showCreatePR = true
                    }
                }

                if info.isLocal && !info.isCurrent {
                    actionButton("Checkout", color: .blue) {
                        Task { await doCheckout() }
                    }
                    .disabled(checkingOut)
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
        .padding(16)
        .frame(width: 300, height: 220)
        }
    }

    private func actionButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }

    private func doCheckout() async {
        checkingOut = true
        do {
            try await git.checkoutBranch(repoPath: info.repoPath, name: info.name)
            _ = await git.pullCurrentBranch(repoPath: info.repoPath)
            openRider()
            dismiss()
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
            ?? repoURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["open", "-a", "Rider", file.path]
        try? task.run()
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

