import SwiftUI

final class PRPreviewPanelManager {
    static let shared = PRPreviewPanelManager()
    private var panel: NSWindow?

    func show(repoPath: String, branchName: String, backendUrl: String, gitHubId: Int64, onComplete: ((URL) -> Void)? = nil) {
        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = CreatePRPreviewView(
            repoPath: repoPath, branchName: branchName,
            backendUrl: backendUrl, gitHubId: gitHubId,
            onComplete: { url in
                onComplete?(url)
                self.close()
            },
            onCancel: { self.close() }
        )
        let hostingController = NSHostingController(rootView: view)
        let w = PanelFactory.makeWindow(size: CGSize(width: 460, height: 420), title: "New Pull Request", position: .topRight)
        w.contentViewController = hostingController
        w.makeKeyAndOrderFront(nil)
        panel = w
    }

    func close() {
        panel?.close()
        panel = nil
    }
}
