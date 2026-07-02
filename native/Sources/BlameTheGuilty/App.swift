import SwiftUI
import ServiceManagement

private let BackendUrl = "https://moonlike-silenced-sprung.ngrok-free.dev"

@main
struct BlameTheGuiltyApp: App {
    @StateObject private var signalR = SignalRService(baseUrl: BackendUrl)
    @State private var isLoggedIn = false
    @State private var username   = ""
    @State private var gitHubId: Int64 = 0
    @State private var loginError: String?
    @State private var isLoading  = false

    init() {
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
        // setupNotifications() is called in onAppear (after app is fully active)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                signalR: signalR,
                isLoggedIn: isLoggedIn,
                username: username,
                loginError: loginError,
                isLoading: isLoading,
                onLogin: login,
                onLogout: logout
            )
        } label: {
            Image(systemName: "exclamationmark.octagon.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(menuBarIconColor)
                .onAppear {
                    setupNotifications()   // request permission once app is fully active
                    autoConnectIfNeeded()
                }
        }
    }

    // MARK: - Menu bar icon colour

    private var menuBarIconColor: Color {
        guard isLoggedIn else { return .secondary }
        return signalR.isConnected ? .red : .orange
    }

    // MARK: - Auto-connect from Keychain on startup

    private func autoConnectIfNeeded() {
        guard !isLoggedIn, let session = KeychainService.load() else { return }
        gitHubId   = session.gitHubId
        username   = session.username
        isLoggedIn = true
        signalR.connect(gitHubId: session.gitHubId)
    }

    // MARK: - Login

    private func login() {
        isLoading  = true
        loginError = nil
        Task {
            do {
                let oauth  = OAuthService()
                let result = try await oauth.startLogin(backendUrl: BackendUrl)
                await MainActor.run {
                    gitHubId   = result.id
                    username   = result.username
                    isLoggedIn = true
                    // Persist so the user never has to log in again
                    KeychainService.save(gitHubId: result.id, username: result.username)
                }
                signalR.connect(gitHubId: result.id)
            } catch {
                await MainActor.run { loginError = "Login failed. Please try again." }
            }
            await MainActor.run { isLoading = false }
        }
    }

    // MARK: - Logout

    private func logout() {
        KeychainService.delete()
        signalR.disconnect()
        isLoggedIn = false
        username   = ""
        gitHubId   = 0
        loginError = nil
    }
}

// MARK: - Menu bar popup content

struct MenuBarContent: View {
    @ObservedObject var signalR: SignalRService
    let isLoggedIn:  Bool
    let username:    String
    let loginError:  String?
    let isLoading:   Bool
    let onLogin:     () -> Void
    let onLogout:    () -> Void

    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)

    private let crimsonGradient = LinearGradient(
        colors: [Color(red: 0.82, green: 0.10, blue: 0.10),
                 Color(red: 0.52, green: 0.04, blue: 0.04)],
        startPoint: .leading, endPoint: .trailing
    )

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            statusSection
            if isLoggedIn, let event = signalR.lastEvent {
                Divider()
                lastFailureSection(event)
            }
            if !isLoggedIn {
                Divider()
                loginSection
            }
            Divider()
            settingsSection
            Divider()
            quitButton
        }
        .frame(width: 262)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text("Blame the Guilty")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text("CI/CD Punishment System")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.70))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(crimsonGradient)
    }

    // MARK: Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            connectionRow
            if isLoggedIn { userRow }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var connectionRow: some View {
        HStack(spacing: 8) {
            if isLoading && !isLoggedIn {
                ProgressView().scaleEffect(0.65).frame(width: 8, height: 8)
                Text("Authenticating...")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            } else if isLoggedIn {
                Circle()
                    .fill(signalR.isConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(signalR.isConnected ? "Connected & watching" : "Reconnecting...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(signalR.isConnected ? .green : .orange)
            } else {
                Circle().fill(Color.secondary.opacity(0.40)).frame(width: 8, height: 8)
                Text("Not signed in").font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var userRow: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 22, height: 22)
                Image(systemName: "person.fill").font(.system(size: 10)).foregroundColor(.accentColor)
            }
            Text("@\(username)").font(.system(size: 12, weight: .medium))
            Spacer()
        }
    }

    // MARK: Last failure

    @ViewBuilder
    private func lastFailureSection(_ event: PunishmentEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 11)).foregroundColor(.red)
                Text("Last Failure")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.red)
                Spacer()
                Text(event.date, style: .relative)
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(event.culprit)").font(.system(size: 12, weight: .medium))
                Text(event.repo).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                Text("Run #\(event.runId)").font(.system(size: 11)).foregroundColor(.secondary)
            }
            if let url = event.workflowURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                        Text("Open Workflow in Browser").font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.78, green: 0.10, blue: 0.10))
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Login

    @ViewBuilder
    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = loginError {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle.fill").font(.caption2).foregroundColor(.red)
                    Text(error).font(.caption).foregroundColor(.red).lineLimit(2)
                }
                .padding(.horizontal, 14).padding(.top, 8)
            }
            Button(action: onLogin) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                    Text(isLoading ? "Connecting..." : "Sign in with GitHub").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isLoading)
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.78, green: 0.10, blue: 0.10))
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    // MARK: Settings (launch at login + logout)

    private var settingsSection: some View {
        VStack(spacing: 0) {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .font(.system(size: 12))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .onChange(of: launchAtLogin) { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else       { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = (SMAppService.mainApp.status == .enabled)
                    }
                }

            Button {
                sendTestNotification()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bell.badge")
                    Text("Send Test Notification")
                }
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 4)

            if isLoggedIn {
                Button(role: .destructive, action: onLogout) {
                    HStack(spacing: 5) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Log out @\(username)")
                    }
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
        }
    }

    private func sendTestNotification() {
        showNotification(
            title: "⚠️ Blame the Guilty",
            body: "Test — alvaro merged a failing workflow in myorg/backend",
            subtitle: "Run #999",
            actionURL: URL(string: "https://github.com")
        )
    }

    // MARK: Quit

    private var quitButton: some View {
        Button("Quit Blame the Guilty") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }
}
