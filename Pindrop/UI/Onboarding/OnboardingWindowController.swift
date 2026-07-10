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
    private var hostingController: NSHostingController<AnyView>?
    
    func showOnboarding(
        settings: SettingsStore,
        modelManager: ModelManager,
        transcriptionService: TranscriptionService,
        permissionManager: PermissionManager,
        onComplete: @escaping () -> Void
    ) {
        guard window == nil else {
            Log.boot.info("OnboardingWindowController.showOnboarding: window already present, ordering front")
            window?.makeKeyAndOrderFront(nil)
            return
        }
        
        Log.boot.info("OnboardingWindowController.showOnboarding: creating window")
        let onboardingView = OnboardingWindow(
            settings: settings,
            modelManager: modelManager,
            transcriptionService: transcriptionService,
            permissionManager: permissionManager,
            onComplete: { [weak self] in
                self?.closeOnboarding()
                onComplete()
            },
            onPreferredContentSizeChange: { [weak self] size in
                self?.ensureWindowCanFitContentSize(size)
            }
        )
        .environment(\.locale, settings.selectedAppLocale.locale)
        
        let hosting = NSHostingController(rootView: AnyView(onboardingView))
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
        
        let onboardingSize = NSSize(width: 760, height: 560)
        window.setContentSize(onboardingSize)
        window.minSize = onboardingSize
        window.maxSize = onboardingSize
        applyInterfaceLayoutDirection(to: window, locale: settings.selectedAppLocale.locale)
        
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Log.boot.info("OnboardingWindowController.showOnboarding: window visible")
    }

    private func ensureWindowCanFitContentSize(_ preferredSize: CGSize) {
        // U9 onboarding is deliberately fixed-size; retain the callback seam for callers.
        _ = preferredSize
    }
    
    func closeOnboarding() {
        Log.boot.info("OnboardingWindowController.closeOnboarding")
        window?.close()
        window = nil
        hostingController = nil
    }
    
    var isShowingOnboarding: Bool {
        window != nil && window?.isVisible == true
    }
}
