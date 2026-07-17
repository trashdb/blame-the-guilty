import SwiftUI

struct ActivePRsView: View {
    let prs: [PullRequest]
    let gitHubId: Int64
    @State private var selectedPR: PullRequest?
    @State private var optimisticDrafts: [String: Bool] = [:]

    private func status(for pr: PullRequest) -> (label: String, color: Color) {
        let draft = optimisticDrafts[pr.id] ?? pr.draft
        if pr.isMerged { return ("MERGED", .purple) }
        if draft { return ("DRAFT", .gray) }
        switch pr.ciStatus {
        case "waiting": return ("WAITING", .orange)
        case "failed":  return ("FAIL", .red)
        case "review":  return ("REVIEW", .blue)
        default:        return ("READY", .green)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("Active PRs (\(prs.count))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
                Spacer()
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(prs) { pr in
                        let s = status(for: pr)
                        Button {
                            selectedPR = pr
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pr.title)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color(white: 0.85))
                                        .lineLimit(1)
                                    HStack(spacing: 0) {
                                        Text(shortRepo(pr.repo)).font(.system(size: 10)).foregroundStyle(.secondary)
                                        Text(" → ").font(.system(size: 10)).foregroundStyle(.secondary)
                                        Text(pr.baseBranch).font(.system(size: 10, design: .monospaced)).foregroundStyle(.blue)
                                    }
                                    .lineLimit(1)
                                }
                                Spacer()
                                Text(s.label)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(s.color)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(s.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(s.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(s.color.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .cursor(.pointingHand)
                        .popover(item: $selectedPR) { selected in
                            if selected.id == pr.id {
                                PRDetailView(pr: pr, gitHubId: gitHubId, optimisticDraft: optimisticDrafts[pr.id]) { newDraft in
                                    optimisticDrafts[pr.id] = newDraft
                                }
                            }
                        }
                    }
                }
            }
            .scrollDisabled(prs.count < 4)
            .frame(height: 170, alignment: .top)
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
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
