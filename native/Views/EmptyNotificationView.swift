import SwiftUI

struct EmptyNotificationView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("Last Notification")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)

                    Text("No recent notifications")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 4) {
                        Text("")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }

            HStack {
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.bottom, 12)
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
