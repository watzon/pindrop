//
//  PindropApp.swift
//  Pindrop
//
//  Created on 1/25/26.
//

import SwiftUI
import SwiftData

@main
struct PindropApp: App {
    
    @State private var coordinator: AppCoordinator?
    
    let modelContainer: ModelContainer = {
        let schema = Schema([TranscriptionRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        MenuBarExtra {
            EmptyView()
                .onAppear {
                    if coordinator == nil {
                        let context = modelContainer.mainContext
                        coordinator = AppCoordinator(modelContext: context)
                        Task {
                            await coordinator?.start()
                        }
                    }
                }
        } label: {
            Image(systemName: "mic.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
