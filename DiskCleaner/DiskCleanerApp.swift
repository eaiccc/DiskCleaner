//
//  DiskCleanerApp.swift
//  DiskCleaner
//
//  Created by Link on 2026/6/3.
//

import SwiftUI
import SwiftData

@main
struct DiskCleanerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CleanupRecord.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            AppStore.shared.modelContainer = container
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        AppStore.shared.onLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
