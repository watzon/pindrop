//
//  PindropApp.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI
import SwiftData
import AppKit

@main
struct PindropApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    
    var body: some Scene {
        WindowGroup(id: "placeholder") {
            EmptyView()
        }
        .defaultSize(width: 0, height: 0)
        .windowResizability(.contentSize)
    }
}

extension AppDelegate {
    static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var coordinator: AppCoordinator?
    private var settingsStore: SettingsStore?
    
    private var modelContainer: ModelContainer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isPreview else { return }
        
        do {
            modelContainer = try ModelContainer(
                for: TranscriptionRecord.self,
                WordReplacement.self,
                VocabularyWord.self,
                Note.self,
                migrationPlan: TranscriptionRecordMigrationPlan.self
            )
        } catch {
            Log.app.error("Failed to create ModelContainer: \(error)")
            showModelContainerErrorAlert(error: error)
            NSApplication.shared.terminate(nil)
            return
        }
        
        guard let container = modelContainer else {
            NSApplication.shared.terminate(nil)
            return
        }
        
        let context = container.mainContext
        coordinator = AppCoordinator(modelContext: context, modelContainer: container)
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
        guard !Self.isPreview else { return }
        let showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        NSApplication.shared.setActivationPolicy(policy)
    }
    
    @objc func openSettings(_ sender: Any?) {
        Task { @MainActor in
            coordinator?.statusBarController.showSettings()
        }
    }
    
    private func showModelContainerErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Database Error"
        alert.informativeText = "Failed to initialize the database: \(error.localizedDescription)\n\nThe app will now quit. Please try restarting or contact support if the problem persists."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        alert.runModal()
    }
}
