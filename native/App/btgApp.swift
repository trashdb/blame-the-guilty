//
//  btgApp.swift
//  btg
//
//  Created by Álvaro López Sierra on 05/07/2026.
//

import SwiftUI

@main
struct btgApp: App {
    @StateObject private var signalR = SignalRService(baseUrl: backendUrl)

    var body: some Scene {
        MenuBarExtra("btg") {
            ContentView(signalR: signalR)
        }
        .menuBarExtraStyle(.window)
    }
}
