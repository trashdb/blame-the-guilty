import SwiftUI

final class BranchDetailPanelManager {
    static let shared = BranchDetailPanelManager()
    private var panel: NSWindow?

    func show(info: BranchInfo, gitHubId: Int64, backendUrl: String, onCheckout: (() -> Void)?) {
        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = BranchDetailView(
            info: info, gitHubId: gitHubId, backendUrl: backendUrl,
            onCheckout: onCheckout
        )
        let hostingController = NSHostingController(rootView: view)
        let w = PanelFactory.makeWindow(size: CGSize(width: 320, height: 240), title: "Branch")
        w.contentViewController = hostingController
        w.makeKeyAndOrderFront(nil)
        panel = w
    }

    func close() {
        panel?.close()
        panel = nil
    }
}
