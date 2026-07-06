import SwiftUI

@main
struct BlameTheGuiltyApp: App {
    @StateObject private var signalR = SignalRService(baseUrl: backendUrl)

    var body: some Scene {
        MenuBarExtra {
            ContentView(signalR: signalR)
        } label: {
            if let image = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "Blame the Guilty") {
                let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
                if let colored = image.withSymbolConfiguration(config) {
                    Image(nsImage: colored)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
