import SwiftUI

final class SettingsPanelManager {
    static let shared = SettingsPanelManager()
    private var panel: NSPanel?
    var token: String?
    var backendUrl: String = ""

    func show() {
        if panel == nil {
            let hostingController = NSHostingController(rootView: SettingsView(token: token, backendUrl: backendUrl))
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
