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
            },
            onPreferredContentSizeChange: { [weak self] size in
                self?.ensureWindowCanFitContentSize(size)
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
        
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func ensureWindowCanFitContentSize(_ preferredSize: CGSize) {
        guard let window else { return }

        let minimumSize = NSSize(width: 800, height: 600)
        let targetSize = NSSize(
            width: max(minimumSize.width, preferredSize.width),
            height: max(minimumSize.height, preferredSize.height)
        )

        let currentSize = window.contentLayoutRect.size
        guard currentSize.width < targetSize.width || currentSize.height < targetSize.height else {
            return
        }

        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetSize))
        frame.origin.x = window.frame.midX - (frame.size.width / 2)
        frame.origin.y = window.frame.maxY - frame.size.height
        window.setFrame(frame, display: true, animate: true)
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
