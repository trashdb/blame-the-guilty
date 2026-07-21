import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject private var badge = MenuBarBadgeService.shared

    var body: some View {
        Image(systemName: "flame.fill")
            .foregroundStyle(.red)
            .help(tooltip)
    }

    private var tooltip: String {
        switch badge.connectionState {
        case .disconnected: return "Blame the Guilty — Disconnected"
        case .connected:    return "Blame the Guilty — \(badge.activePRCount) active PRs"
        case .hasFailures:  return "Blame the Guilty — \(badge.failedPRCount) PR\(badge.failedPRCount == 1 ? "" : "s") failing"
        case .hasRunning:   return "Blame the Guilty — \(badge.runningWorkflowCount) workflow\(badge.runningWorkflowCount == 1 ? "" : "s") running"
        }
    }
}
