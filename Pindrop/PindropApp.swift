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
        WindowGroup(id: "placeholder") {
            EmptyView()
        }
        .defaultSize(width: 0, height: 0)
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var coordinator: AppCoordinator?
    private var settingsStore: SettingsStore?
    
    private lazy var modelContainer: ModelContainer = {
        let schema = Schema([
            TranscriptionRecord.self,
            WordReplacement.self,
            VocabularyWord.self
        ])
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
        settingsStore = coordinator?.settingsStore
        
        updateDockVisibility()
        setupMainMenu()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        
        Task { @MainActor in
            await coordinator?.start()
        }
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        
        appMenu.addItem(NSMenuItem(title: "About Pindrop", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(settingsItem)
        
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Pindrop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        mainMenu.addItem(appMenuItem)
        NSApplication.shared.mainMenu = mainMenu
    }
    
    @objc private func settingsDidChange() {
        updateDockVisibility()
    }
    
    private func updateDockVisibility() {
        let showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        NSApplication.shared.setActivationPolicy(policy)
    }
    
    @objc func openSettings(_ sender: Any?) {
        Task { @MainActor in
            coordinator?.statusBarController.showSettings()
        }
    }
}
