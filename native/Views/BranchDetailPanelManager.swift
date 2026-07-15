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

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.contentViewController = hostingController
        w.title = info.name
        w.center()
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        w.backgroundColor = NSColor.windowBackgroundColor
        w.isOpaque = true
        w.hasShadow = true
        w.hidesOnDeactivate = false
        w.makeKeyAndOrderFront(nil)
        panel = w
    }

    func close() {
        panel?.close()
        panel = nil
    }
}
