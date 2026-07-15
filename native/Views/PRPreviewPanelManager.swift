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

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.contentViewController = hostingController
        w.title = "Create Pull Request"
        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            let x = sf.maxX - w.frame.width - 40
            let y = sf.maxY - w.frame.height - 40
            w.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            w.center()
        }
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
