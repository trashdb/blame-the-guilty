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
                        .font(.system(size: 20, weight: .bold))

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
            Text("Workspace Path")
                .font(.system(size: 13, weight: .medium))
            Text("Local git repos are discovered recursively under this directory.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.top, -8)
            HStack(spacing: 6) {
                TextField("e.g. ~/Desktop/dev", text: $pathDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
                    .onAppear { pathDraft = workspacePath }
                Button("Save") {
                    workspacePath = pathDraft
                    SettingsPanelManager.shared.close()
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(.green.opacity(0.3), lineWidth: 1)
                )
                .buttonStyle(.plain)
                .cursor(.pointingHand)
            }
        }
    }

    @ViewBuilder
    private var jiraSection: some View {
        Group {
            Text("Jira Ticket Base URL")
                .font(.system(size: 13, weight: .medium))
            Text("Used to build links to tickets extracted from branch names (e.g. LOY-1234 → https://.../browse/LOY-1234).")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.top, -8)
            HStack(spacing: 6) {
                TextField("https://your-domain.atlassian.net/browse/", text: $jiraDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
                    .onAppear { jiraDraft = jiraBoardUrl }
                Button("Save") {
                    jiraBoardUrl = jiraDraft
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(.green.opacity(0.3), lineWidth: 1)
                )
                .buttonStyle(.plain)
                .cursor(.pointingHand)
            }

            Text("Jira Board URL")
                .font(.system(size: 13, weight: .medium))
                .padding(.top, 12)
            Text("Opened by the \"Open Jira Board\" spotlight command.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.top, -8)
            HStack(spacing: 6) {
                TextField("https://your-domain.atlassian.net/jira/...", text: $jiraViewDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
                    .onAppear { jiraViewDraft = jiraBoardViewUrl }
                Button("Save") {
                    jiraBoardViewUrl = jiraViewDraft
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(.green.opacity(0.3), lineWidth: 1)
                )
                .buttonStyle(.plain)
                .cursor(.pointingHand)
            }
        }
    }

    @ViewBuilder
    private var favoriteRepoSection: some View {
        Group {
            Text("Favorite Repo")
                .font(.system(size: 13, weight: .medium))
            HStack(spacing: 6) {
                if scanning {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 100)
                } else if discoveredRepos.isEmpty {
                    Text("No repos found — check workspace path")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Picker(selection: $favoriteRepo) {
                        ForEach(discoveredRepos, id: \.self) { repo in
                            HStack(spacing: 4) {
                                if repo == favoriteRepo {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                }
                                Text(repo)
                            }
                            .tag(repo)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .font(.system(size: 9))
                            Text(favoriteRepo)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Refresh") {
                    Task { await scanForRepos() }
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(.green.opacity(0.3), lineWidth: 1)
                )
                .buttonStyle(.plain)
                .cursor(.pointingHand)
            }
        }
    }

    @ViewBuilder
    private var menuBarSection: some View {
        Group {
            Text("Menu Bar Widget")
                .font(.system(size: 13, weight: .medium))
            Text("Show PR/CI status counts directly in the menu bar icon.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.top, -8)
            HStack(spacing: 8) {
                ForEach(MenuBarWidgetMode.allCases, id: \.rawValue) { mode in
                    Button {
                        menuBarWidgetMode = mode.rawValue
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: modeIcon(mode))
                                .font(.system(size: 16))
                            Text(mode.rawValue)
                                .font(.system(size: 10, weight: .medium))
                            Text(modeDescription(mode))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(height: 24)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(menuBarWidgetMode == mode.rawValue ? .blue.opacity(0.2) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(menuBarWidgetMode == mode.rawValue ? .blue.opacity(0.5) : .white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                }
            }
        }
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
            Text("Backend URL")
                .font(.system(size: 13, weight: .medium))
            Text("The backend server URL. Only change if self-hosting the blame-the-guilty server.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.top, -8)
            HStack(spacing: 6) {
                TextField("https://...", text: $backendUrlDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
                    .onAppear { backendUrlDraft = settingsBackendUrl }
                Button("Save") {
                    settingsBackendUrl = backendUrlDraft
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(.green.opacity(0.3), lineWidth: 1)
                )
                .buttonStyle(.plain)
                .cursor(.pointingHand)
            }
        }
    }

    @ViewBuilder
    private var patSection: some View {
        Group {
            Text("Personal Access Token")
                .font(.system(size: 13, weight: .medium))
            Text("Optional. Used to access org repos when OAuth is blocked. Create at github.com/settings/tokens with repo scope.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.top, -8)
            HStack(spacing: 6) {
                SecureField("github_pat_...", text: $patDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
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
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(.green.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)
                .disabled(patSaving || patDraft.isEmpty)
            }
            if patSaved {
                Text("PAT saved successfully")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
            if let patError {
                Text(patError)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Default IDE")
                .font(.system(size: 13, weight: .medium))
            Text("Select your favourite IDE from the dropdown.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Button {
                showPicker = true
            } label: {
                HStack(spacing: 8) {
                    current.viewIcon(size: 22)
                    Text(current.displayName)
                        .font(.system(size: 12))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)
            .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                VStack(spacing: 6) {
                    TextField("Search IDE…", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        )

                    ScrollView(.vertical) {
                        LazyVStack(spacing: 2) {
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
                .padding(10)
                .frame(width: 320)
            }

            if defaultIDE == "custom" {
                TextField("e.g. myeditor://open?file={file}&line={line}", text: $customIDECommand)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
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
            HStack(spacing: 10) {
                    ide.viewIcon(size: 26)
                        .frame(width: 32)
                Text(ide.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? .white.opacity(0.1)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }
}
