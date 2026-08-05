import SwiftUI

final class SettingsPanelManager {
    static let shared = SettingsPanelManager()
    private var panel: NSPanel?
    var api: ApiClientProtocol?

    func show() {
        if panel == nil, let api {
            let hostingController = NSHostingController(rootView: SettingsView(api: api))
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
