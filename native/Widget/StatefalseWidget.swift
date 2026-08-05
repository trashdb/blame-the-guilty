import WidgetKit
import SwiftUI

struct StatefalseWidget: Widget {
    let kind: String = "StatefalseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatefalseProvider()) { entry in
            StatefalseWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("statefalse")
        .description("Shows your PR status at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StatefalseProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatefalseEntry {
        StatefalseEntry(date: Date(), prCount: 3, status: "CI Ready", recentPR: "Fix auth bug")
    }

    func getSnapshot(in context: Context, completion: @escaping (StatefalseEntry) -> Void) {
        let entry = StatefalseEntry(date: Date(), prCount: 0, status: "Loading…", recentPR: nil)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatefalseEntry>) -> Void) {
        Task {
            let entry = await fetchEntry()
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private func fetchEntry() async -> StatefalseEntry {
        let client = LiveApiClient.fromCurrentSession()
        guard let prs = await client.fetchActivePRs() else {
            return StatefalseEntry(date: Date(), prCount: 0, status: "Offline", recentPR: nil)
        }

        let failing = prs.filter { $0.ciStatus == "failed" }.count
        let status = failing > 0 ? "\(failing) failing" : "\(prs.count) active"
        let recent = prs.first.map { "PR #\($0.prNumber): \($0.title)" }

        return StatefalseEntry(date: Date(), prCount: prs.count, status: status, recentPR: recent)
    }
}

struct StatefalseEntry: TimelineEntry {
    let date: Date
    let prCount: Int
    let status: String
    let recentPR: String?
}

struct StatefalseWidgetEntryView: View {
    var entry: StatefalseEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            Color.black
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text("statefalse")
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
    StatefalseWidget()
} timeline: {
    StatefalseEntry(date: Date(), prCount: 5, status: "CI Ready", recentPR: "Fix auth bug")
    StatefalseEntry(date: Date(), prCount: 3, status: "2 failing", recentPR: "Update deps")
}
