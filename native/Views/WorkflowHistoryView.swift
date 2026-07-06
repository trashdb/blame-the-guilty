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
                    if let target = run.targetGitHubId, target != 0 {
                        Text("→ target #\(String(target))")
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
                        showTargetPicker.toggle()
                    } label: {
                        Image(systemName: run.targetGitHubId != nil ? "person.fill.badge.plus" : "person.badge.plus")
                            .font(.system(size: 10))
                            .foregroundStyle(.purple)
                            .padding(6)
                            .background(.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                    .help("Assign notification target")
                    .popover(isPresented: $showTargetPicker) {
                        targetPickerPopover
                    }
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Notify on completion")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            if loadingUsers {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(8)
            } else {
                ForEach(users) { user in
                    Button {
                        assignTarget(user.gitHubId)
                        showTargetPicker = false
                    } label: {
                        HStack(spacing: 6) {
                            Text(user.login)
                                .font(.system(size: 12))
                            if user.gitHubId == run.targetGitHubId {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.purple)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            user.gitHubId == run.targetGitHubId
                                ? .purple.opacity(0.1)
                                : .clear,
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                }

                if users.isEmpty {
                    Text("No other users registered")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(8)
                }
            }

            Divider()

            Button("Clear target") {
                assignTarget(nil)
                showTargetPicker = false
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            .cursor(.pointingHand)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .padding(10)
        .frame(width: 180)
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

    private func assignTarget(_ targetId: Int64?) {
        guard let url = URL(string: "\(backendUrl)/api/workflows/runs/\(run.runId)/target") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any?] = ["targetGitHubId": targetId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard error == nil, data != nil else { return }
            DispatchQueue.main.async {
                signalR.setTargetGitHubId(for: run.runId, targetId: targetId)
            }
        }.resume()
    }
}
