import SwiftUI

struct LastNotificationCardView: View {
    let event: PunishmentEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                Text("Last Notification")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
                Spacer()
                Text(event.date, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("@\(event.culprit)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(white: 0.85))

                    if let wfName = event.workflowName {
                        Text(wfName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        Text(event.repo)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("Run #\(event.runId)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }

            if let url = event.workflowURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                        Text("Open in GitHub")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(Color(white: 0.85))
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}
