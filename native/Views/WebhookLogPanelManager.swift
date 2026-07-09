import SwiftUI

final class WebhookLogPanelManager {
    static let shared = WebhookLogPanelManager()
    private var panel: NSPanel?

    func show(gitHubId: Int64) {
        if panel == nil {
            let hostingController = NSHostingController(rootView: WebhookLogView(gitHubId: gitHubId))

            panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            panel?.contentViewController = hostingController
            panel?.title = "Webhook Log"
            panel?.center()
            panel?.level = .floating
            panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel?.isReleasedWhenClosed = false
            panel?.backgroundColor = .clear
            panel?.isOpaque = false
            panel?.hasShadow = true
        }

        panel?.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.close()
        panel = nil
    }
}
