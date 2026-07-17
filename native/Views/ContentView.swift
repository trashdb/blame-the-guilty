import Combine
import SwiftUI

struct ContentView: View {
    @ObservedObject var signalR: SignalRService

    @State private var keepSignedIn = true
    @State private var isLoading = false
    @State private var loginError: String?
    @State private var showQuickSearch = false
    @FocusState private var quickSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                // Header
                HStack(spacing: DS.Spacing.md) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13)).padding(.bottom, 2)
                    Text("Blame the Guilty")
                        .font(.system(size: 16, weight: .semibold))
                }

                Text("CI/CD notifications when a merged PR breaks the build.")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(2)

                Divider()

                if signalR.isLoggedIn {
                    LoggedInCardView(username: signalR.username, avatarUrl: signalR.avatarUrl, onSignOut: logout)
                    KeepSignedInToggleView(isOn: $keepSignedIn)
                } else {
                    SignInCardView(isLoading: isLoading, loginError: loginError, onSignIn: login)
                }

                if signalR.isLoggedIn {
                    ActivePRsView(prs: signalR.activePRs, gitHubId: signalR.userGitHubId)
                    Divider()
                }

                if signalR.isLoggedIn {
                    if let event = signalR.lastEvent {
                        LastNotificationCardView(event: event)
                    } else {
                        EmptyNotificationView()
                    }
                }

                if signalR.isLoggedIn {
                    Divider()
                    LocalBranchesView(gitHubId: signalR.userGitHubId, backendUrl: signalR.baseUrl)
                }
            }
            .foregroundStyle(DS.Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DS.Spacing.xl)
            .padding(.horizontal, DS.Spacing.xxl)

            Spacer(minLength: 0)

            Divider()

            // Toolbar
            HStack {
                if signalR.isLoggedIn {
                    toolbarButton(icon: "arrow.triangle.2.circlepath", help: "Full resync: workflows + PRs") {
                        Task {
                            let n = await signalR.syncActiveWorkflows(gitHubId: signalR.userGitHubId)
                            if n > 0 {
                                showNotification(
                                    title: "Workflows Synced",
                                    body: "\(n) new running workflow\(n == 1 ? "" : "s") found via GitHub API",
                                    subtitle: nil,
                                    actionURL: nil
                                )
                            }
                        }
                    }
                }

                toolbarButton(icon: "bell.fill", help: "Send Test Notification") {
                    showNotification(
                        title: "Blame the Guilty",
                        body: "Test notification from popover",
                        subtitle: "Works!",
                        actionURL: URL(string: "https://github.com")
                    )
                }

                if signalR.isLoggedIn {
                    toolbarButton(icon: "list.bullet.rectangle", help: "Workflow History") {
                        WorkflowHistoryPanelManager.shared.show(signalR: signalR, gitHubId: signalR.userGitHubId)
                    }

                    toolbarButton(icon: "antenna.radiowaves.left.and.right", help: "Webhook Event Log (debug)") {
                        WebhookLogPanelManager.shared.show(gitHubId: signalR.userGitHubId)
                    }

                    toolbarButton(icon: "tray.full", help: "See All PRs") {
                        let repo = UserDefaults.standard.string(forKey: "favoriteRepo") ?? TeamDefaults.favoriteRepo
                        if let u = URL(string: "https://github.com/easyjet-dev/\(repo)/pulls") {
                            NSWorkspace.shared.open(u)
                        }
                    }

                    toolbarButton(icon: "gearshape.fill", help: "Settings") {
                        let m = SettingsPanelManager.shared
                        m.gitHubId = signalR.userGitHubId
                        m.backendUrl = signalR.baseUrl
                        m.show()
                    }
                }

                if signalR.isLoggedIn, signalR.runningWorkflows.count > 0 {
                    Button {
                        WorkflowHistoryPanelManager.shared.show(signalR: signalR, gitHubId: signalR.userGitHubId)
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Circle()
                                .fill(.orange)
                                .frame(width: 7, height: 7)
                            Text("\(signalR.runningWorkflows.count) \(signalR.runningWorkflows.count == 1 ? "workflow" : "workflows") running")
                                .font(DS.Font.small.medium())
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.lg))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.lg)
                                .stroke(.orange.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                }

                Spacer()

                toolbarButton(icon: "trash.fill", help: "Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, DS.Spacing.xxl)
            .padding(.vertical, DS.Spacing.xl)
        }
        .frame(width: 400, height: 820, alignment: .top)
        .background(.regularMaterial)
        .onAppear {
            signalR.restoreSession()
            Task { await scanCurrentBranches() }
            setupQuickSearchShortcut()
        }
        .onChange(of: signalR.activePRs) { updateMenuBarBadge($0) }
        .overlay(QuickSearchView(
            isPresented: $showQuickSearch,
            actions: signalR.isLoggedIn ? quickSearchActions : [],
            signalR: signalR,
            gitHubId: signalR.userGitHubId,
            backendUrl: signalR.baseUrl
        ))
    }

    private var quickSearchActions: [QuickSearchAction] {
        var actions: [QuickSearchAction] = []

        let repo = UserDefaults.standard.string(forKey: "favoriteRepo") ?? TeamDefaults.favoriteRepo

        actions.append(QuickSearchAction(
            id: "jira-board", title: "Open Jira Board",
            subtitle: "Browse all tickets",
            icon: "link", category: .jira
        ) {
            let url = UserDefaults.standard.string(forKey: "jiraBoardViewUrl") ?? TeamDefaults.jiraBoardViewUrl
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        })

        let branches = MenuBarBadgeService.shared.currentBranches
        for branch in branches {
            actions.append(QuickSearchAction(
                id: "create-pr-\(branch.repoPath)-\(branch.name)",
                title: "Create PR from \(branch.name)",
                subtitle: "\(branch.repoName) → open PR preview",
                icon: "plus.circle", category: .branch
            ) {
                let info = BranchInfo(
                    name: branch.name, repoPath: branch.repoPath,
                    repoName: branch.repoName,
                    isCurrent: true, isLocal: true,
                    isMerged: false, isDefault: false
                )
                BranchDetailPanelManager.shared.show(
                    info: info,
                    gitHubId: self.signalR.userGitHubId,
                    backendUrl: self.signalR.baseUrl,
                    onCheckout: nil
                )
            })
            actions.append(QuickSearchAction(
                id: "open-ide-\(branch.repoPath)",
                title: "Open \(branch.repoName) in IDE",
                subtitle: branch.repoPath,
                icon: "chevron.left.forwardslash.chevron.right", category: .repo
            ) {
                IDEOpener.openRepo(repoPath: branch.repoPath)
            })
            if let ticket = branch.ticketNumber {
                actions.append(QuickSearchAction(
                    id: "jira-ticket-\(ticket)",
                    title: "Open Jira ticket \(ticket)",
                    subtitle: "\(branch.repoName) — current branch",
                    icon: "link", category: .jira
                ) {
                    let base = UserDefaults.standard.string(forKey: "jiraBoardUrl") ?? TeamDefaults.jiraBoardUrl
                    if let u = URL(string: "\(base)\(ticket)") {
                        NSWorkspace.shared.open(u)
                    }
                })
            }
        }
        if let fav = branches.first(where: { $0.repoName == repo }) {
            actions.append(QuickSearchAction(
                id: "checkout-main-\(fav.repoPath)",
                title: "Checkout main in \(fav.repoName)",
                subtitle: "Switch to main branch",
                icon: "arrow.triangle.branch", category: .branch
            ) {
                Task {
                    let git = GitService()
                    try? await git.checkoutBranch(repoPath: fav.repoPath, name: "main")
                    try? await git.pullCurrentBranch(repoPath: fav.repoPath)
                    await self.scanCurrentBranches()
                }
            })
        }

        return actions
    }

    private func setupQuickSearchShortcut() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "k" {
                if let window = NSApp.keyWindow, window.level == .floating || window == NSApp.keyWindow {
                    self.showQuickSearch.toggle()
                    return nil
                }
            }
            return event
        }
    }

    private func scanCurrentBranches() async {
        let path = UserDefaults.standard.string(forKey: "workspacePath") ?? TeamDefaults.workspacePath
        let branches = await GitService.scanCurrentBranches(workspacePath: path)
        await MainActor.run {
            MenuBarBadgeService.shared.currentBranches = branches
        }
    }

    private func updateMenuBarBadge(_ prs: [PullRequest]) {
        let badge = MenuBarBadgeService.shared
        badge.activePRCount = prs.count
        badge.failedPRCount = prs.filter { $0.ciStatus == "failed" || $0.conclusion == "failure" }.count
        badge.draftCount = prs.filter { $0.draft }.count
        badge.waitingCount = prs.filter { $0.ciStatus == "waiting" }.count
        badge.reviewCount = prs.filter { $0.ciStatus == "review" }.count
        badge.readyCount = prs.filter { $0.ciStatus == "ready" || $0.ciStatus == "" }.count
        badge.mergedCount = prs.filter { $0.isMerged }.count
        badge.runningWorkflowCount = signalR.runningWorkflows.count
    }

    private func login() {
        isLoading = true
        loginError = nil
        Task {
            do {
                try await signalR.login(keepSignedIn: keepSignedIn)
            } catch {
                await MainActor.run { loginError = "Login failed. Please try again." }
            }
            await MainActor.run { isLoading = false }
        }
    }

    private func logout() {
        signalR.logout()
        loginError = nil
    }
}

#Preview {
    ContentView(signalR: SignalRService(baseUrl: backendUrl))
}
