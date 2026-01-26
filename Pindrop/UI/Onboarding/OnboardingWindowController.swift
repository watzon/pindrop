//
//  OnboardingWindowController.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI
import AppKit

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private var hostingController: NSHostingController<OnboardingWindow>?
    
    func showOnboarding(
        settings: SettingsStore,
        modelManager: ModelManager,
        transcriptionService: TranscriptionService,
        permissionManager: PermissionManager,
        onComplete: @escaping () -> Void
    ) {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            return
        }
        
        let onboardingView = OnboardingWindow(
            settings: settings,
            modelManager: modelManager,
            transcriptionService: transcriptionService,
            permissionManager: permissionManager,
            onComplete: { [weak self] in
                self?.closeOnboarding()
                onComplete()
            }
        )
        
        let hosting = NSHostingController(rootView: onboardingView)
        hostingController = hosting
        
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.center()
        
        window.setContentSize(NSSize(width: 800, height: 600))
        window.minSize = NSSize(width: 800, height: 600)
        window.maxSize = NSSize(width: 800, height: 600)
        
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func closeOnboarding() {
        window?.close()
        window = nil
        hostingController = nil
    }
    
    var isShowingOnboarding: Bool {
        window != nil && window?.isVisible == true
    }
}
