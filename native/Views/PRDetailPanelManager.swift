import SwiftUI

final class PRDetailPanelManager {
    static let shared = PRDetailPanelManager()
    private var panel: NSWindow?

    func show(pr: PullRequest, gitHubId: Int64) {
        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = PRDetailView(pr: pr, gitHubId: gitHubId)
        let hostingController = NSHostingController(rootView: view)
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
