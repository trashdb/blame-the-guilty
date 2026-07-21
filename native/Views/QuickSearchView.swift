import AppKit
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
        let branches = MenuBarBadgeService.shared.currentBranches
        let jiraUrl = UserDefaults.standard.string(forKey: "jiraBoardUrl") ?? TeamDefaults.jiraBoardUrl

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
                    .cursor(.pointingHand)

                VStack(spacing: 0) {
                    HStack(spacing: DS.Spacing.lg) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundStyle(DS.Color.textSecondary)
                        TextField("Search or ask anything…", text: $query)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundStyle(DS.Color.textPrimary)
                            .onSubmit { executeSelected() }
                    }
                    .padding(DS.Spacing.xl)
                    .background(DS.Color.fieldBackground.opacity(0.6))

                    Group {
                        if query.isEmpty {
                            resultsList
                        } else if !hasAnyResults {
                            VStack(spacing: DS.Spacing.lg) {
                                Spacer()
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 24))
                                    .foregroundStyle(DS.Color.textTertiary)
                                Text("No matching commands")
                                    .font(DS.Font.body)
                                    .foregroundStyle(DS.Color.textSecondary)
                                Spacer()
                            }
                            .frame(height: 180)
                        } else {
                            resultsList
                        }
                    }
                    .animation(DS.Animation.default, value: query.isEmpty)
                    .animation(DS.Animation.default, value: hasAnyResults)

                    HStack(spacing: DS.Spacing.xl) {
                        Text("↵ execute")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                        Text("⌘K close")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                        Spacer()
                        Text("\(allResults.count) results")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DS.Color.fieldBackground.opacity(0.4))
                }
                .frame(width: 360)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.xl)
                        .stroke(DS.Color.divider, lineWidth: 1)
                )
                .transition(.scale(scale: 0.95).combined(with: .opacity))
                .onAppear {
                    selectedIndex = 0
                    focusTextField()
                    Task {
                        let path = UserDefaults.standard.string(forKey: "workspacePath") ?? TeamDefaults.workspacePath
                        let branches = await GitService.scanCurrentBranches(workspacePath: path)
                        await MainActor.run { MenuBarBadgeService.shared.currentBranches = branches }
                    }
                }
                .onChange(of: query) { _ in selectedIndex = 0 }
                .onChange(of: isPresented) { shown in
                    if shown { query = ""; selectedIndex = 0; focusTextField() }
                }
                .onExitCommand { isPresented = false }
            }
        }
    }

    private var resultsList: some View {
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
                                    .hoverEffect()
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
        HStack(spacing: DS.Spacing.xl) {
            Image(systemName: action.icon)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .font(DS.Font.body.medium())
                    .foregroundStyle(DS.Color.textPrimary)
                Text(action.subtitle)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            Spacer()
            if globalIdx == selectedIndex {
                Image(systemName: "arrow.left")
                    .font(DS.Font.small)
                    .foregroundStyle(DS.Color.accent)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.vertical, DS.Spacing.lg)
        .background(
            globalIdx == selectedIndex
                ? DS.Color.accent.opacity(0.15)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: DS.Radius.sm)
        )
        .animation(DS.Animation.default, value: selectedIndex)
    }

    private func focusTextField() {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) else { return }

            func findField(in view: NSView) -> NSTextField? {
                for sub in view.subviews {
                    if let tf = sub as? NSTextField, tf.isEditable { return tf }
                    if let found = findField(in: sub) { return found }
                }
                return nil
            }

            if let tf = findField(in: window.contentView ?? NSView()) {
                window.makeFirstResponder(tf)
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ cat: QuickSearchCategory) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: cat.icon)
                .font(DS.Font.caption)
            Text(cat.rawValue)
                .font(DS.Font.caption.semibold())
        }
        .foregroundStyle(DS.Color.textTertiary)
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }
}
