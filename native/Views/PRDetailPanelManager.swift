import SwiftUI

final class PRDetailPanelManager {
    static let shared = PRDetailPanelManager()
    private var panel: NSWindow?

    func show(deps: Dependencies, pr: PullRequest, gitHubId: Int64) {
        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = PRDetailView(pr: pr, gitHubId: gitHubId, deps: deps)
        let hostingController = NSHostingController(rootView: view.environment(\.dependencies, deps))
        let w = PanelFactory.makeWindow(size: CGSize(width: 380, height: 320), title: "Pull Request")
        w.contentViewController = hostingController
        w.makeKeyAndOrderFront(nil)
        panel = w
    }

    func close() {
        panel?.close()
        panel = nil
    }
}
