import SwiftUI

struct SettingsView: View {
    let gitHubId: Int64
    let backendUrl: String

    @AppStorage("workspacePath") private var workspacePath: String = {
        NSHomeDirectory() + "/Desktop/dev"
    }()
    @State private var pathDraft = ""
    @State private var patDraft = ""
    @State private var patSaved = false
    @State private var patSaving = false
    @State private var patError: String?

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

                if gitHubId > 0 {
                    Group {
                        Text("Personal Access Token")
                            .font(.system(size: 13, weight: .medium))
                        Text("Optional. Used to access org repos when OAuth is blocked. Create at github.com/settings/tokens with repo scope.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.top, -8)
                        HStack(spacing: 6) {
                            SecureField("github_pat_...", text: $patDraft)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(.white.opacity(0.1), lineWidth: 1)
                                )
                            Button {
                                Task { await savePat() }
                            } label: {
                                if patSaving {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 40)
                                } else {
                                    Text("Save")
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .stroke(.green.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                            .cursor(.pointingHand)
                            .disabled(patSaving || patDraft.isEmpty)
                        }
                        if patSaved {
                            Text("PAT saved successfully")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                        }
                        if let patError {
                            Text(patError)
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                        }
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
        .frame(width: 540, height: 440)
    }

    private func savePat() async {
        patSaving = true
        patSaved = false
        patError = nil
        defer { patSaving = false }

        guard let url = URL(string: "\(backendUrl)/api/auth/pat?gitHubId=\(gitHubId)") else {
            patError = "Invalid backend URL"
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["patToken": patDraft])

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                patSaved = true
                patDraft = ""
            } else {
                patError = "Failed to save PAT"
            }
        } catch {
            patError = error.localizedDescription
        }
    }
}
