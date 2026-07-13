import SwiftUI

struct LocalBranchesView: View {
    let gitHubId: Int64
    let backendUrl: String

    @State private var repos: [ScannedRepo] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedTab = 0
    @State private var branchToDelete: (repo: ScannedRepo, branch: GitBranch)?
    @State private var remoteBranchToDelete: (repo: ScannedRepo, branch: RemoteBranch)?

    @AppStorage("workspacePath") private var workspacePath: String = {
        NSHomeDirectory() + "/Desktop/dev"
    }()

    private let git = GitService()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                Text("Branches")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                Spacer()
                Picker("", selection: $selectedTab) {
                    Text("Local").tag(0)
                    Text("Remote").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Button {
                        Task { await scan() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help("Refresh branches")
                    .cursor(.pointingHand)
                }
            }

            if let error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }

            if repos.isEmpty && !isLoading {
                VStack(spacing: 4) {
                    Text("No git repos found in workspace")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("Change the workspace path in Settings")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            ScrollView {
                VStack(spacing: 3) {
                    ForEach(repos) { repo in
                        repoRow(repo)
                    }
                }
            }
            .frame(height: 200)
        }
        .onAppear { Task { await scan() } }
        .confirmationDialog(
            branchToDelete != nil
                ? "Delete branch \"\(branchToDelete!.branch.name)\"?"
                : "Delete remote branch \"\(remoteBranchToDelete?.branch.name ?? "")\"?",
            isPresented: .init(
                get: { branchToDelete != nil || remoteBranchToDelete != nil },
                set: { if !$0 { branchToDelete = nil; remoteBranchToDelete = nil } }
            ),
            actions: {
                Button("Delete", role: .destructive) {
                    if let r = branchToDelete?.repo, let b = branchToDelete?.branch {
                        Task { await deleteBranch(repo: r, branch: b) }
                        branchToDelete = nil
                    } else if let r = remoteBranchToDelete?.repo, let b = remoteBranchToDelete?.branch {
                        Task { await deleteRemoteBranch(repo: r, branch: b) }
                        remoteBranchToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { branchToDelete = nil; remoteBranchToDelete = nil }
            },
            message: {
                if branchToDelete != nil {
                    Text("This will run `git branch -D` locally. Unmerged changes will be lost.")
                } else {
                    Text("This will run `git push origin --delete` on the remote. The branch will be permanently removed.")
                }
            }
        )
    }

    @ViewBuilder
    private func repoRow(_ repo: ScannedRepo) -> some View {
        let count = selectedTab == 0 ? repo.branches.count : repo.remoteBranches.count
        VStack(spacing: 0) {
            Button {
                if let idx = repos.firstIndex(where: { $0.id == repo.id }) {
                    repos[idx].isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: repo.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text(GitService.repoName(from: repo.path))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(white: 0.85))
                    Spacer()
                    Text("\(count)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)

            if repo.isExpanded {
                if let err = repo.error {
                    Text(err)
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                        .padding(.leading, 16)
                }

                if selectedTab == 0 {
                    localBranchList(repo)
                } else {
                    remoteBranchList(repo)
                }
            }
        }
    }

    @ViewBuilder
    private func localBranchList(_ repo: ScannedRepo) -> some View {
        ForEach(repo.branches) { branch in
            HStack(spacing: 5) {
                if branch.isCurrent {
                    Text("*")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                        .frame(width: 8)
                } else {
                    Text(" ")
                        .frame(width: 8)
                }

                Text(branch.name)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(branch.isCurrent ? .green : Color(white: 0.75))
                    .lineLimit(1)

                if branch.isCurrent {
                    Text("(current)")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !branch.isCurrent && !isDefaultBranch(branch.name) {
                    Button {
                        branchToDelete = (repo, branch)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 8))
                            .foregroundStyle(.red.opacity(0.7))
                            .padding(3)
                            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                    .help("Delete \"\(branch.name)\"")
                    .cursor(.pointingHand)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func remoteBranchList(_ repo: ScannedRepo) -> some View {
        ForEach(repo.remoteBranches) { branch in
            HStack(spacing: 5) {
                Circle()
                    .fill(branch.isMerged ? .green : .orange)
                    .frame(width: 6, height: 6)

                Text(branch.name)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(white: 0.75))
                    .lineLimit(1)

                Text(branch.isMerged ? "merged" : "unmerged")
                    .font(.system(size: 8))
                    .foregroundStyle(branch.isMerged ? .green : .orange)

                Spacer()

                if isDefaultBranch(branch.name) {
                    Text("protected")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        remoteBranchToDelete = (repo, branch)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 8))
                            .foregroundStyle(branch.isMerged ? .red.opacity(0.7) : .gray.opacity(0.3))
                            .padding(3)
                            .background((branch.isMerged ? Color.red : Color.gray).opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                    .help(branch.isMerged ? "Delete \"\(branch.name)\" (safe — merged)" : "Not merged yet — cannot delete")
                    .cursor(.pointingHand)
                    .disabled(!branch.isMerged)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 2)
        }
    }

    private func scan() async {
        await MainActor.run { isLoading = true; error = nil }
        let expanded = (workspacePath as NSString).expandingTildeInPath
        let paths = GitService.discoverRepos(workspacePath: expanded)

        await withTaskGroup(of: (Int, ScannedRepo).self) { group in
            for (i, path) in paths.enumerated() {
                group.addTask(priority: .userInitiated) {
                    do {
                        await self.git.fetchRepo(repoPath: path)
                        let b = try await self.git.listMyBranches(repoPath: path)
                        let r = await self.git.listMyRemoteBranchesViaAPI(
                            repoPath: path, backendUrl: self.backendUrl, gitHubId: self.gitHubId
                        )
                        let repo = ScannedRepo(
                            path: path,
                            branches: b.map { GitBranch(name: $0.name, isCurrent: $0.isCurrent) },
                            remoteBranches: r.map { RemoteBranch(name: $0.name, isMerged: $0.isMerged) },
                            isExpanded: false
                        )
                        return (i, repo)
                    } catch {
                        let repo = ScannedRepo(
                            path: path, branches: [], remoteBranches: [], isExpanded: false,
                            error: "Error: \((error as? GitService.GitError)?.localizedDescription ?? error.localizedDescription)"
                        )
                        return (i, repo)
                    }
                }
            }
            var results: [(Int, ScannedRepo)] = []
            for await result in group {
                results.append(result)
            }
            let sorted = results.sorted { $0.0 < $1.0 }.map { $0.1 }
            await MainActor.run { repos = sorted; isLoading = false }
        }
    }

    private func deleteBranch(repo: ScannedRepo, branch: GitBranch) async {
        guard let ri = repos.firstIndex(where: { $0.id == repo.id }) else { return }
        do {
            try await git.deleteLocalBranch(repoPath: repo.path, name: branch.name)
            await MainActor.run { repos[ri].branches.removeAll { $0.id == branch.id } }
        } catch {
            await MainActor.run {
                repos[ri].error = "Failed to delete \"\(branch.name)\": \((error as? GitService.GitError)?.localizedDescription ?? error.localizedDescription)"
                repos[ri].isExpanded = true
            }
        }
    }

    private func isDefaultBranch(_ name: String) -> Bool {
        name == "main" || name == "master"
    }

    private func deleteRemoteBranch(repo: ScannedRepo, branch: RemoteBranch) async {
        guard let ri = repos.firstIndex(where: { $0.id == repo.id }) else { return }
        do {
            try await git.deleteRemoteBranch(repoPath: repo.path, name: branch.name)
            await MainActor.run { repos[ri].remoteBranches.removeAll { $0.id == branch.id } }
        } catch {
            await MainActor.run {
                repos[ri].error = "Failed to delete \"\(branch.name)\": \((error as? GitService.GitError)?.localizedDescription ?? error.localizedDescription)"
                repos[ri].isExpanded = true
            }
        }
    }
}
