import SwiftUI

struct ContentView: View {
    @ObservedObject var signalR: SignalRService

    @State private var keepSignedIn = true
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

                if signalR.isLoggedIn {
                    LoggedInCardView(username: signalR.username, avatarUrl: signalR.avatarUrl, onSignOut: logout)
                    KeepSignedInToggleView(isOn: $keepSignedIn)
                } else {
                    SignInCardView(isLoading: isLoading, loginError: loginError, onSignIn: login)
                }

                if signalR.isLoggedIn {
                    ActivePRsView(prs: signalR.activePRs)
                    Divider()
                }
                
                if signalR.isLoggedIn {
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

                if signalR.isLoggedIn {
                    Button {
                        WorkflowHistoryPanelManager.shared.show(signalR: signalR, gitHubId: signalR.userGitHubId)
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
                
                
                
                if signalR.isLoggedIn, signalR.runningWorkflows.count > 0 {
                    Button {
                        WorkflowHistoryPanelManager.shared.show(signalR: signalR, gitHubId: signalR.userGitHubId)
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
        .onAppear { signalR.restoreSession() }
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
