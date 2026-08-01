import SwiftUI

final class WebhookLogPanelManager {
    static let shared = WebhookLogPanelManager()
    private var panel: NSPanel?

    func show(gitHubId: Int64) {
        if panel == nil {
            let hostingController = NSHostingController(rootView: WebhookLogView(gitHubId: gitHubId))
            let p = PanelFactory.makePanel(size: CGSize(width: 560, height: 500), title: "Webhook Log")
            p.contentViewController = hostingController
            panel = p
        }
        panel?.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.close()
        panel = nil
    }
}
