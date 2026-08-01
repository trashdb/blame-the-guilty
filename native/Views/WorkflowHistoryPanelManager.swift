import SwiftUI

final class WorkflowHistoryPanelManager {
    static let shared = WorkflowHistoryPanelManager()
    private var panel: NSPanel?

    func show(signalR: SignalRService, gitHubId: Int64) {
        if panel == nil {
            let hostingController = NSHostingController(rootView: WorkflowHistoryView(signalR: signalR, gitHubId: gitHubId))
            let p = PanelFactory.makePanel(size: CGSize(width: 600, height: 500), title: "Workflow History")
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
