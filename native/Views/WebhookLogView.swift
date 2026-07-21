import SwiftUI

struct WebhookLogView: View {
    let gitHubId: Int64

    @State private var logs: [WebhookLogEntry] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .sidebar)

            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                HStack {
                    Text("Webhook Event Log")
                        .font(DS.Font.largeTitle)
                    Spacer()
                    actionButton("Refresh", color: .blue) { loadLogs() }
                }

                Divider()

                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else if let error {
                    Spacer()
                    Text(error)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.destructive)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else if logs.isEmpty {
                    emptyState("No webhook events yet", icon: "antenna.radiowaves.left.and.right")
                } else {
                    ScrollView {
                        LazyVStack(spacing: DS.Spacing.xs) {
                            ForEach(logs) { entry in
                                WebhookLogRow(entry: entry)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(DS.Spacing.xxl)
        }
        .frame(width: 560, height: 500)
        .onAppear(perform: loadLogs)
        .closeOnEscape { WebhookLogPanelManager.shared.close() }
        .closeOnCmdW { WebhookLogPanelManager.shared.close() }
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

    var outcomeColor: SwiftUI.Color {
        switch entry.outcome {
        case "processed": return DS.Color.success
        case "ignored":   return DS.Color.warning
        default:          return DS.Color.textTertiary
        }
    }

    var body: some View {
        HStack(spacing: DS.Spacing.lg) {
            Circle()
                .fill(outcomeColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(entry.eventType)
                        .font(DS.Font.mono(10).semibold())
                        .foregroundStyle(DS.Color.textPrimary)
                    if let action = entry.action {
                        Text(action)
                            .font(DS.Font.mono(10))
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    if let repo = entry.repo {
                        Text(shortRepo(repo))
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
                HStack(spacing: DS.Spacing.xs) {
                    if let name = entry.workflowName {
                        Text(name)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                            .lineLimit(1)
                    }
                    if let msg = entry.message {
                        Text(msg)
                            .font(DS.Font.mono(9))
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
            }

            Spacer()

            Text(entry.outcome)
                .font(DS.Font.tiny.bold())
                .foregroundStyle(outcomeColor)
                .padding(.horizontal, DS.Spacing.xs)
                .padding(.vertical, 2)
                .background(outcomeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.rowBackground, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
    }
}
