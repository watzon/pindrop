//
//  PindropApp.swift
//  Pindrop
//
//  Created on 1/25/26.
//

import SwiftUI
import SwiftData
import AppKit

@main
struct PindropApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var coordinator: AppCoordinator?
    
    private lazy var modelContainer: ModelContainer = {
        let schema = Schema([TranscriptionRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let context = modelContainer.mainContext
        coordinator = AppCoordinator(modelContext: context, modelContainer: modelContainer)
        Task { @MainActor in
            await coordinator?.start()
        }
    }
}
