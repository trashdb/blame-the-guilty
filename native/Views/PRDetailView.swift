import SwiftUI

struct PRDetailView: View {
    let pr: PullRequest

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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Button {
                    NSWorkspace.shared.open(pr.prUrl)
                } label: {
                    Label("Open on GitHub", systemImage: "arrow.up.right.square")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)
            }

            let s = status(for: pr)
            HStack(spacing: 8) {
                Text(s.label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(s.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(s.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                Spacer()
            }

            Text(pr.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(white: 0.9))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                Text(shortRepo(pr.repo))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("→")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text(pr.baseBranch)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 4) {
                Text("head:")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(pr.headBranch)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text("PR #\(pr.prNumber)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(16)
        .frame(width: 280, height: 200)
    }
}
