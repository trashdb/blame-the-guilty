import ServiceManagement
import SwiftUI

@main
struct BlameTheGuiltyApp: App {
    @StateObject private var signalR = SignalRService(baseUrl: backendUrl)
    @State private var conflictWatcher: ConflictWatcherService?

    init() {
        try? SMAppService.mainApp.register()
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(signalR: signalR)
                .onAppear {
                    if conflictWatcher == nil {
                        let watcher = ConflictWatcherService(signalR: signalR)
                        watcher.start()
                        conflictWatcher = watcher
                    }
                }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.red)
                Text("Blame")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
