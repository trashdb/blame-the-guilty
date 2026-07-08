import SwiftUI

struct ContentView: View {
    @ObservedObject var signalR: SignalRService

    @State private var isLoggedIn = false
    @State private var keepSignedIn = true
    @State private var username = ""
    @State private var avatarUrl: String?
    @State private var gitHubId: Int64 = 0
    @State private var isLoading = false
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 10) {
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
                    LoggedInCardView(username: username, avatarUrl: avatarUrl, onSignOut: logout)
                    KeepSignedInToggleView(isOn: $keepSignedIn)
                } else {
                    SignInCardView(isLoading: isLoading, loginError: loginError, onSignIn: login)
                }

                if isLoggedIn, !signalR.activePRs.isEmpty {
                    ActivePRsView(prs: signalR.activePRs, workflows: signalR.recentWorkflows)
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
            .padding(.vertical, 10)
            .padding(.horizontal, 16)

            Spacer(minLength: 0)

            Divider()

            HStack {
                Button {
                    showNotification(
                        title: "Blame the Guilty",
                        body: "Test notification from popover",
                        subtitle: "Works!",
                        actionURL: URL(string: "https://github.com")
                    )
                } label: {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Send Test Notification")
                .cursor(.pointingHand)

                if isLoggedIn {
                    Button {
                        WorkflowHistoryPanelManager.shared.show(signalR: signalR, gitHubId: gitHubId)
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Workflow History")
                    .cursor(.pointingHand)
                }
                
                
                
                if isLoggedIn, signalR.runningWorkflows.count > 0 {
                    Button {
                        WorkflowHistoryPanelManager.shared.show(signalR: signalR, gitHubId: gitHubId)
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.orange)
                                .frame(width: 7, height: 7)
                            Text("\(signalR.runningWorkflows.count) \(signalR.runningWorkflows.count == 1 ? "workflow" : "workflows") running")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.orange.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                }

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
        .frame(width: 400, height: 630, alignment: .top)
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
                    avatarUrl = result.avatarUrl
                    isLoggedIn = true
                    signalR.connect(gitHubId: result.id, username: result.username)
                    if keepSignedIn {
                        KeychainService.save(gitHubId: result.id, username: result.username, avatarUrl: result.avatarUrl)
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
        avatarUrl = nil
        gitHubId = 0
        loginError = nil
    }

    private func autoConnectIfNeeded() {
        guard !isLoggedIn, let session = KeychainService.load() else { return }
        gitHubId = session.gitHubId
        username = session.username
        avatarUrl = session.avatarUrl
        isLoggedIn = true
        signalR.connect(gitHubId: session.gitHubId, username: session.username)
    }

}

#Preview {
    ContentView(signalR: SignalRService(baseUrl: backendUrl))
}
