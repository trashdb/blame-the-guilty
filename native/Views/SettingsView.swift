import SwiftUI

struct SettingsView: View {
    var body: some View {
        ZStack {
            VisualEffectBackground(material: .sidebar)

            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.system(size: 20, weight: .bold))

                Divider()

                Button {
                    showNotification(
                        title: "Blame the Guilty",
                        body: "Test — alvaro merged a failing workflow in myorg/backend",
                        subtitle: "Run #999",
                        actionURL: URL(string: "https://github.com")
                    )
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.badge.fill")
                        Text("Send Test Notification")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)

                Spacer()
            }
            .padding(24)
        }
        .frame(width: 480, height: 400)
    }
}
