import SwiftUI

struct ActivePRsView: View {
    let prs: [PullRequest]

    private func statusColor(for pr: PullRequest) -> Color {
        if pr.isMerged { return .purple }
        if pr.draft { return .gray }
        switch pr.mergeableState {
        case "clean": return .green
        case "blocked", "dirty", "behind", "unstable": return .red
        default: return Color.accentColor
        }
    }

    private func statusLabel(for pr: PullRequest) -> String {
        if pr.isMerged { return "MERGED" }
        if pr.draft { return "DRAFT" }
        switch pr.mergeableState {
        case "clean": return "READY"
        case "blocked", "dirty", "behind", "unstable": return "FAIL"
        default: return "WAITING"
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
                ForEach(prs) { pr in
                    Button {
                        NSWorkspace.shared.open(pr.prUrl)
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pr.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color(white: 0.85))
                                    .lineLimit(1)
                                HStack(spacing: 0) {
                                    Text(pr.repo).font(.system(size: 10)).foregroundStyle(.secondary)
                                    Text(" → ").font(.system(size: 10)).foregroundStyle(.secondary)
                                    Text(pr.baseBranch).font(.system(size: 10, design: .monospaced)).foregroundStyle(.blue)
                                }
                                .lineLimit(1)
                            }
                            Spacer()
                            let label = statusLabel(for: pr)
                            if !label.isEmpty {
                                Text(label)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(statusColor(for: pr))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(statusColor(for: pr).opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(statusColor(for: pr).opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(statusColor(for: pr).opacity(0.3), lineWidth: 1)
                    )
                }
            }
            .scrollDisabled(prs.count < 5)
            .frame(height: 210, alignment: .top)
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
    }
}
