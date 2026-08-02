import ServiceManagement
import SwiftUI

@main
struct StatefalseApp: App {
    @StateObject private var signalR: SignalRService
    private let deps: Dependencies

    init() {
        try? SMAppService.mainApp.register()
        ProcessInfo.processInfo.disableAutomaticTermination("Menu bar icon must stay visible")

        let signalR = SignalRService(baseUrl: backendUrl)
        _signalR = StateObject(wrappedValue: signalR)
        deps = Dependencies.live(signalRService: signalR)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(signalR: signalR)
                .environment(\.dependencies, deps)
                .onAppear {
                    if conflictWatcher == nil {
                        let watcher = ConflictWatcherService(signalR: signalR, gitService: deps.gitService)
                        watcher.start()
                        conflictWatcher = watcher
                    }
                }
        } label: {
            MenuBarLabelView()
        }
        .menuBarExtraStyle(.window)
    }

    @State private var conflictWatcher: ConflictWatcherService?
}
