import Combine
import SwiftUI

struct CachedBranch {
    let name: String
    let repoPath: String
    let repoName: String
    let ticketNumber: String?
}

enum MenuBarConnectionState {
    case disconnected, connected, hasFailures, hasRunning
}

class MenuBarBadgeService: ObservableObject {
    static let shared = MenuBarBadgeService()

    @Published var activePRCount = 0
    @Published var failedPRCount = 0
    @Published var runningWorkflowCount = 0
    @Published var draftCount = 0
    @Published var waitingCount = 0
    @Published var reviewCount = 0
    @Published var readyCount = 0
    @Published var mergedCount = 0
    @Published var currentBranches: [CachedBranch] = []
    @Published var connectionState: MenuBarConnectionState = .disconnected

    var iconName: String {
        switch connectionState {
        case .disconnected:  return "flame.fill"
        case .connected:     return "flame.fill"
        case .hasFailures:   return "flame.trianglebadge.exclamationmark"
        case .hasRunning:    return "flame.fill"
        }
    }

    var iconColor: SwiftUI.Color {
        switch connectionState {
        case .disconnected:  return Color(nsColor: .tertiaryLabelColor)
        case .connected:     return DS.Color.statusGreen
        case .hasFailures:   return DS.Color.statusRed
        case .hasRunning:    return DS.Color.warning
        }
    }
}
