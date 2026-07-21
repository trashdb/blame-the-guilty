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
    @State private var showDeleteConfirmation = false
    @State private var checkingOutBranch: (repo: ScannedRepo, name: String)?
    @State private var pullingBranch: (repoId: String, name: String)?
    @State private var selectedBranchInfo: BranchInfo?
    @AppStorage("favoriteRepo") private var favoriteRepo = TeamDefaults.favoriteRepo
    @AppStorage("workspacePath") private var workspacePath = TeamDefaults.workspacePath

    private let git = GitService()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Header
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "arrow.triangle.branch")
                    .font(DS.Font.small)
                    .foregroundStyle(DS.Color.success)
                Text("Branches")
                    .font(DS.Font.section)
                    .foregroundStyle(DS.Color.success)
                Spacer()
                Picker("", selection: $selectedTab) {
                    Text("Local").tag(0)
                    Text("Remote").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .cursor(.pointingHand)
                Group {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Button {
                            Task { await scan() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(DS.Font.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Refresh branches")
                        .cursor(.pointingHand)
                    }
                }
                .frame(width: 22, height: 22)
            }

            if let error {
                Text(error)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.destructive)
                    .transition(.opacity)
            }

            if repos.isEmpty && !isLoading {
                VStack(spacing: DS.Spacing.sm) {
                    Text("No git repos found in workspace")
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.textSecondary)
                    Text("Change the workspace path in Settings")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
                .padding(.vertical, DS.Spacing.sm)
                .transition(.opacity)
            }

            ScrollView {
                LazyVStack(spacing: DS.Spacing.xs) {
                    ForEach(repos) { repo in
                        repoRow(repo)
                    }
                }
                .animation(DS.Animation.default, value: repos.count)
            }
            .frame(height: 180)
        }
        .animation(DS.Animation.default, value: showDeleteConfirmation)
        .overlay(alignment: .center) {
            if showDeleteConfirmation {
                deleteConfirmationOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .background {
            Color.clear
                .popover(item: $selectedBranchInfo) { info in
                    BranchDetailView(info: info, gitHubId: gitHubId, backendUrl: backendUrl, onCheckout: { Task { await scan() } })
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
                .animation(DS.Animation.popover, value: selectedBranchInfo != nil)
        }
        .animation(DS.Animation.default, value: isLoading)
        .animation(DS.Animation.default, value: error != nil)
        .onAppear { if repos.isEmpty { Task { await scan() } } }
    }

    @ViewBuilder
    private var deleteConfirmationOverlay: some View {
        ZStack {
            DS.Color.textPrimary.opacity(0.3)
                .ignoresSafeArea()
            VStack(spacing: DS.Spacing.xl) {
                let isRemote = remoteBranchToDelete != nil
                Text(isRemote
                     ? "Delete remote branch \"\(remoteBranchToDelete!.branch.name)\"?"
                     : "Delete branch \"\(branchToDelete!.branch.name)\"?")
                    .font(DS.Font.title)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(isRemote
                     ? "This will run `git push origin --delete` on the remote."
                     : "This will run `git branch -D` locally. Unmerged changes will be lost.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: DS.Spacing.xl) {
                    actionButton("Cancel", color: DS.Color.textSecondary) {
                        branchToDelete = nil
                        remoteBranchToDelete = nil
                        showDeleteConfirmation = false
                    }
                    solidButton("Delete", color: DS.Color.destructive) {
                        if let r = branchToDelete?.repo, let b = branchToDelete?.branch {
                            Task { await deleteBranch(repo: r, branch: b) }
                        } else if let r = remoteBranchToDelete?.repo, let b = remoteBranchToDelete?.branch {
                            Task { await deleteRemoteBranch(repo: r, branch: b) }
                        }
                        branchToDelete = nil
                        remoteBranchToDelete = nil
                        showDeleteConfirmation = false
                    }
                }
            }
            .padding(DS.Spacing.xxl)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl)
                    .stroke(DS.Color.divider, lineWidth: 1)
            )
            .padding(.horizontal, DS.Spacing.xxl)
        }
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
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: repo.isExpanded ? "chevron.down" : "chevron.right")
                        .font(DS.Font.micro)
                        .foregroundStyle(DS.Color.textTertiary)
                    Image(systemName: "folder")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.success)
                    if GitService.repoName(from: repo.path) == favoriteRepo {
                        Image(systemName: "star.fill")
                            .font(DS.Font.micro)
                            .foregroundStyle(DS.Color.statusYellow)
                    }
                    Text(GitService.repoName(from: repo.path))
                        .font(DS.Font.caption.medium())
                        .foregroundStyle(DS.Color.textPrimary)
                    Spacer()
                    Text("\(count)")
                        .font(DS.Font.tiny)
                        .foregroundStyle(DS.Color.textTertiary)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Color.rowBackground, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
            }
            .buttonStyle(.plain)
            .hoverEffect(cornerRadius: DS.Radius.sm)
            .cursor(.pointingHand)

            Group {
                if repo.isExpanded {
                    if let err = repo.error {
                        Text(err)
                            .font(DS.Font.tiny)
                            .foregroundStyle(DS.Color.destructive)
                            .padding(.leading, 18)
                            .transition(.opacity)
                    }

                    if selectedTab == 0 {
                        localBranchList(repo)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        remoteBranchList(repo)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .animation(DS.Animation.default, value: repo.isExpanded)
        }
    }

    @ViewBuilder
    private func localBranchList(_ repo: ScannedRepo) -> some View {
        ForEach(repo.branches) { branch in
            HStack(spacing: DS.Spacing.sm) {
                Button {
                    selectedBranchInfo = BranchInfo(
                        name: branch.name, repoPath: repo.path,
                        repoName: GitService.repoName(from: repo.path),
                        isCurrent: branch.isCurrent, isLocal: true,
                        isMerged: false,
                        isDefault: isDefaultBranch(branch.name))
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(branch.isCurrent ? "*" : " ")
                            .font(DS.Font.mono(10).bold())
                            .foregroundStyle(DS.Color.success)
                            .frame(width: 8)
                        Text(branch.name)
                            .font(DS.Font.mono(10))
                            .foregroundStyle(branch.isCurrent ? DS.Color.success : DS.Color.textSecondary)
                            .lineLimit(1)
                        if branch.isCurrent {
                            Text("(current)")
                                .font(DS.Font.micro)
                                .foregroundStyle(DS.Color.textTertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)
                .help("Details for \"\(branch.name)\"")
                .frame(maxWidth: .infinity, alignment: .leading)
                if !branch.isCurrent && !isDefaultBranch(branch.name) {
                    Button {
                        Task { await pullBranch(repo: repo, name: branch.name) }
                    } label: {
                        if pullingBranch?.repoId == repo.id && pullingBranch?.name == branch.name {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(DS.Font.micro)
                                .foregroundStyle(DS.Color.textTertiary)
                                .padding(3)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Pull \"\(branch.name)\" (fetch + rebase)")
                    .cursor(.pointingHand)
                    .disabled(pullingBranch?.repoId == repo.id && pullingBranch?.name == branch.name)
                    Button {
                        branchToDelete = (repo, branch)
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(DS.Font.micro)
                            .foregroundStyle(DS.Color.destructive.opacity(0.7))
                            .padding(3)
                            .background(DS.Color.destructive.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .help("Delete \"\(branch.name)\"")
                    .cursor(.pointingHand)
                }
            }
            .hoverEffect(cornerRadius: DS.Radius.sm)
            .padding(.leading, 18)
            .padding(.trailing, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
        }
    }

    @ViewBuilder
    private func remoteBranchList(_ repo: ScannedRepo) -> some View {
        ForEach(repo.remoteBranches) { branch in
            HStack(spacing: DS.Spacing.sm) {
                Circle()
                    .fill(branch.isMerged ? DS.Color.success : DS.Color.warning)
                    .frame(width: 6, height: 6)

                Button {
                    let info = BranchInfo(
                        name: branch.name, repoPath: repo.path,
                        repoName: GitService.repoName(from: repo.path),
                        isCurrent: false, isLocal: false,
                        isMerged: branch.isMerged,
                        isDefault: isDefaultBranch(branch.name))
                    selectedBranchInfo = nil
                    DispatchQueue.main.async {
                        selectedBranchInfo = info
                    }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(branch.name)
                            .font(DS.Font.mono(10))
                            .foregroundStyle(DS.Color.textSecondary)
                            .lineLimit(1)
                        Text(branch.isMerged ? "merged" : "unmerged")
                            .font(DS.Font.micro)
                            .foregroundStyle(branch.isMerged ? DS.Color.success : DS.Color.warning)
                    }
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)
                .help("Details for \"\(branch.name)\"")
                .frame(maxWidth: .infinity, alignment: .leading)
                if isDefaultBranch(branch.name) {
                    Text("protected")
                        .font(DS.Font.micro)
                        .foregroundStyle(DS.Color.textTertiary)
                } else {
                    Button {
                        remoteBranchToDelete = (repo, branch)
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(DS.Font.micro)
                            .foregroundStyle(branch.isMerged ? DS.Color.destructive.opacity(0.7) : DS.Color.textTertiary.opacity(0.3))
                            .padding(3)
                            .background((branch.isMerged ? DS.Color.destructive : DS.Color.textTertiary).opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .help(branch.isMerged ? "Delete \"\(branch.name)\" (safe — merged)" : "Not merged yet — cannot delete")
                    .cursor(.pointingHand)
                    .disabled(!branch.isMerged)
                }
            }
            .hoverEffect(cornerRadius: DS.Radius.sm)
            .padding(.leading, 18)
            .padding(.trailing, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
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
        Task { [paths] in
            for p in paths {
                await git.fetchRepo(repoPath: p)
            }
        }
    }

    private func checkoutBranch(repo: ScannedRepo, name: String) async {
        await MainActor.run { checkingOutBranch = (repo, name) }
        do {
            try await git.checkoutBranch(repoPath: repo.path, name: name)
            if case .conflict = await git.pullCurrentBranch(repoPath: repo.path) {
                await openRider(repo.path)
            }
            let branches = try await git.listMyBranches(repoPath: repo.path)
            await MainActor.run {
                if let ri = repos.firstIndex(where: { $0.id == repo.id }) {
                    repos[ri].branches = branches.map { GitBranch(name: $0.name, isCurrent: $0.isCurrent) }
                }
                checkingOutBranch = nil
            }
        } catch {
            await MainActor.run { checkingOutBranch = nil }
        }
    }

    @MainActor
    private func openRider(_ repoPath: String) {
        IDEOpener.openRepo(repoPath: repoPath)
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

    private func pullBranch(repo: ScannedRepo, name: String) async {
        let key = (repo.id, name)
        await MainActor.run { pullingBranch = key }
        do {
            try await git.pullBranch(repoPath: repo.path, name: name)
            let branches = try await git.listMyBranches(repoPath: repo.path)
            await MainActor.run {
                if let ri = repos.firstIndex(where: { $0.id == repo.id }) {
                    repos[ri].branches = branches.map { GitBranch(name: $0.name, isCurrent: $0.isCurrent) }
                }
                if pullingBranch?.repoId == repo.id && pullingBranch?.name == name {
                    pullingBranch = nil
                }
            }
        } catch {
            await MainActor.run {
                if let ri = repos.firstIndex(where: { $0.id == repo.id }) {
                    repos[ri].error = "Failed to pull \"\(name)\": \((error as? GitService.GitError)?.localizedDescription ?? error.localizedDescription)"
                }
                pullingBranch = nil
            }
        }
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
