import SwiftUI

final class DailyNoteManager {
    static let shared = DailyNoteManager()
    private var panel: NSWindow?

    func show(gitHubId: Int64, backendUrl: String) {
        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = DailyNotesView(gitHubId: gitHubId, backendUrl: backendUrl) {
            DailyNoteManager.shared.close()
        }
        let hostingController = NSHostingController(rootView: view)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.contentViewController = hostingController
        w.title = "Daily Notes"
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
