import SwiftUI

final class SettingsPanelManager {
    static let shared = SettingsPanelManager()
    private var panel: NSPanel?
    var gitHubId: Int64 = 0
    var backendUrl: String = ""

    func show() {
        if panel == nil {
            let hostingController = NSHostingController(rootView: SettingsView(gitHubId: gitHubId, backendUrl: backendUrl))
            let p = PanelFactory.makePanel(size: CGSize(width: 540, height: 400), title: "Settings")
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
