import SwiftUI

struct SettingsView: View {
    @AppStorage("workspacePath") private var workspacePath: String = {
        NSHomeDirectory() + "/Desktop/dev"
    }()
    @State private var pathDraft = ""

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .sidebar)

            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.system(size: 20, weight: .bold))

                Divider()

                Group {
                    Text("Workspace Path")
                        .font(.system(size: 13, weight: .medium))
                    Text("Local git repos are discovered recursively under this directory.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.top, -8)
                    HStack(spacing: 6) {
                        TextField("e.g. ~/Desktop/dev", text: $pathDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.white.opacity(0.1), lineWidth: 1)
                            )
                            .onAppear { pathDraft = workspacePath }
                        Button("Save") {
                            workspacePath = pathDraft
                            SettingsPanelManager.shared.close()
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(.green.opacity(0.3), lineWidth: 1)
                        )
                        .buttonStyle(.plain)
                        .cursor(.pointingHand)
                    }
                }

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
