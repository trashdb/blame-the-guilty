import SwiftUI

final class SettingsPanelManager {
    static let shared = SettingsPanelManager()
    private var panel: NSPanel?
    var gitHubId: Int64 = 0
    var backendUrl: String = ""

    func show() {
        if panel == nil {
            let hostingController = NSHostingController(rootView: SettingsView(gitHubId: gitHubId, backendUrl: backendUrl))

            panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 440),
                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            panel?.contentViewController = hostingController
            panel?.title = "Settings"
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
