import SwiftUI

struct WorkflowHistoryView: View {
    @ObservedObject var signalR: SignalRService
    let gitHubId: Int64

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .sidebar)

            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                Text("Workflow History")
                    .font(DS.Font.largeTitle)

                Divider()

                if signalR.recentWorkflows.isEmpty {
                    Spacer()
                    Text("No workflows yet")
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textSecondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    GeometryReader { geo in
                        ScrollView {
                            LazyVStack(spacing: DS.Spacing.xs) {
                                ForEach(signalR.recentWorkflows) { run in
                                    WorkflowRunRow(run: run, gitHubId: gitHubId, signalR: signalR)
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(DS.Spacing.xxl)
        }
        .frame(width: 600, height: 500)
    }
}

struct WorkflowRunRow: View {
    let run: WorkflowRun
    let gitHubId: Int64
    @ObservedObject var signalR: SignalRService

    @State private var showTargetPicker = false
    @State private var users: [GitHubUserInfo] = []
    @State private var loadingUsers = false
    @State private var selectedIds: Set<Int64> = []
    @State private var isRerunning = false
    @State private var rerunError: String?

    private var userIdToLogin: [Int64: String] {
        Dictionary(uniqueKeysWithValues: users.map { ($0.gitHubId, $0.login) })
    }

    var statusColor: SwiftUI.Color {
        switch run.status {
        case "in_progress":  return DS.Color.warning
        case "success":      return DS.Color.success
        case "failure":      return DS.Color.destructive
        case "cancelled":    return DS.Color.textTertiary
        case "superseded":   return DS.Color.statusYellow
        default:             return DS.Color.textTertiary
        }
    }

    var statusIcon: String {
        switch run.status {
        case "in_progress":  return "arrow.triangle.2.circlepath"
        case "success":      return "checkmark.circle.fill"
        case "failure":      return "xmark.circle.fill"
        case "cancelled":    return "xmark.circle"
        case "superseded":   return "arrow.triangle.branch"
        default:             return "questionmark.circle"
        }
    }

    var body: some View {
        HStack(spacing: DS.Spacing.section) {
            Image(systemName: statusIcon)
                .font(.system(size: 16))
                .foregroundStyle(statusColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(run.workflowName)
                    .font(DS.Font.title)
                    .foregroundStyle(DS.Color.textPrimary)

                if let prNumber = run.prNumber {
                    HStack(spacing: DS.Spacing.xs) {
                        Text("PR #\(prNumber)")
                            .font(DS.Font.small.medium())
                            .foregroundStyle(DS.Color.accent)
                        if let prTitle = run.prTitle {
                            Text(prTitle)
                                .font(DS.Font.small)
                                .foregroundStyle(DS.Color.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                HStack(spacing: DS.Spacing.md) {
                    if let trigger = run.trigger {
                        Text(trigger.replacingOccurrences(of: "_", with: " "))
                            .font(DS.Font.small)
                            .foregroundStyle(DS.Color.textTertiary)
                        Text("·")
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                    Text(shortRepo(run.repo))
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.textTertiary)
                    Text("·")
                        .foregroundStyle(DS.Color.textTertiary)
                    Text("@\(run.actor)")
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.textTertiary)
                }

                HStack(spacing: DS.Spacing.md) {
                    if !run.targetGitHubIds.isEmpty {
                        let names = run.targetGitHubIds.compactMap { userIdToLogin[$0] }
                        Text("→ \(names.joined(separator: ", "))")
                            .font(DS.Font.small)
                            .foregroundStyle(DS.Color.statusPurple)
                        Text("·")
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                    if run.isRunning {
                        Text(run.startedAt, style: .relative)
                            .font(DS.Font.small)
                            .foregroundStyle(DS.Color.textTertiary)
                    } else if let duration = run.duration {
                        Text(durationString(from: duration))
                            .font(DS.Font.mono(11))
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }
            }

            Spacer()

            VStack(spacing: DS.Spacing.xs) {
                if run.isRunning {
                    Button {
                        loadUsers()
                        selectedIds = Set(run.targetGitHubIds)
                        showTargetPicker.toggle()
                    } label: {
                        Image(systemName: run.targetGitHubIds.isEmpty ? "person.badge.plus" : "person.fill.badge.plus")
                            .font(DS.Font.small)
                            .foregroundStyle(DS.Color.statusPurple)
                            .padding(DS.Spacing.md)
                            .background(DS.Color.statusPurple.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                    .help("Assign notification targets")
                    .popover(isPresented: $showTargetPicker) {
                        targetPickerPopover
                    }
                }

                if !run.isRunning {
                    Button {
                        rerunWorkflow()
                    } label: {
                        Group {
                            if isRerunning {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 11, height: 11)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(DS.Font.small)
                            }
                        }
                        .foregroundStyle(DS.Color.accent)
                        .padding(DS.Spacing.md)
                        .background(DS.Color.accentDim, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                    .help("Rerun workflow")
                    .disabled(isRerunning)
                }

                if let url = URL(string: run.htmlUrl) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(DS.Font.small)
                            .foregroundStyle(DS.Color.textSecondary)
                            .padding(DS.Spacing.md)
                            .background(DS.Color.rowBackground, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.xxl)
        .padding(.vertical, DS.Spacing.xl)
        .background(DS.Color.rowBackground, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.divider, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var targetPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Notify on completion")
                .font(DS.Font.title)
                .foregroundStyle(DS.Color.textPrimary)
                .padding(.horizontal, DS.Spacing.xxl)
                .padding(.vertical, DS.Spacing.xl)

            if loadingUsers {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.xxl)
            } else {
                if users.isEmpty {
                    Text("No other users registered")
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.xxl)
                } else {
                    ScrollView {
                        LazyVStack(spacing: DS.Spacing.xs) {
                            ForEach(users) { user in
                                userRow(user)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                    }
                    .frame(maxHeight: 200)
                }
            }

            Divider()
                .padding(.horizontal, DS.Spacing.lg)

            HStack(spacing: 0) {
                actionButton("Clear", color: DS.Color.textSecondary) {
                    selectedIds = []
                    saveTargets()
                    showTargetPicker = false
                }

                Spacer()

                solidButton("Done", color: DS.Color.statusPurple) {
                    saveTargets()
                    showTargetPicker = false
                }
            }
            .padding(.horizontal, DS.Spacing.xxl)
            .padding(.vertical, DS.Spacing.xl)
        }
        .frame(width: 220)
    }

    private func userRow(_ user: GitHubUserInfo) -> some View {
        Button {
            if selectedIds.contains(user.gitHubId) {
                selectedIds.remove(user.gitHubId)
            } else {
                selectedIds.insert(user.gitHubId)
            }
        } label: {
            HStack(spacing: DS.Spacing.lg) {
                Image(systemName: selectedIds.contains(user.gitHubId) ? "checkmark.square.fill" : "square")
                    .font(DS.Font.small)
                    .foregroundStyle(selectedIds.contains(user.gitHubId) ? DS.Color.statusPurple : DS.Color.textSecondary)
                Text(user.login)
                    .font(DS.Font.body)
                    .foregroundStyle(selectedIds.contains(user.gitHubId) ? DS.Color.textPrimary : DS.Color.textSecondary)
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.xxl)
            .padding(.vertical, DS.Spacing.lg)
            .background(
                selectedIds.contains(user.gitHubId)
                    ? DS.Color.statusPurple.opacity(0.08)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: DS.Radius.sm)
            )
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }

    private func loadUsers() {
        guard let url = URL(string: "\(backendUrl)/api/users") else { return }
        loadingUsers = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            loadingUsers = false
            guard let data = data,
                  let decoded = try? JSONDecoder().decode([GitHubUserInfo].self, from: data) else { return }
            DispatchQueue.main.async {
                users = decoded.filter { $0.gitHubId != gitHubId }
            }
        }.resume()
    }

    private func rerunWorkflow() {
        guard let url = URL(string: "\(backendUrl)/api/workflows/runs/\(run.runId)/rerun?gitHubId=\(gitHubId)") else { return }
        isRerunning = true
        rerunError = nil
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isRerunning = false
                if let error = error {
                    self.rerunError = error.localizedDescription
                    return
                }
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        Task { await signalR.syncFromApi(gitHubId: gitHubId) }
                    } else {
                        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                        self.rerunError = "HTTP \(httpResponse.statusCode): \(body)"
                    }
                }
            }
        }.resume()
    }

    private func durationString(from interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? ""
    }

    private func saveTargets() {
        let ids = Array(selectedIds)
        guard let dbId = run.dbId else { return }
        guard let url = URL(string: "\(backendUrl)/api/workflows/runs/\(dbId)/target") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["targetGitHubIds": ids]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard error == nil, data != nil else { return }
            DispatchQueue.main.async {
                signalR.setTargetGitHubIds(for: dbId, targetIds: ids)
            }
        }.resume()
    }
}
