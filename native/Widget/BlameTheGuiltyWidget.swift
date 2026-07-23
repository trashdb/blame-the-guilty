import WidgetKit
import SwiftUI

struct BlameTheGuiltyWidget: Widget {
    let kind: String = "BlameTheGuiltyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BlameProvider()) { entry in
            BlameWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Blame the Guilty")
        .description("Shows your PR status at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BlameProvider: TimelineProvider {
    func placeholder(in context: Context) -> BlameEntry {
        BlameEntry(date: Date(), prCount: 3, status: "CI Ready", recentPR: "Fix auth bug")
    }

    func getSnapshot(in context: Context, completion: @escaping (BlameEntry) -> Void) {
        let entry = BlameEntry(date: Date(), prCount: 0, status: "Loading…", recentPR: nil)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BlameEntry>) -> Void) {
        Task {
            let entry = await fetchEntry()
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private func fetchEntry() async -> BlameEntry {
        let urlString = "\(TeamDefaults.backendUrl)/api/pullrequests/active?gitHubId=0"
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url) else {
            return BlameEntry(date: Date(), prCount: 0, status: "Offline", recentPR: nil)
        }

        struct PRResponse: Decodable {
            let prNumber: Int64
            let title: String
            let ciStatus: String?
        }

        guard let prs = try? JSONDecoder().decode([PRResponse].self, from: data) else {
            return BlameEntry(date: Date(), prCount: 0, status: "Error", recentPR: nil)
        }

        let failing = prs.filter { $0.ciStatus == "failed" }.count
        let status = failing > 0 ? "\(failing) failing" : "\(prs.count) active"
        let recent = prs.first.map { "PR #\($0.prNumber): \($0.title)" }

        return BlameEntry(date: Date(), prCount: prs.count, status: status, recentPR: recent)
    }
}

struct BlameEntry: TimelineEntry {
    let date: Date
    let prCount: Int
    let status: String
    let recentPR: String?
}

struct BlameWidgetEntryView: View {
    var entry: BlameEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            Color.black
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.red)
                    Text("Blame the Guilty")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Text(entry.status)
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                if let recent = entry.recentPR {
                    Text(recent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                HStack {
                    Text("\(entry.prCount) PRs")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
}

#Preview(as: .systemSmall) {
    BlameTheGuiltyWidget()
} timeline: {
    BlameEntry(date: Date(), prCount: 5, status: "CI Ready", recentPR: "Fix auth bug")
    BlameEntry(date: Date(), prCount: 3, status: "2 failing", recentPR: "Update deps")
}
