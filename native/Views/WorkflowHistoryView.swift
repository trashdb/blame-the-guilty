import SwiftUI

struct WorkflowHistoryView: View {
    @ObservedObject var signalR: SignalRService

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .sidebar)

            VStack(alignment: .leading, spacing: 16) {
                Text("Workflow History")
                    .font(.system(size: 20, weight: .bold))

                Divider()

                if signalR.recentWorkflows.isEmpty {
                    Spacer()
                    Text("No workflows yet")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(signalR.recentWorkflows) { run in
                                WorkflowRunRow(run: run)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(width: 520, height: 500)
    }
}

struct WorkflowRunRow: View {
    let run: WorkflowRun

    var statusColor: Color {
        switch run.status {
        case "in_progress": return .orange
        case "success":     return .green
        case "failure":     return .red
        default:            return .secondary
        }
    }

    var statusIcon: String {
        switch run.status {
        case "in_progress": return "arrow.triangle.2.circlepath"
        case "success":     return "checkmark.circle.fill"
        case "failure":     return "xmark.circle.fill"
        default:            return "questionmark.circle"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .font(.system(size: 14))
                .foregroundStyle(statusColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(run.workflowName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.85))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(run.repo)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("@\(run.actor)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(run.startedAt, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let url = URL(string: run.htmlUrl) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        )
    }
}
