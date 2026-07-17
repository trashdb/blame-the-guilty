import SwiftUI

struct QuickSearchAction: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let category: QuickSearchCategory
    let action: () -> Void

    static func == (lhs: QuickSearchAction, rhs: QuickSearchAction) -> Bool {
        lhs.id == rhs.id
    }
}

enum QuickSearchCategory: String, CaseIterable {
    case jira = "Jira"
    case github = "GitHub"
    case repo = "Repos"
    case branch = "Branches"
    case app = "App"
    case ai = "AI"

    var icon: String {
        switch self {
        case .jira:    return "link"
        case .github:  return "tray.full"
        case .repo:    return "folder"
        case .branch:  return "arrow.triangle.branch"
        case .app:     return "gearshape"
        case .ai:      return "sparkle"
        }
    }
}

struct QuickSearchView: View {
    @Binding var isPresented: Bool
    let actions: [QuickSearchAction]
    let signalR: SignalRService
    let gitHubId: Int64
    let backendUrl: String

    @State private var query = ""
    @State private var selectedIndex = 0

    private var projectKey: String {
        let url = UserDefaults.standard.string(forKey: "jiraBoardViewUrl") ?? TeamDefaults.jiraBoardViewUrl
        if let match = try? NSRegularExpression(pattern: "/projects/([A-Z]+)/")
            .firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
           let range = Range(match.range(at: 1), in: url) {
            return String(url[range])
        }
        return "LOY"
    }

    private var smartResults: [QuickSearchAction] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, q.count >= 2 else { return [] }
        var results: [QuickSearchAction] = []
        let lower = q.lowercased()
        let branches = MenuBarBadgeService.shared.currentBranches
        let jiraUrl = UserDefaults.standard.string(forKey: "jiraBoardUrl") ?? TeamDefaults.jiraBoardUrl

        // "open 945" or just "945"
        if let match = try? NSRegularExpression(pattern: "^(?:open\\s+)?(\\d+)$", options: .caseInsensitive)
            .firstMatch(in: q, range: NSRange(q.startIndex..., in: q)),
           let range = Range(match.range(at: 1), in: q) {
            let ticket = "\(projectKey)-\(q[range])"
            results.append(QuickSearchAction(
                id: "smart-ticket-\(ticket)", title: "Open Jira ticket \(ticket)",
                subtitle: "Open ticket in browser", icon: "link", category: .jira
            ) {
                if let u = URL(string: "\(jiraUrl)\(ticket)") { NSWorkspace.shared.open(u) }
            })
        }

        // "LOY-945" or "open LOY-945" (full ticket key)
        if let match = try? NSRegularExpression(pattern: "^(?:open\\s+)?([A-Z]+-\\d+)$", options: .caseInsensitive)
            .firstMatch(in: q, range: NSRange(q.startIndex..., in: q)),
           let range = Range(match.range(at: 1), in: q) {
            let ticket = String(q[range]).uppercased()
            results.append(QuickSearchAction(
                id: "smart-ticket-\(ticket)", title: "Open Jira ticket \(ticket)",
                subtitle: "Open ticket in browser", icon: "link", category: .jira
            ) {
                if let u = URL(string: "\(jiraUrl)\(ticket)") { NSWorkspace.shared.open(u) }
            })
        }

        // "checkout <name>" — find matching branch
        if let match = try? NSRegularExpression(pattern: "^checkout\\s+(.+)", options: .caseInsensitive)
            .firstMatch(in: q, range: NSRange(q.startIndex..., in: q)),
           let range = Range(match.range(at: 1), in: q) {
            let term = String(q[range]).lowercased()
            for b in branches {
                if b.name.lowercased().contains(term) || b.repoName.lowercased().contains(term) {
                    results.append(QuickSearchAction(
                        id: "smart-checkout-\(b.repoPath)-\(b.name)",
                        title: "Checkout \(b.name) in \(b.repoName)",
                        subtitle: b.repoPath, icon: "arrow.triangle.branch", category: .branch
                    ) {
                        Task {
                            let git = GitService()
                            try? await git.checkoutBranch(repoPath: b.repoPath, name: b.name)
                            try? await git.pullCurrentBranch(repoPath: b.repoPath)
                        }
                    })
                }
            }
        }

        // "create pr from <name>" or "pr <name>"
        if let match = try? NSRegularExpression(pattern: "(?:create\\s+)?pr\\s+(?:from\\s+)?(.+)", options: .caseInsensitive)
            .firstMatch(in: q, range: NSRange(q.startIndex..., in: q)),
           let range = Range(match.range(at: 1), in: q) {
            let term = String(q[range]).lowercased()
            for b in branches {
                if b.name.lowercased().contains(term) || b.repoName.lowercased().contains(term) {
                    let info = BranchInfo(name: b.name, repoPath: b.repoPath, repoName: b.repoName, isCurrent: true, isLocal: true, isMerged: false, isDefault: false)
                    results.append(QuickSearchAction(
                        id: "smart-pr-\(b.repoPath)-\(b.name)",
                        title: "Create PR from \(b.name)",
                        subtitle: "\(b.repoName) → open PR preview", icon: "plus.circle", category: .branch
                    ) {
                        BranchDetailPanelManager.shared.show(info: info, gitHubId: self.gitHubId, backendUrl: self.backendUrl, onCheckout: nil)
                    })
                }
            }
        }

        return results
    }

    private var regularResults: [QuickSearchAction] {
        if query.isEmpty { return actions }
        let lower = query.lowercased()
        return actions.filter { action in
            action.title.lowercased().contains(lower) ||
            action.subtitle.lowercased().contains(lower) ||
            action.id.lowercased().contains(lower)
        }
    }

    private var allResults: [QuickSearchAction] {
        smartResults + regularResults
    }

    private var hasAnyResults: Bool {
        !allResults.isEmpty
    }

    var body: some View {
        if !isPresented {
            Color.clear
                .frame(width: 0, height: 0)
        } else {
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { isPresented = false }

                VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                TextField("Search or ask anything…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(white: 0.95))
                    .onSubmit { executeSelected() }
            }
            .padding(12)
            .background(.white.opacity(0.06))

            if query.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 1, pinnedViews: .sectionHeaders) {
                            let grouped = Dictionary(grouping: allResults) { $0.category }
                            ForEach(QuickSearchCategory.allCases, id: \.rawValue) { cat in
                                if let items = grouped[cat], !items.isEmpty {
                                    Section {
                                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, action in
                                            let globalIdx = allResults.firstIndex(where: { $0.id == action.id }) ?? 0
                                            Button {
                                                select(action)
                                            } label: {
                                                actionRow(action, globalIdx: globalIdx)
                                            }
                                            .buttonStyle(.plain)
                                            .cursor(.pointingHand)
                                            .id(action.id)
                                        }
                                    } header: {
                                        sectionHeader(cat)
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: selectedIndex) { newVal in
                        if newVal >= 0, newVal < allResults.count {
                            withAnimation(.none) {
                                proxy.scrollTo(allResults[newVal].id, anchor: .center)
                            }
                        }
                    }
                }
                .frame(height: min(CGFloat(allResults.count) * 40 + CGFloat(QuickSearchCategory.allCases.count) * 20, 400))
            } else if !hasAnyResults {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("No matching commands")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(height: 180)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 1, pinnedViews: .sectionHeaders) {
                            let grouped = Dictionary(grouping: allResults) { $0.category }
                            ForEach(QuickSearchCategory.allCases, id: \.rawValue) { cat in
                                if let items = grouped[cat], !items.isEmpty {
                                    Section {
                                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, action in
                                            let globalIdx = allResults.firstIndex(where: { $0.id == action.id }) ?? 0
                                            Button {
                                                select(action)
                                            } label: {
                                                actionRow(action, globalIdx: globalIdx)
                                            }
                                            .buttonStyle(.plain)
                                            .cursor(.pointingHand)
                                            .id(action.id)
                                        }
                                    } header: {
                                        sectionHeader(cat)
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: selectedIndex) { newVal in
                        if newVal >= 0, newVal < allResults.count {
                            withAnimation(.none) {
                                proxy.scrollTo(allResults[newVal].id, anchor: .center)
                            }
                        }
                    }
                }
                .frame(height: min(CGFloat(allResults.count) * 40 + CGFloat(QuickSearchCategory.allCases.count) * 20, 400))
            }

            HStack(spacing: 12) {
                Text("↵ execute")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text("⌘K close")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(allResults.count) results")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.white.opacity(0.04))
        }
        .frame(width: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            selectedIndex = 0
            Task {
                let path = UserDefaults.standard.string(forKey: "workspacePath") ?? TeamDefaults.workspacePath
                let branches = await GitService.scanCurrentBranches(workspacePath: path)
                await MainActor.run { MenuBarBadgeService.shared.currentBranches = branches }
            }
        }
        .onChange(of: query) { _ in selectedIndex = 0 }
        .onChange(of: isPresented) { shown in if shown { query = ""; selectedIndex = 0 } }
        }
    }
}

    private func select(_ action: QuickSearchAction) {
        query = ""
        isPresented = false
        action.action()
    }

    private func executeSelected() {
        guard !allResults.isEmpty, selectedIndex < allResults.count else { return }
        select(allResults[selectedIndex])
    }

    func moveUp() {
        guard !allResults.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + allResults.count) % allResults.count
    }

    func moveDown() {
        guard !allResults.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % allResults.count
    }

    @ViewBuilder
    private func actionRow(_ action: QuickSearchAction, globalIdx: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: action.icon)
                .font(.system(size: 12))
                .foregroundStyle(.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(white: 0.9))
                Text(action.subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if globalIdx == selectedIndex {
                Image(systemName: "arrow.left")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            globalIdx == selectedIndex
                ? .blue.opacity(0.15)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
    }

    @ViewBuilder
    private func sectionHeader(_ cat: QuickSearchCategory) -> some View {
        HStack(spacing: 4) {
            Image(systemName: cat.icon)
                .font(.system(size: 9))
            Text(cat.rawValue)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }
}
