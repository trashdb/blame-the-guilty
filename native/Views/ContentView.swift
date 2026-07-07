import SwiftUI

struct ContentView: View {
    @ObservedObject var signalR: SignalRService

    @State private var isLoggedIn = false
    @State private var keepSignedIn = true
    @State private var username = ""
    @State private var gitHubId: Int64 = 0
    @State private var isLoading = false
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13)).padding(.bottom, 2)
                    Text("Blame the Guilty")
                        .font(.system(size: 16, weight: .semibold))
                }

                Text("CI/CD notifications when a merged PR breaks the build.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Divider()

                if isLoggedIn {
                    LoggedInCardView(username: username, onSignOut: logout)
                    KeepSignedInToggleView(isOn: $keepSignedIn)
                } else {
                    SignInCardView(isLoading: isLoading, loginError: loginError, onSignIn: login)
                }

                if isLoggedIn, !signalR.runningWorkflows.isEmpty {
                    RunningWorkflowsIndicatorView(
                        count: signalR.runningWorkflows.count,
                        onTap: { WorkflowHistoryPanelManager.shared.show(signalR: signalR, gitHubId: gitHubId) }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
                }

                if isLoggedIn, !signalR.activePRs.isEmpty {
                    ActivePRsView(prs: signalR.activePRs)
                    Divider()
                }

                if isLoggedIn {
                    if let event = signalR.lastEvent {
                        LastNotificationCardView(event: event)
                    } else {
                        EmptyNotificationView()
                    }
                }
            }
            .foregroundStyle(Color(white: 0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .padding(.horizontal, 16)

            Spacer(minLength: 0)

            Divider()

            HStack {
                Button {
                    openSettingsWindow()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Settings")
                .cursor(.pointingHand)

                Button {
                    WorkflowHistoryPanelManager.shared.show(signalR: signalR, gitHubId: gitHubId)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Workflow History")
                .cursor(.pointingHand)

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Quit")
                .cursor(.pointingHand)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .frame(width: 300, height: 600, alignment: .top)
        .background(.regularMaterial)
        .onAppear { autoConnectIfNeeded() }
    }

    private func login() {
        isLoading = true
        loginError = nil
        Task {
            do {
                let oauth = OAuthService()
                let result = try await oauth.startLogin(backendUrl: backendUrl)
                await MainActor.run {
                    gitHubId = result.id
                    username = result.username
                    isLoggedIn = true
                    signalR.connect(gitHubId: result.id, username: result.username)
                    if keepSignedIn {
                        KeychainService.save(gitHubId: result.id, username: result.username)
                    }
                }
            } catch {
                await MainActor.run { loginError = "Login failed. Please try again." }
            }
            await MainActor.run { isLoading = false }
        }
    }

    private func logout() {
        signalR.disconnect()
        KeychainService.delete()
        isLoggedIn = false
        username = ""
        gitHubId = 0
        loginError = nil
    }

    private func autoConnectIfNeeded() {
        guard !isLoggedIn, let session = KeychainService.load() else { return }
        gitHubId = session.gitHubId
        username = session.username
        isLoggedIn = true
        signalR.connect(gitHubId: session.gitHubId, username: session.username)
    }

    private func openSettingsWindow() {
        SettingsPanelManager.shared.show()
    }

}

final class SettingsPanelManager {
    static let shared = SettingsPanelManager()
    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let hostingController = NSHostingController(rootView: SettingsView())

            panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            panel?.contentViewController = hostingController
            panel?.title = "Settings"
            panel?.center()
            panel?.level = .floating
            panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel?.isReleasedWhenClosed = false
            panel?.backgroundColor = .clear
            panel?.isOpaque = false
            panel?.hasShadow = true
        }

        panel?.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

final class WorkflowHistoryPanelManager {
    static let shared = WorkflowHistoryPanelManager()
    private var panel: NSPanel?

    func show(signalR: SignalRService, gitHubId: Int64) {
        if panel == nil {
            let hostingController = NSHostingController(rootView: WorkflowHistoryView(signalR: signalR, gitHubId: gitHubId))

            panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            panel?.contentViewController = hostingController
            panel?.title = "Workflow History"
            panel?.center()
            panel?.level = .floating
            panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel?.isReleasedWhenClosed = false
            panel?.backgroundColor = .clear
            panel?.isOpaque = false
            panel?.hasShadow = true
        }

        panel?.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

struct EmptyNotificationView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("Last Notification")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text("There are no recent notifications")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct ActivePRsView: View {
    let prs: [PullRequest]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("Active PRs (\(prs.count))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
                Spacer()
            }

            ForEach(prs.prefix(5)) { pr in
                Button {
                    NSWorkspace.shared.open(pr.prUrl)
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pr.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(white: 0.85))
                                .lineLimit(1)
                            HStack(spacing: 0) {
                                Text(pr.repo).font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(" → ").font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(pr.baseBranch).font(.system(size: 10, design: .monospaced)).foregroundStyle(.blue)
                            }
                            .lineLimit(1)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.06), lineWidth: 1)
                )
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
    }
}

#Preview {
    ContentView(signalR: SignalRService(baseUrl: backendUrl))
}
