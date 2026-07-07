import SwiftUI

struct WorkflowHistoryView: View {
    @ObservedObject var signalR: SignalRService
    let gitHubId: Int64

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .sidebar)

            VStack(alignment: .leading, spacing: 16) {
                Text("Workflow History")
                    .font(.system(size: 20, weight: .bold))

                Divider()

                if signalR.recentWorkflows.isEmpty {
                    Spacer()
                    Text("No workflows yet")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    GeometryReader { geo in
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(signalR.recentWorkflows) { run in
                                    WorkflowRunRow(run: run, gitHubId: gitHubId, signalR: signalR)
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(width: 520, height: 500)
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

    private var userIdToLogin: [Int64: String] {
        Dictionary(uniqueKeysWithValues: users.map { ($0.gitHubId, $0.login) })
    }

    var statusColor: Color {
        switch run.status {
        case "in_progress": return .orange
        case "success":     return .green
        case "failure":     return .red
        default:            return .secondary
        }
    }

    var statusIcon: String {
        switch run.status {
        case "in_progress": return "arrow.triangle.2.circlepath"
        case "success":     return "checkmark.circle.fill"
        case "failure":     return "xmark.circle.fill"
        default:            return "questionmark.circle"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .font(.system(size: 14))
                .foregroundStyle(statusColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(run.workflowName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.85))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(run.repo)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("@\(run.actor)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    if !run.targetGitHubIds.isEmpty {
                        let names = run.targetGitHubIds.compactMap { userIdToLogin[$0] }
                        Text("→ \(names.joined(separator: ", "))")
                            .font(.system(size: 10))
                            .foregroundStyle(.purple)
                    }
                    Text(run.startedAt, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                if run.isRunning {
                    Button {
                        loadUsers()
                        selectedIds = Set(run.targetGitHubIds)
                        showTargetPicker.toggle()
                    } label: {
                        Image(systemName: run.targetGitHubIds.isEmpty ? "person.badge.plus" : "person.fill.badge.plus")
                            .font(.system(size: 10))
                            .foregroundStyle(.purple)
                            .padding(6)
                            .background(.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
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
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                            .padding(6)
                            .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                    .help("Rerun workflow")
                }

                if let url = URL(string: run.htmlUrl) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var targetPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Notify on completion")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            if loadingUsers {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                if users.isEmpty {
                    Text("No other users registered")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    ForEach(users) { user in
                        Button {
                            if selectedIds.contains(user.gitHubId) {
                                selectedIds.remove(user.gitHubId)
                            } else {
                                selectedIds.insert(user.gitHubId)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selectedIds.contains(user.gitHubId) ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 11))
                                    .foregroundStyle(selectedIds.contains(user.gitHubId) ? Color.purple : Color.secondary)
                                Text(user.login)
                                    .font(.system(size: 12))
                                    .foregroundStyle(selectedIds.contains(user.gitHubId) ? .primary : Color(white: 0.85))
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                selectedIds.contains(user.gitHubId)
                                    ? .purple.opacity(0.1)
                                    : .white.opacity(0.03),
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(.plain)
                        .cursor(.pointingHand)
                    }
                }
            }

            Divider()
                .padding(.horizontal, 8)

            HStack(spacing: 0) {
                Button("Clear") {
                    selectedIds = []
                    saveTargets()
                    showTargetPicker = false
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .cursor(.pointingHand)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Spacer()

                Button("Done") {
                    saveTargets()
                    showTargetPicker = false
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.purple)
                .buttonStyle(.plain)
                .cursor(.pointingHand)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 220)
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
        guard let url = URL(string: "\(backendUrl)/api/workflows/runs/\(run.runId)/rerun?gitHubId=\(gitHubId)") else {
            print("Rerun: invalid URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Rerun failed: \(error.localizedDescription)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                print("Rerun status: \(httpResponse.statusCode)")
                if let data = data, let body = String(data: data, encoding: .utf8) {
                    print("Rerun body: \(body)")
                }
            }
        }.resume()
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
