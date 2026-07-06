import SwiftUI

@main
struct btgApp: App {
    @StateObject private var signalR = SignalRService(baseUrl: backendUrl)

    var body: some Scene {
        MenuBarExtra {
            ContentView(signalR: signalR)
        } label: {
            Image(nsImage: menuBarIcon())
        }
        .menuBarExtraStyle(.window)
    }

    private func menuBarIcon() -> NSImage {
        let image = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "btg")!
        image.isTemplate = false
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed, .systemOrange])
        return image.withSymbolConfiguration(config) ?? image
    }
}
