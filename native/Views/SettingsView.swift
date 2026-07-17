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
    @AppStorage("menuBarWidgetMode") private var menuBarWidgetMode = MenuBarWidgetMode.minimal.rawValue
    @AppStorage("backendUrl") private var settingsBackendUrl = TeamDefaults.backendUrl
    @State private var pathDraft = ""
    @State private var jiraDraft = ""
    @State private var jiraViewDraft = ""
    @State private var backendUrlDraft = ""
    @State private var patDraft = ""
    @State private var ideDraft = ""
    @State private var patSaved = false
    @State private var patSaving = false
    @State private var patError: String?
    @State private var discoveredRepos: [String] = []
    @State private var scanning = true

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .sidebar)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Settings")
                        .font(DS.Font.largeTitle)

                    Divider()

                    workspaceSection
                    Divider()
                    jiraSection
                    Divider()
                    favoriteRepoSection
                    Divider()
                    IDEListView(defaultIDE: $defaultIDE, customIDECommand: $customIDECommand)
                    Divider()
                    menuBarSection
                    Divider()
                    backendSection
                    Divider()
                    if gitHubId > 0 { patSection }
                }
                .padding(24)
            }
        }
        .frame(width: 540, height: 620)
        .onAppear { Task { await scanForRepos() } }
    }

    @ViewBuilder
    private var workspaceSection: some View {
        Group {
            sectionHeader("Workspace Path")
            Text("Local git repos are discovered recursively under this directory.")
                .font(DS.Font.small)
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.top, -8)
            HStack(spacing: DS.Spacing.md) {
                styledTextField("e.g. ~/Desktop/dev", text: $pathDraft)
                    .onAppear { pathDraft = workspacePath }
                solidButton("Save", color: .green) {
                    workspacePath = pathDraft
                    SettingsPanelManager.shared.close()
                }
            }
        }
    }

    @ViewBuilder
    private var jiraSection: some View {
        Group {
            sectionHeader("Jira Ticket Base URL")
            Text("Used to build links to tickets extracted from branch names (e.g. LOY-1234 → https://.../browse/LOY-1234).")
                .font(DS.Font.small)
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.top, -8)
            HStack(spacing: DS.Spacing.md) {
                styledTextField("https://your-domain.atlassian.net/browse/", text: $jiraDraft)
                    .onAppear { jiraDraft = jiraBoardUrl }
                solidButton("Save", color: .green) {
                    jiraBoardUrl = jiraDraft
                }
            }

            sectionHeader("Jira Board URL")
                .padding(.top, 12)
            Text("Opened by the \"Open Jira Board\" spotlight command.")
                .font(DS.Font.small)
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.top, -8)
            HStack(spacing: DS.Spacing.md) {
                styledTextField("https://your-domain.atlassian.net/jira/...", text: $jiraViewDraft)
                    .onAppear { jiraViewDraft = jiraBoardViewUrl }
                solidButton("Save", color: .green) {
                    jiraBoardViewUrl = jiraViewDraft
                }
            }
        }
    }

    @ViewBuilder
    private var favoriteRepoSection: some View {
        Group {
            sectionHeader("Favorite Repo")
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
                }
                actionButton("Refresh", color: .green) {
                    Task { await scanForRepos() }
                }
            }
        }
    }

    @ViewBuilder
    private var menuBarSection: some View {
        Group {
            sectionHeader("Menu Bar Widget")
            Text("Show PR/CI status counts directly in the menu bar icon.")
                .font(DS.Font.small)
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.top, -8)
            HStack(spacing: DS.Spacing.lg) {
                ForEach(MenuBarWidgetMode.allCases, id: \.rawValue) { mode in
                    menuBarCard(mode)
                }
            }
        }
    }

    private func menuBarCard(_ mode: MenuBarWidgetMode) -> some View {
        Button {
            menuBarWidgetMode = mode.rawValue
        } label: {
            VStack(spacing: DS.Spacing.sm) {
                Image(systemName: modeIcon(mode))
                    .font(.system(size: 16))
                Text(mode.rawValue)
                    .font(DS.Font.small.medium())
                Text(modeDescription(mode))
                    .font(DS.Font.tiny)
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 24)
            }
            .frame(maxWidth: .infinity)
            .padding(DS.Spacing.xl)
            .background(cardBackground(mode), in: RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(cardBorder(mode), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }

    private func cardBackground(_ mode: MenuBarWidgetMode) -> SwiftUI.Color {
        menuBarWidgetMode == mode.rawValue ? DS.Color.accent.opacity(0.2) : DS.Color.fieldBackground
    }

    private func cardBorder(_ mode: MenuBarWidgetMode) -> SwiftUI.Color {
        menuBarWidgetMode == mode.rawValue ? DS.Color.accent.opacity(0.5) : DS.Color.divider
    }

    private func modeIcon(_ mode: MenuBarWidgetMode) -> String {
        switch mode {
        case .minimal: return "flame"
        case .badge:   return "flame.badge.exclamationmark"
        case .counts:  return "number"
        case .full:    return "text.badge.checkmark"
        }
    }

    private func modeDescription(_ mode: MenuBarWidgetMode) -> String {
        switch mode {
        case .minimal: return "Just 'Blame'"
        case .badge:   return "Icons for failures & running"
        case .counts:  return "Total PR count"
        case .full:    return "PRs, failures, running"
        }
    }

    @ViewBuilder
    private var backendSection: some View {
        Group {
            sectionHeader("Backend URL")
            Text("The backend server URL. Only change if self-hosting the blame-the-guilty server.")
                .font(DS.Font.small)
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.top, -8)
            HStack(spacing: DS.Spacing.md) {
                styledTextField("https://...", text: $backendUrlDraft)
                    .onAppear { backendUrlDraft = settingsBackendUrl }
                solidButton("Save", color: .green) {
                    settingsBackendUrl = backendUrlDraft
                }
            }
        }
    }

    @ViewBuilder
    private var patSection: some View {
        Group {
            sectionHeader("Personal Access Token")
            Text("Optional. Used to access org repos when OAuth is blocked. Create at github.com/settings/tokens with repo scope.")
                .font(DS.Font.small)
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.top, -8)
            HStack(spacing: DS.Spacing.md) {
                SecureField("github_pat_...", text: $patDraft)
                    .textFieldStyle(.plain)
                    .font(DS.Font.mono(12))
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DS.Color.fieldBackground, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.divider, lineWidth: 1)
                    )
                Button {
                    Task { await savePat() }
                } label: {
                    if patSaving {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 40)
                    } else {
                        Text("Save")
                            .font(DS.Font.caption.semibold())
                            .foregroundStyle(.green)
                            .padding(.horizontal, DS.Spacing.xl)
                            .padding(.vertical, DS.Spacing.sm + 1)
                            .background(DS.Color.badgeBackground(.green), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.sm)
                                    .stroke(DS.Color.badgeBorder(.green), lineWidth: 1)
                            )
                    }
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)
                .disabled(patSaving || patDraft.isEmpty)
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
    }

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

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                patSaved = true
                patDraft = ""
            } else {
                patError = "Failed to save PAT"
            }
        } catch {
            patError = error.localizedDescription
        }
    }
}

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
            sectionHeader("Default IDE")
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
            .cursor(.pointingHand)
            .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                VStack(spacing: DS.Spacing.md) {
                    styledTextField("Search IDE…", text: $search)

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

            if defaultIDE == "custom" {
                styledTextField("e.g. myeditor://open?file={file}&line={line}", text: $customIDECommand)
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
