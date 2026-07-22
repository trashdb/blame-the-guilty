import SwiftUI

struct SettingsView: View {
    let gitHubId: Int64
    let backendUrl: String

    @AppStorage("workspacePath") private var workspacePath = TeamDefaults.workspacePath
    @AppStorage("jiraBoardUrl") private var jiraBoardUrl = TeamDefaults.jiraBoardUrl
    @AppStorage("jiraBoardViewUrl") private var jiraBoardViewUrl = TeamDefaults.jiraBoardViewUrl
    @AppStorage("favoriteRepo") private var favoriteRepo = TeamDefaults.favoriteRepo
    @AppStorage("defaultIDE") private var defaultIDE = "rider"
    @AppStorage("customIDECommand") private var customIDECommand = ""
    @AppStorage("backendUrl") private var settingsBackendUrl = TeamDefaults.backendUrl
    @AppStorage("showMergedPRs") private var showMergedPRs = true
    @State private var pathDraft = ""
    @State private var pathError: String?
    @State private var jiraDraft = ""
    @State private var jiraError: String?
    @State private var jiraViewDraft = ""
    @State private var jiraViewError: String?
    @State private var backendUrlDraft = ""
    @State private var backendUrlError: String?
    @State private var patDraft = ""
    @State private var ideDraft = ""
    @State private var patSaved = false
    @State private var patSaving = false
    @State private var patError: String?
    @State private var discoveredRepos: [String] = []
    @State private var scanning = true

    // Connection test states
    @State private var backendTestResult: ConnectionTestResult?
    @State private var backendTesting = false
    @State private var jiraTestResult: ConnectionTestResult?

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .sidebar)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: DS.Spacing.lg) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(DS.Color.accent)
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("Settings")
                                .font(DS.Font.largeTitle)
                            Text("Blame the Guilty")
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                    }
                    .padding(.bottom, DS.Spacing.xl)

                    CollapsibleSection(title: "Workspace", icon: "folder") {
                        workspaceSection
                    }

                    CollapsibleSection(title: "Jira", icon: "link") {
                        jiraSection
                    }

                    CollapsibleSection(title: "IDE", icon: "chevron.left.forwardslash.chevron.right") {
                        IDEListView(defaultIDE: $defaultIDE, customIDECommand: $customIDECommand)
                    }

                    CollapsibleSection(title: "Favorite Repo", icon: "star") {
                        favoriteRepoSection
                    }

                    CollapsibleSection(title: "Backend URL", icon: "server.rack") {
                        backendSection
                    }

                    CollapsibleSection(title: "Personal Access Token", icon: "key.fill") {
                        patSection
                    }

                    CollapsibleSection(title: "Pull Requests", icon: "arrow.triangle.branch") {
                        pullRequestsSection
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 540, height: 620)
        .onAppear { Task { await scanForRepos() } }
        .closeOnEscape { SettingsPanelManager.shared.close() }
        .closeOnCmdW { SettingsPanelManager.shared.close() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var workspaceSection: some View {
        Text("Local git repos are discovered recursively under this directory. Changes apply immediately without restart.")
            .font(DS.Font.small)
            .foregroundStyle(DS.Color.textSecondary)
        HStack(spacing: DS.Spacing.md) {
            styledTextField(
                "e.g. ~/Desktop/dev",
                text: $pathDraft,
                help: "Absolute path to the parent directory containing your git repositories. Subdirectories are scanned recursively.",
                error: $pathError
            )
            .onAppear { pathDraft = workspacePath }
            solidButton("Save", color: .green) {
                let expanded = (pathDraft as NSString).expandingTildeInPath
                if FileManager.default.fileExists(atPath: expanded) {
                    workspacePath = pathDraft
                    pathError = nil
                    SettingsPanelManager.shared.close()
                } else {
                    pathError = "Directory not found at \(expanded)"
                }
            }
        }
    }

    @ViewBuilder
    private var pullRequestsSection: some View {
        Text("Control which pull requests appear in the Active PRs list.")
            .font(DS.Font.small)
            .foregroundStyle(DS.Color.textSecondary)

        Toggle(isOn: $showMergedPRs) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show merged PRs")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textPrimary)
                Text("When on, recently merged PRs stay visible for 24h. Turn off to only see open PRs.")
                    .font(DS.Font.small)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
        .toggleStyle(.switch)
        .tint(DS.Color.success)
    }

    @ViewBuilder
    private var jiraSection: some View {
        Text("Used to build links to tickets extracted from branch names (e.g. LOY-1234 → https://.../browse/LOY-1234). Paste the full URL including /browse/.")
        Text("Used to build links to tickets extracted from branch names (e.g. LOY-1234 → https://.../browse/LOY-1234). Paste the full URL including /browse/.")
            .font(DS.Font.small)
            .foregroundStyle(DS.Color.textSecondary)

        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionHeader("Ticket Base URL")
            HStack(spacing: DS.Spacing.md) {
                urlTextField(
                    "https://your-domain.atlassian.net/browse/",
                    text: $jiraDraft,
                    required: false,
                    help: "Base URL for opening individual Jira tickets from branch names (e.g. LOY-123 → https://domain.atlassian.net/browse/LOY-123).",
                    error: $jiraError
                )
                .onAppear { jiraDraft = jiraBoardUrl }
                solidButton("Save", color: .green) {
                    saveJiraUrl()
                }
            }

            sectionHeader("Board URL")
            HStack(spacing: DS.Spacing.md) {
                urlTextField(
                    "https://your-domain.atlassian.net/jira/...",
                    text: $jiraViewDraft,
                    required: false,
                    help: "Full URL to your Jira board for quick access from the toolbar menu.",
                    error: $jiraViewError
                )
                .onAppear { jiraViewDraft = jiraBoardViewUrl }
                solidButton("Save", color: .green) {
                    saveJiraViewUrl()
                }
            }

            HStack(spacing: DS.Spacing.sm) {
                actionButton("Test Connection", color: .blue, help: "Open Jira board in browser to verify URL") {
                    let url = jiraBoardViewUrl.isEmpty ? jiraBoardUrl : jiraBoardViewUrl
                    if let u = URL(string: url) {
                        NSWorkspace.shared.open(u)
                        jiraTestResult = .success("Opened in browser")
                    } else {
                        jiraTestResult = .failure("Invalid URL")
                    }
                }
                if let result = jiraTestResult {
                    connectionTestBadge(result)
                }
            }
        }
    }

    private func saveJiraUrl() {
        if jiraDraft.isEmpty {
            jiraBoardUrl = jiraDraft
            jiraError = nil
        } else if URL(string: jiraDraft) != nil {
            jiraBoardUrl = jiraDraft
            jiraError = nil
        } else {
            jiraError = "Invalid URL format"
        }
    }

    private func saveJiraViewUrl() {
        if jiraViewDraft.isEmpty {
            jiraBoardViewUrl = jiraViewDraft
            jiraViewError = nil
        } else if URL(string: jiraViewDraft) != nil {
            jiraBoardViewUrl = jiraViewDraft
            jiraViewError = nil
        } else {
            jiraViewError = "Invalid URL format"
        }
    }

    @ViewBuilder
    private var favoriteRepoSection: some View {
        HStack(spacing: DS.Spacing.md) {
            if scanning {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 100)
            } else if discoveredRepos.isEmpty {
                Text("No repos found — check workspace path")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textSecondary)
            } else {
                Picker(selection: $favoriteRepo) {
                    ForEach(discoveredRepos, id: \.self) { repo in
                        HStack(spacing: DS.Spacing.sm) {
                            if repo == favoriteRepo {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                            }
                            Text(repo)
                        }
                        .tag(repo)
                    }
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(DS.Font.caption)
                        Text(favoriteRepo)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nativeCursor(.pointingHand)
            }
            actionButton("Refresh", color: .green) {
                Task { await scanForRepos() }
            }
        }
    }

    @ViewBuilder
    private var backendSection: some View {
        Text("The backend server URL. Only change if self-hosting the blame-the-guilty server. Must point to a running instance with /health endpoint.")
            .font(DS.Font.small)
            .foregroundStyle(DS.Color.textSecondary)

        HStack(spacing: DS.Spacing.md) {
            urlTextField(
                "https://your-server.com",
                text: $backendUrlDraft,
                help: "Full URL of the blame-the-guilty backend server, including protocol (https://). The server must expose a /health endpoint.",
                error: $backendUrlError
            )
            .onAppear { backendUrlDraft = settingsBackendUrl }
            solidButton("Save", color: .green) {
                saveBackendUrl()
            }
        }

        HStack(spacing: DS.Spacing.sm) {
            actionButton("Test Connection", color: .blue, help: "Test connectivity to the backend server by calling its /health endpoint") {
                Task { await testBackendConnection() }
            }
            .disabled(backendTesting)
            if backendTesting {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }
            if let result = backendTestResult {
                connectionTestBadge(result)
            }
        }
    }

    private func saveBackendUrl() {
        if backendUrlDraft.isEmpty {
            backendUrlError = "URL is required"
        } else if URL(string: backendUrlDraft) != nil {
            settingsBackendUrl = backendUrlDraft
            backendUrlError = nil
        } else {
            backendUrlError = "Invalid URL format"
        }
    }

    @ViewBuilder
    private var patSection: some View {
        Text("Optional. Used to access org repos when OAuth is blocked. Create at github.com/settings/tokens with repo scope.")
            .font(DS.Font.small)
            .foregroundStyle(DS.Color.textSecondary)
            .padding(.top, -8)
        HStack(spacing: DS.Spacing.md) {
            styledTextField(
                "github_pat_...",
                text: $patDraft,
                help: "GitHub Personal Access Token (classic) with repo scope. Required when OAuth authentication does not grant access to organisation repositories."
            )
            .onAppear { patDraft = "" }
            solidButton(patSaving ? "Saving…" : "Save", color: .green, disabled: patSaving || patDraft.isEmpty) {
                Task { await savePat() }
            }
        }
        if patSaved {
            Text("PAT saved successfully")
                .font(DS.Font.small)
                .foregroundStyle(DS.Color.success)
        }
        if let patError {
            Text(patError)
                .font(DS.Font.small)
                .foregroundStyle(DS.Color.destructive)
        }
    }

    // MARK: - Helpers

    private func scanForRepos() async {
        scanning = true
        let expanded = (workspacePath as NSString).expandingTildeInPath
        let paths = GitService.discoverRepos(workspacePath: expanded)
        await MainActor.run {
            discoveredRepos = paths.compactMap { GitService.repoName(from: $0) }.sorted()
            if !discoveredRepos.contains(favoriteRepo), let first = discoveredRepos.first {
                favoriteRepo = first
            }
            scanning = false
        }
    }

    private func savePat() async {
        patSaving = true
        patSaved = false
        patError = nil
        defer { patSaving = false }

        guard let url = URL(string: "\(settingsBackendUrl)/api/auth/pat?gitHubId=\(gitHubId)") else {
            patError = "Invalid backend URL"
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["patToken": patDraft])

        // Persist locally first so `GitService.storedPAT()` is always a reliable
        // fallback for git pull over HTTPS, even if the backend is unreachable.
        let draft = patDraft
        UserDefaults.standard.set(draft, forKey: "patToken")

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                patSaved = true
                patDraft = ""
            } else {
                patError = "Saved locally, but backend rejected it (HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1))"
            }
        } catch {
            patError = "Saved locally, but backend is unreachable: \(error.localizedDescription)"
        }
    }

    private func testBackendConnection() async {
        backendTesting = true
        backendTestResult = nil
        defer { backendTesting = false }

        let url = backendUrlDraft.isEmpty ? settingsBackendUrl : backendUrlDraft
        guard let u = URL(string: "\(url)/health") else {
            backendTestResult = .failure("Invalid URL")
            return
        }
        do {
            let (data, resp) = try await URLSession.shared.data(from: u)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String {
                    backendTestResult = .success("Healthy (\(status))")
                } else {
                    backendTestResult = .success("Connected")
                }
            } else {
                backendTestResult = .failure("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
            }
        } catch {
            backendTestResult = .failure(error.localizedDescription)
        }
    }

    @ViewBuilder
    private func connectionTestBadge(_ result: ConnectionTestResult) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Circle()
                .fill(result.isSuccess ? DS.Color.success : DS.Color.destructive)
                .frame(width: 6, height: 6)
            Text(result.message)
                .font(DS.Font.tiny)
                .foregroundStyle(result.isSuccess ? DS.Color.success : DS.Color.destructive)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(
            (result.isSuccess ? DS.Color.success : DS.Color.destructive).opacity(0.1),
            in: RoundedRectangle(cornerRadius: DS.Radius.sm)
        )
    }
}

// MARK: - Connection Test Result

enum ConnectionTestResult {
    case success(String)
    case failure(String)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .success(let m): return m
        case .failure(let m): return m
        }
    }
}

// MARK: - Collapsible Section

struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    @State private var isExpanded = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Button {
                withAnimation(DS.Animation.hover) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: icon)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.accent)
                    Text(title)
                        .font(DS.Font.section)
                        .foregroundStyle(DS.Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(DS.Font.micro)
                        .foregroundStyle(DS.Color.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, DS.Spacing.md)
                .padding(.horizontal, DS.Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)

            if isExpanded {
                content
                    .padding(.leading, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.md)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
        }
    }
}

// MARK: - IDE List View

struct IDEListView: View {
    @Binding var defaultIDE: String
    @Binding var customIDECommand: String
    @State private var showPicker = false
    @State private var search = ""

    private var current: IDEDefinition { ideDefinition(for: defaultIDE) }
    private var filtered: [IDEDefinition] {
        search.isEmpty
            ? installedIDEs
            : installedIDEs.filter { $0.displayName.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            Text("Select your favourite IDE from the dropdown.")
                .font(DS.Font.small)
                .foregroundStyle(DS.Color.textSecondary)

            Button {
                showPicker = true
            } label: {
                HStack(spacing: DS.Spacing.lg) {
                    current.viewIcon(size: 22)
                    Text(current.displayName)
                        .font(DS.Font.body)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.vertical, DS.Spacing.lg - 1)
                .background(DS.Color.fieldBackground, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(DS.Color.divider, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Choose your preferred IDE for opening files")
            .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                VStack(spacing: DS.Spacing.md) {
                    styledTextField("Search IDE…", text: $search, help: "Filter available IDEs by name")

                    ScrollView(.vertical) {
                        LazyVStack(spacing: DS.Spacing.xs) {
                            ForEach(filtered, id: \.id) { ide in
                                IDERow(
                                    ide: ide,
                                    isSelected: defaultIDE == ide.id,
                                    action: {
                                        defaultIDE = ide.id
                                        if ide.id != "custom" { customIDECommand = "" }
                                        showPicker = false
                                        search = ""
                                    }
                                )
                            }
                        }
                    }
                    .frame(height: min(CGFloat(filtered.count) * 30 + 4, 300))
                }
                .padding(DS.Spacing.xl)
                .frame(width: 320)
            }
            .cursor(.pointingHand)

            if defaultIDE == "custom" {
                styledTextField("e.g. myeditor://open?file={file}&line={line}", text: $customIDECommand, help: "Custom URL scheme to open files in your editor")
            }
        }
    }
}

private struct IDERow: View {
    let ide: IDEDefinition
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xl) {
                ide.viewIcon(size: 26)
                    .frame(width: 32)
                Text(ide.displayName)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(DS.Font.body.bold())
                        .foregroundStyle(DS.Color.accent)
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.vertical, DS.Spacing.lg)
            .background(
                isSelected
                    ? DS.Color.fieldBackground
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: DS.Radius.sm)
            )
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }
}
