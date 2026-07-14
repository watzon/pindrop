//
//  TelemetryConsentWindowController.swift
//  Pindrop
//
//  Created on 2026-07-14.
//

import AppKit
import SwiftUI

@MainActor
final class TelemetryConsentWindowController: NSObject, TelemetryConsentPresenting, NSWindowDelegate {
    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private var onResponse: ((Bool) -> Void)?
    private var didRespond = false

    func showConsent(
        settings: SettingsStore,
        onResponse: @escaping (Bool) -> Void
    ) {
        if let window {
            Log.ui.info("TelemetryConsentWindowController.showConsent: window already present, ordering front")
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        Log.ui.infoVisible("TelemetryConsentWindowController.showConsent: creating window")
        self.onResponse = onResponse
        didRespond = false

        let consentView = TelemetryConsentView(
            settings: settings,
            onResponse: { [weak self] accepted in
                self?.respond(accepted)
            }
        )
        .environment(\.locale, settings.selectedAppLocale.locale)
        .environment(\.layoutDirection, settings.selectedAppLocale.layoutDirection)

        let hosting = NSHostingController(rootView: AnyView(consentView))
        hostingController = hosting

        let window = ConsentNSWindow(contentViewController: hosting)
        window.delegate = self
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = localized("Help improve Pindrop?", locale: settings.selectedAppLocale.locale)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        // Real close button (hover ✕, standard position) — closing means "Not now".
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let contentSize = NSSize(width: 460, height: 500)
        window.setContentSize(contentSize)
        window.minSize = contentSize
        window.maxSize = contentSize
        window.center()
        PindropThemeController.shared.apply(to: window)
        window.backgroundColor = .clear
        applyInterfaceLayoutDirection(to: window, locale: settings.selectedAppLocale.locale)

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func respond(_ accepted: Bool) {
        guard !didRespond else { return }
        didRespond = true
        onResponse?(accepted)
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Closing without an explicit choice (Esc, ⌘W) counts as "Not now".
        if !didRespond {
            didRespond = true
            onResponse?(false)
        }
        onResponse = nil
        window = nil
        hostingController = nil
    }

    var isShowingConsent: Bool {
        window != nil && window?.isVisible == true
    }
}

private final class ConsentNSWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isCommandW(event) {
            close()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if isCommandW(event) || event.keyCode == 53 {
            close()
            return
        }

        super.keyDown(with: event)
    }

    private func isCommandW(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
            && event.charactersIgnoringModifiers?.lowercased() == "w"
    }
}
