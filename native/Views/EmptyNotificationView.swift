import SwiftUI

struct EmptyNotificationView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "bell.slash.fill")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                Text("Last Notification")
                    .font(DS.Font.small.semibold())
                    .foregroundStyle(DS.Color.textSecondary)
                Spacer()
            }

            HStack(spacing: DS.Spacing.md) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("")
                        .font(DS.Font.body.semibold())
                        .foregroundStyle(DS.Color.textTertiary)

                    Text("No recent notifications")
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textTertiary)

                    HStack(spacing: DS.Spacing.xs) {
                        Text("")
                            .font(DS.Font.small)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }

                Spacer()
            }

            HStack {
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.sm + 1)
            .padding(.bottom, DS.Spacing.xl + 1)
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
