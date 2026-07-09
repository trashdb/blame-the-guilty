import SwiftUI

final class WorkflowHistoryPanelManager {
    static let shared = WorkflowHistoryPanelManager()
    private var panel: NSPanel?

    func show(signalR: SignalRService, gitHubId: Int64) {
        if panel == nil {
            let hostingController = NSHostingController(rootView: WorkflowHistoryView(signalR: signalR, gitHubId: gitHubId))

            panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            panel?.contentViewController = hostingController
            panel?.title = "Workflow History"
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
