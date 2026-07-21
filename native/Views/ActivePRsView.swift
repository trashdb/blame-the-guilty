import SwiftUI

struct ActivePRsView: View {
    let prs: [PullRequest]
    let gitHubId: Int64
    @State private var selectedPR: PullRequest?
    @State private var optimisticDrafts: [String: Bool] = [:]
    @State private var searchQuery = ""
    @State private var selectedRepo: String? = nil
    @State private var selectedStatus: PRFilterStatus = .all

    private var repos: [String] {
        Array(Set(prs.map(\.repo))).sorted()
    }

    private var filteredPRs: [PullRequest] {
        var result = prs

        // Search
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q) ||
                $0.repo.lowercased().contains(q) ||
                $0.baseBranch.lowercased().contains(q)
            }
        }

        // Repo
        if let repo = selectedRepo {
            result = result.filter { $0.repo == repo }
        }

        // Status
        switch selectedStatus {
        case .all:      break
        case .ready:    result = result.filter { $0.ciStatus == "ready" || $0.ciStatus == "" }
        case .waiting:  result = result.filter { $0.ciStatus == "waiting" }
        case .fail:     result = result.filter { $0.ciStatus == "failed" || $0.conclusion == "failure" }
        case .draft:    result = result.filter { $0.draft }
        }

        return result
    }

    private func status(for pr: PullRequest) -> (label: String, color: Color) {
        let draft = optimisticDrafts[pr.id] ?? pr.draft
        return (DS.Color.statusLabel(for: pr, draft: draft),
                DS.Color.statusColor(for: pr, draft: draft))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            sectionHeader("Active PRs (\(filteredPRs.count))")

            // Search field
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                TextField("Search PRs...", text: $searchQuery)
                    .font(DS.Font.mono(12))
                    .textFieldStyle(.plain)
                    .foregroundStyle(DS.Color.textPrimary)
                    .help("Filter PRs by title, repo, or branch")
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Color.fieldBackground, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(DS.Color.divider, lineWidth: 1)
            )

            // Repo picker
            if repos.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.xs) {
                        repoPill(name: "All", isSelected: selectedRepo == nil) {
                            withAnimation(DS.Animation.hover) { selectedRepo = nil }
                        }
                        ForEach(repos.prefix(6), id: \.self) { repo in
                            repoPill(name: shortRepo(repo), isSelected: selectedRepo == repo) {
                                withAnimation(DS.Animation.hover) { selectedRepo = repo }
                            }
                        }
                        if repos.count > 6 {
                            Text("+\(repos.count - 6)")
                                .font(DS.Font.tiny)
                                .foregroundStyle(DS.Color.textTertiary)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.xs)
                }
            }

            // Status picker
            Picker("Status", selection: $selectedStatus) {
                Text("All").tag(PRFilterStatus.all)
                Text("Ready").tag(PRFilterStatus.ready)
                Text("Waiting").tag(PRFilterStatus.waiting)
                Text("Fail").tag(PRFilterStatus.fail)
                Text("Draft").tag(PRFilterStatus.draft)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
            .cursor(.pointingHand)

            // Results (fixed height area)
            ScrollView {
                LazyVStack(spacing: DS.Spacing.sm) {
                    if filteredPRs.isEmpty {
                        VStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "tray")
                                .font(.title2)
                                .foregroundStyle(DS.Color.textTertiary)
                            Text("No PRs match your filters")
                                .font(DS.Font.small)
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.xl)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        ForEach(filteredPRs) { pr in
                            PRCardRow(
                                pr: pr,
                                status: status(for: pr),
                                isPresented: Binding(
                                    get: { selectedPR?.id == pr.id },
                                    set: { if !$0 { selectedPR = nil } }
                                ),
                                action: { selectedPR = pr },
                                popover: PRDetailView(
                                    pr: pr,
                                    gitHubId: gitHubId,
                                    optimisticDraft: optimisticDrafts[pr.id]
                                ) { newDraft in
                                    optimisticDrafts[pr.id] = newDraft
                                }
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .animation(DS.Animation.default, value: filteredPRs.count)
            }
            .scrollDisabled(filteredPRs.count < 4)
            .frame(height: 180, alignment: .top)
        }
        .padding(.top, DS.Spacing.xs)
        .padding(.bottom, DS.Spacing.sm)
        .onChange(of: prs) { newPRs in
            let activeIDs = Set(newPRs.map(\.id))
            optimisticDrafts = optimisticDrafts.filter { activeIDs.contains($0.key) }
            for pr in newPRs {
                if optimisticDrafts[pr.id] == pr.draft {
                    optimisticDrafts.removeValue(forKey: pr.id)
                }
            }
            if let sel = selectedPR, !activeIDs.contains(sel.id) {
                selectedPR = nil
            }
        }
    }

    @ViewBuilder
    private func repoPill(name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name)
                .font(DS.Font.tiny.bold())
                .foregroundStyle(isSelected ? DS.Color.accent : DS.Color.textSecondary)
                .padding(.horizontal, DS.Spacing.sm + 2)
                .padding(.vertical, DS.Spacing.xs)
                .background(
                    isSelected
                    ? DS.Color.accent.opacity(0.12)
                    : DS.Color.fieldBackground,
                    in: RoundedRectangle(cornerRadius: DS.Radius.sm)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .stroke(isSelected ? DS.Color.accent.opacity(0.3) : DS.Color.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .cursor(.pointingHand)
        .help("Filter by repository: \(name)")
    }
}

enum PRFilterStatus: String, CaseIterable {
    case all, ready, waiting, fail, draft
}

// MARK: - Individual PR Card Row
private struct PRCardRow<PopoverContent: View>: View {
    let pr: PullRequest
    let status: (label: String, color: Color)
    @Binding var isPresented: Bool
    let action: () -> Void
    let popover: PopoverContent

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.lg) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(pr.title)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 0) {
                        Text(shortRepo(pr.repo))
                            .font(DS.Font.small)
                            .foregroundStyle(DS.Color.textSecondary)
                        Text(" → ")
                            .font(DS.Font.small)
                            .foregroundStyle(DS.Color.textTertiary)
                        Text(pr.baseBranch)
                            .font(DS.Font.mono(10))
                            .foregroundStyle(DS.Color.accent)
                    }
                    .lineLimit(1)
                }

                Spacer()

                Text(status.label)
                    .font(DS.Font.tiny.bold())
                    .foregroundStyle(status.color)
                    .padding(.horizontal, DS.Spacing.sm + 1)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(DS.Color.badgeBackground(status.color),
                                in: RoundedRectangle(cornerRadius: DS.Radius.sm))
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(isHovering
                          ? DS.Color.badgeBackground(status.color).opacity(1.1)
                          : DS.Color.badgeBackground(status.color))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(DS.Color.badgeBorder(status.color), lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
        .onHover { hovering in
            withAnimation(DS.Animation.hover) {
                isHovering = hovering
            }
        }
        .popover(isPresented: $isPresented) {
            popover
                .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
        .animation(DS.Animation.popover, value: isPresented)
        .help("\(pr.title) — \(shortRepo(pr.repo)) → \(pr.baseBranch) (\(status.label))")
    }
}
