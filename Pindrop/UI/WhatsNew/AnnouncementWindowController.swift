//
//  AnnouncementWindowController.swift
//  Pindrop
//
//  Created on 2026-07-07.
//

import AppKit
import SwiftUI

@MainActor
final class AnnouncementWindowController: NSObject, AnnouncementPresenting, NSWindowDelegate {
    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private var onDismiss: (() -> Void)?

    func showAnnouncement(
        _ announcement: Announcement,
        settings: SettingsStore,
        onDismiss: @escaping () -> Void
    ) {
        if let window {
            Log.ui.info("AnnouncementWindowController.showAnnouncement: window already present, ordering front")
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        Log.ui.infoVisible("AnnouncementWindowController.showAnnouncement: creating window id=\(announcement.id)")
        self.onDismiss = onDismiss

        let whatsNewView = WhatsNewView(
            announcement: announcement,
            settings: settings,
            onDismiss: { [weak self] in
                self?.closeAnnouncement()
            }
        )
        .environment(\.locale, settings.selectedAppLocale.locale)
        .environment(\.layoutDirection, settings.selectedAppLocale.layoutDirection)

        let hosting = NSHostingController(rootView: AnyView(whatsNewView))
        hostingController = hosting

        let window = WhatsNewNSWindow(contentViewController: hosting)
        window.delegate = self
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = localized(announcement.titleKey, locale: settings.selectedAppLocale.locale)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating

        let contentSize = NSSize(width: 520, height: 640)
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
        Log.ui.infoVisible("AnnouncementWindowController.showAnnouncement: window visible id=\(announcement.id)")
    }

    func closeAnnouncement() {
        Log.ui.info("AnnouncementWindowController.closeAnnouncement")
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        let dismissal = onDismiss
        onDismiss = nil
        window = nil
        hostingController = nil
        dismissal?()
    }

    var isShowingAnnouncement: Bool {
        window != nil && window?.isVisible == true
    }
}

private final class WhatsNewNSWindow: NSWindow {
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
