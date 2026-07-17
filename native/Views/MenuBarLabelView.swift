import SwiftUI

enum MenuBarWidgetMode: String, CaseIterable {
    case minimal = "Minimal"
    case badge = "Badge"
    case counts = "Counts"
    case full = "Full"
}

struct MenuBarLabelView: View {
    @ObservedObject private var badge = MenuBarBadgeService.shared
    @AppStorage("menuBarWidgetMode") private var widgetMode = MenuBarWidgetMode.minimal.rawValue

    var body: some View {
        switch MenuBarWidgetMode(rawValue: widgetMode) ?? .minimal {
        case .minimal:
            Image(systemName: "flame.fill")
                .foregroundStyle(.red)
        default:
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.red)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
    }

    private var label: String {
        switch MenuBarWidgetMode(rawValue: widgetMode) ?? .minimal {
        case .minimal:
            return "Blame"
        case .badge:
            let parts: [String] = [
                badge.failedPRCount > 0 ? "\(badge.failedPRCount) ✗" : nil,
                badge.runningWorkflowCount > 0 ? "\(badge.runningWorkflowCount) ⟳" : nil,
            ].compactMap { $0 }
            if parts.isEmpty { return "Blame ✓" }
            return "Blame \(parts.joined(separator: " "))"
        case .counts:
            let total = badge.activePRCount
            return "Blame (\(total))"
        case .full:
            let parts: [String] = [
                badge.activePRCount > 0 ? "\(badge.activePRCount) PRs" : nil,
                badge.failedPRCount > 0 ? "\(badge.failedPRCount) ✗" : nil,
                badge.readyCount > 0 && badge.failedPRCount == 0 ? "\(badge.readyCount) ✓" : nil,
                badge.runningWorkflowCount > 0 ? "\(badge.runningWorkflowCount) ⟳" : nil,
            ].compactMap { $0 }
            if parts.isEmpty { return "Blame idle" }
            return "Blame \(parts.joined(separator: " "))"
        }
    }
}

#Preview {
    MenuBarLabelView()
}
