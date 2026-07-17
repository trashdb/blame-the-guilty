import SwiftUI

struct ActivePRsView: View {
    let prs: [PullRequest]
    let gitHubId: Int64
    @State private var selectedPR: PullRequest?
    @State private var optimisticDrafts: [String: Bool] = [:]

    private func status(for pr: PullRequest) -> (label: String, color: Color) {
        let draft = optimisticDrafts[pr.id] ?? pr.draft
        return (DS.Color.statusLabel(for: pr, draft: draft),
                DS.Color.statusColor(for: pr, draft: draft))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            sectionHeader("Active PRs (\(prs.count))")

            ScrollView {
                LazyVStack(spacing: DS.Spacing.sm) {
                    ForEach(prs) { pr in
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
                    }
                }
            }
            .scrollDisabled(prs.count < 4)
            .frame(height: 170, alignment: .top)
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
        }
    }
}
