import SwiftUI

struct ActivePRsView: View {
    let prs: [PullRequest]

    private func status(for pr: PullRequest) -> (label: String, color: Color) {
        if pr.isMerged { return ("MERGED", .purple) }
        if pr.draft { return ("DRAFT", .gray) }
        switch pr.ciStatus {
        case "waiting": return ("WAITING", .orange)
        case "failed":  return ("FAIL", .red)
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
                ForEach(prs) { pr in
                    let s = status(for: pr)
                    return Button {
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
                            Text(s.label)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(s.color)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(s.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .background(s.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(s.color.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
            .scrollDisabled(prs.count < 5)
            .frame(height: 210, alignment: .top)
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
    }
}
