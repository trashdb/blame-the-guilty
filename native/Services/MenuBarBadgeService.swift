import Combine
import SwiftUI

struct CachedBranch {
    let name: String
    let repoPath: String
    let repoName: String
    let ticketNumber: String?
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
}
