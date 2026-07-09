import SwiftUI

struct WebhookLogView: View {
    let gitHubId: Int64

    @State private var logs: [WebhookLogEntry] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .sidebar)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Webhook Event Log")
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                    Button("Refresh") {
                        loadLogs()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                }

                Divider()

                if isLoading {
                    Spacer()
                    ProgressView().scaleEffect(0.8).frame(maxWidth: .infinity)
                    Spacer()
                } else if let error {
                    Spacer()
                    Text(error).font(.system(size: 12)).foregroundStyle(.red).frame(maxWidth: .infinity)
                    Spacer()
                } else if logs.isEmpty {
                    Spacer()
                    Text("No webhook events yet").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(logs) { entry in
                                WebhookLogRow(entry: entry)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
        }
        .frame(width: 560, height: 500)
        .onAppear(perform: loadLogs)
    }

    private func loadLogs() {
        guard let url = URL(string: "\(backendUrl)/api/webhook/logs?limit=50") else { return }
        isLoading = true
        error = nil
        URLSession.shared.dataTask(with: url) { data, _, err in
            DispatchQueue.main.async {
                isLoading = false
                if let err {
                    error = err.localizedDescription
                    return
                }
                guard let data else { error = "No data"; return }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let decoded = try? decoder.decode([WebhookLogEntry].self, from: data) {
                    logs = decoded
                } else {
                    error = "Failed to decode"
                }
            }
        }.resume()
    }
}

struct WebhookLogRow: View {
    let entry: WebhookLogEntry

    var outcomeColor: Color {
        switch entry.outcome {
        case "processed": return .green
        case "ignored":   return .orange
        default:          return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(outcomeColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(entry.eventType)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(white: 0.85))
                    if let action = entry.action {
                        Text(action)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if let repo = entry.repo {
                        Text(shortRepo(repo))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 4) {
                    if let name = entry.workflowName {
                        Text(name)
                            .font(.system(size: 10))
                            .foregroundStyle(Color(white: 0.7))
                            .lineLimit(1)
                    }
                    if let msg = entry.message {
                        Text(msg)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Text(entry.outcome)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(outcomeColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(outcomeColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 4))
    }
}
