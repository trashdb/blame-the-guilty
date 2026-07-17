import SwiftUI
import Combine

struct NoteAnalysisItem: Decodable, Identifiable {
    var id: String { title + type }
    let type: String
    let title: String
    let description: String
    let jiraTicketTitle: String?
    let person: String?
    let actionable: Bool
    let actionUrl: String?
    let actionLabel: String?
}

struct NoteAnalysisResult: Decodable {
    let items: [NoteAnalysisItem]
    let summary: String
}

struct DailyNotesView: View {
    @State private var content: String
    @State private var analysis: NoteAnalysisResult?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var analysisId = 0
    @State private var analysisTask: Task<Void, Never>?

    let gitHubId: Int64
    let backendUrl: String
    let onClose: () -> Void

    private let fileURL: URL

    init(gitHubId: Int64, backendUrl: String, onClose: @escaping () -> Void) {
        self.gitHubId = gitHubId
        self.backendUrl = backendUrl
        self.onClose = onClose

        let base = UserDefaults.standard.string(forKey: "workspacePath") ?? TeamDefaults.workspacePath
        let path = base.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
        let notesDir = URL(fileURLWithPath: path).appendingPathComponent("notes")
        try? FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        fileURL = notesDir.appendingPathComponent("daily-\(formatter.string(from: Date())).md")

        let existing = try? String(contentsOf: fileURL, encoding: .utf8)
        _content = State(initialValue: existing ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            editorArea
            aiPanel
        }
        .frame(width: 520, height: 520)
        .onAppear {
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                analysisTask = Task {
                    await analyzeNow(text: content)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("Daily Notes")
                    .font(.system(size: 15, weight: .semibold))
                Text(formattedDate())
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isAnalyzing {
                ProgressView()
                    .scaleEffect(0.6)
                    .controlSize(.small)
            }
            if let s = analysis?.summary {
                Text(s)
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
            }
            Button("Close") { onClose() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.white.opacity(0.03))
    }

    private var editorArea: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text("Write your notes here — AI analyzes automatically")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(content.count) chars")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            TextEditor(text: $content)
                .font(.system(size: 12))
                .frame(minHeight: 160)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .scrollContentBackground(.hidden)
                .background(Color(white: 0.08))
                .onChange(of: content) { _ in
                    save()
                    analysisTask?.cancel()
                    let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard text.count >= 10 else { return }
                    analysisTask = Task {
                        do {
                            try await Task.sleep(nanoseconds: 1_500_000_000)
                            guard !Task.isCancelled else { return }
                            await analyzeNow(text: text)
                        } catch { }
                    }
                }
        }
    }

    private func analyzeNow(text: String) async {
        let currentId = analysisId + 1
        analysisId = currentId
        await MainActor.run { analysis = nil; errorMessage = nil; isAnalyzing = true }

        let url = URL(string: "\(backendUrl)/api/github/analyze-notes")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let defaults = UserDefaults.standard
        let aiKey = defaults.string(forKey: "aiApiKey") ?? ""
        let aiProvider = defaults.string(forKey: "aiProvider") ?? "openai"
        let aiModel = defaults.string(forKey: "aiModel") ?? "gpt-4o"
        var body: [String: Any] = ["content": text, "gitHubId": gitHubId]
        if !aiKey.isEmpty {
            body["apiKey"] = aiKey
            body["aiProvider"] = aiProvider
            body["model"] = aiModel
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard currentId == analysisId else { return }
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                await MainActor.run { errorMessage = "Analysis failed"; isAnalyzing = false }
                return
            }
            let result = try JSONDecoder().decode(NoteAnalysisResult.self, from: data)
            await MainActor.run { analysis = result; isAnalyzing = false; errorMessage = nil }
        } catch {
            await MainActor.run {
                guard currentId == analysisId else { return }
                errorMessage = "Could not reach analysis service"; isAnalyzing = false
            }
        }
    }

    private var aiPanel: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 10))
                    .foregroundStyle(.purple)
                Text("AI Insights")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.purple)
                Spacer()
                if let items = analysis?.items {
                    Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if isAnalyzing && analysis == nil {
                VStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Analyzing notes…")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else if let err = errorMessage {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 16))
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else if let result = analysis, !result.items.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(result.items) { item in
                            insightCard(item)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .frame(minHeight: 80, maxHeight: 180)
            } else if !isAnalyzing && content.trimmingCharacters(in: .whitespaces).count >= 10 {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.green)
                    Text("No action items detected")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(.purple.opacity(0.4))
                    Text("Start writing to get AI-powered insights")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
    }
    private func insightCard(_ item: NoteAnalysisItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconForType(item.type))
                .font(.system(size: 14))
                .foregroundStyle(colorForType(item.type))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.9))
                Text(item.description)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if item.type == "createTicket", let ticketTitle = item.jiraTicketTitle {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 8))
                        Text("Create ticket: \(ticketTitle)")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(.blue)
                    .padding(.top, 2)
                }
                if item.type == "followUp", let person = item.person {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill.questionmark")
                            .font(.system(size: 8))
                        Text("Follow up with \(person)")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
                }
            }

            Spacer()

            if item.actionable {
                Button {
                    executeAction(item)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: actionIconForType(item.type))
                            .font(.system(size: 10))
                        if let label = item.actionLabel {
                            Text(label)
                                .font(.system(size: 8))
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .help("Execute action")
            }
        }
        .padding(10)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(colorForType(item.type).opacity(0.2), lineWidth: 1)
        )
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "createTicket": return "plus.square"
        case "followUp": return "person.2"
        case "todo": return "checkmark.circle"
        default: return "doc.text"
        }
    }

    private func colorForType(_ type: String) -> Color {
        switch type {
        case "createTicket": return .blue
        case "followUp": return .orange
        case "todo": return .green
        default: return .secondary
        }
    }

    private func actionIconForType(_ type: String) -> String {
        switch type {
        case "createTicket": return "arrow.up.forward.app"
        case "followUp": return "bubble.left.and.bubble.right"
        case "todo": return "checkmark"
        default: return "chevron.right"
        }
    }

    private func executeAction(_ item: NoteAnalysisItem) {
        if let urlStr = item.actionUrl, let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
            return
        }

        switch item.type {
        case "createTicket":
            let title = item.jiraTicketTitle ?? item.title
            let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let jiraUrl = UserDefaults.standard.string(forKey: "jiraBoardUrl") ?? TeamDefaults.jiraBoardUrl
            let project = extractProjectKey()
            if let u = URL(string: "\(jiraUrl)jira/software/c/projects/\(project)/issues/?title=\(encoded)") {
                NSWorkspace.shared.open(u)
            } else if let u = URL(string: jiraUrl) {
                NSWorkspace.shared.open(u)
            }
        case "followUp":
            if let person = item.person, let encoded = person.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                if let u = URL(string: "msteams://l/chat/0/0?users=&topicName=Follow%20up%20with%20\(encoded)") {
                    NSWorkspace.shared.open(u)
                    return
                }
                if let u = URL(string: "https://teams.microsoft.com/l/chat/0/0?users=&topicName=Follow%20up%20with%20\(encoded)") {
                    NSWorkspace.shared.open(u)
                }
            }
        case "todo":
            if let title = item.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let u = URL(string: "https://google.com/search?q=\(title)") {
                NSWorkspace.shared.open(u)
            }
        default:
            if let title = item.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let u = URL(string: "https://google.com/search?q=\(title)") {
                NSWorkspace.shared.open(u)
            }
        }
    }

    private func extractProjectKey() -> String {
        let url = UserDefaults.standard.string(forKey: "jiraBoardViewUrl") ?? TeamDefaults.jiraBoardViewUrl
        if let match = try? NSRegularExpression(pattern: "/projects/([A-Z]+)/")
            .firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
           let range = Range(match.range(at: 1), in: url) {
            return String(url[range])
        }
        return "LOY"
    }

    private func formattedDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f.string(from: Date()).capitalized
    }

    private func save() {
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
