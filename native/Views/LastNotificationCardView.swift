import SwiftUI

struct LastNotificationCardView: View {
    let event: PunishmentEvent

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "flame.fill")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.destructive)
                Text("Last Notification")
                    .font(DS.Font.small.semibold())
                    .foregroundStyle(DS.Color.destructive)
                Spacer()
                Text(event.date, style: .relative)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }

            HStack(spacing: DS.Spacing.md) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("@\(event.culprit)")
                        .font(DS.Font.body.semibold())
                        .foregroundStyle(DS.Color.textPrimary)

                    if let wfName = event.workflowName {
                        Text(wfName)
                            .font(DS.Font.small)
                            .foregroundStyle(DS.Color.textSecondary)
                            .lineLimit(1)
                            .transition(.opacity)
                    }

                    HStack(spacing: DS.Spacing.xs) {
                        Text(shortRepo(event.repo))
                            .font(DS.Font.small)
                            .foregroundStyle(DS.Color.textTertiary)
                            .lineLimit(1)
                        Text("·")
                            .foregroundStyle(DS.Color.textTertiary)
                        Text("Run #\(event.runId)")
                            .font(DS.Font.mono(10))
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }

                Spacer()
            }

            if let url = event.workflowURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "arrow.up.right")
                            .font(DS.Font.caption)
                        Text("Open in GitHub")
                            .font(DS.Font.small.medium())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm + 1)
                    .background(DS.Color.cardBackground, in: RoundedRectangle(cornerRadius: DS.Radius.sm + 1))
                    .foregroundStyle(DS.Color.textPrimary)
                }
                .buttonStyle(.plain)
                .hoverEffect()
                .cursor(.pointingHand)
                .help("Open this workflow run in GitHub")
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, DS.Spacing.xl + 1)
        .padding(.vertical, DS.Spacing.lg + 1)
        .background(DS.Color.cardBackground, in: RoundedRectangle(cornerRadius: DS.Radius.lg + 1))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg + 1)
                .stroke(DS.Color.divider, lineWidth: 1)
        )
    }
}
