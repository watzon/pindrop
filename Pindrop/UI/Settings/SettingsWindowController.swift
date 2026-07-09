//
//  SettingsWindowController.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import AppKit
import Combine
import SwiftData
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case dictation
    case appearance
    case shortcuts
    case ai
    case advanced
    case about

    var id: String { rawValue }

    func title(locale: Locale) -> String {
        switch self {
        case .general: return localized("General", locale: locale)
        case .dictation: return localized("Dictation", locale: locale)
        case .appearance: return localized("Appearance", locale: locale)
        case .shortcuts: return localized("Shortcuts", locale: locale)
        case .ai: return localized("AI", locale: locale)
        case .advanced: return localized("Advanced", locale: locale)
        case .about: return localized("About", locale: locale)
        }
    }

    var systemIcon: String {
        switch self {
        case .general: return "gearshape"
        case .dictation: return "mic.fill"
        case .appearance: return "paintbrush"
        case .shortcuts: return "keyboard"
        case .ai: return "sparkles"
        case .advanced: return "wrench.and.screwdriver"
        case .about: return "info.circle"
        }
    }

    var accessibilityIdentifier: String {
        "settings.tab.\(rawValue)"
    }
}

/// Routes a settings tab to its grouped-form pane view.
struct SettingsPaneContent: View {
    @ObservedObject var settings: SettingsStore
    let tab: SettingsTab
    let launchAtLoginManager: LaunchAtLoginManager
    let updateService: UpdateService

    init(
        settings: SettingsStore,
        tab: SettingsTab,
        launchAtLoginManager: LaunchAtLoginManager,
        updateService: UpdateService
    ) {
        self.settings = settings
        self.tab = tab
        self.launchAtLoginManager = launchAtLoginManager
        self.updateService = updateService
    }

    @MainActor
    init(settings: SettingsStore, tab: SettingsTab) {
        self.init(
            settings: settings,
            tab: tab,
            launchAtLoginManager: LaunchAtLoginManager(),
            updateService: UpdateService()
        )
    }

    @ViewBuilder
    var body: some View {
        switch tab {
        case .general:
            GeneralSettingsView(
                settings: settings,
                launchAtLoginManager: launchAtLoginManager,
                updateService: updateService
            )
        case .dictation:
            DictationSettingsView(settings: settings)
        case .appearance:
            ThemeSettingsView(settings: settings)
        case .shortcuts:
            HotkeysSettingsView(settings: settings)
        case .ai:
            AIEnhancementSettingsView(settings: settings)
        case .advanced:
            MCPSettingsView(settings: settings)
        case .about:
            AboutSettingsView(settings: settings)
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    fileprivate enum Layout {
        static let contentWidth: CGFloat = 620
        static let minimumContentHeight: CGFloat = 420
        static let defaultContentHeight: CGFloat = 600
        static let maximumContentHeight: CGFloat = 640
        static let contentPadding: CGFloat = 24
        static let frameAutosaveName = "PindropSettings"
    }

    private let settings: SettingsStore
    private let modelContainer: ModelContainer
    private let launchAtLoginManager: LaunchAtLoginManager
    private let updateService: UpdateService
    private var tabViewController: SettingsTabViewController?
    private var settingsObservation: AnyCancellable?
    private var lastLocalizedAppLocale: AppLocale

    init(
        settings: SettingsStore,
        modelContainer: ModelContainer,
        launchAtLoginManager: LaunchAtLoginManager,
        updateService: UpdateService
    ) {
        self.settings = settings
        self.modelContainer = modelContainer
        self.launchAtLoginManager = launchAtLoginManager
        self.updateService = updateService
        self.lastLocalizedAppLocale = settings.selectedAppLocale
        super.init(window: nil)

        settingsObservation = settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.reloadLocalizedStringsIfNeeded()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(tab: SettingsTab = .general) {
        ensureWindow()
        select(tab: tab)
        reloadLocalizedStrings()

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func reloadLocalizedStrings() {
        guard let tabViewController else { return }

        let locale = settings.selectedAppLocale.locale
        for (index, tab) in SettingsTab.allCases.enumerated()
            where index < tabViewController.tabViewItems.count
        {
            let item = tabViewController.tabViewItems[index]
            let title = tab.title(locale: locale)
            item.label = title
            item.toolTip = title
            item.viewController?.title = title
        }

        updateWindowForSelectedTab()
        if let window {
            applyInterfaceLayoutDirection(to: window, locale: locale)
        }
        lastLocalizedAppLocale = settings.selectedAppLocale
    }

    private func ensureWindow() {
        guard window == nil else { return }

        let tabViewController = SettingsTabViewController()
        tabViewController.tabStyle = .toolbar
        // Empty transitions avoid a stale translucent overlay that can linger under the
        // toolbar when crossfading NSHostingController children during tab switches.
        tabViewController.transitionOptions = []
        tabViewController.onSelectionChange = { [weak self] in
            self?.updateWindowForSelectedTab()
        }

        for tab in SettingsTab.allCases {
            let rootView = SettingsPaneRoot(
                settings: settings,
                modelContainer: modelContainer,
                launchAtLoginManager: launchAtLoginManager,
                updateService: updateService,
                tab: tab
            )
            let hostingController = NSHostingController(rootView: AnyView(rootView))
            // Single size driver: SwiftUI reports preferredContentSize from the pane's
            // natural layout. Do not also hardcode preferredContentSize (that fought
            // SettingsPaneRoot's frame and left intermediate overlay frames at rest).
            hostingController.sizingOptions = [.preferredContentSize]
            hostingController.title = tab.title(locale: settings.selectedAppLocale.locale)

            let item = NSTabViewItem(viewController: hostingController)
            item.identifier = tab.accessibilityIdentifier
            item.label = tab.title(locale: settings.selectedAppLocale.locale)
            item.image = NSImage(
                systemSymbolName: tab.systemIcon,
                accessibilityDescription: item.label
            )
            item.toolTip = item.label
            tabViewController.addTabViewItem(item)
        }

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Layout.contentWidth,
                height: Layout.defaultContentHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = tabViewController
        window.toolbarStyle = .preference
        window.titleVisibility = .visible
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(
            width: Layout.contentWidth,
            height: Layout.minimumContentHeight
        )
        window.contentMaxSize = NSSize(
            width: Layout.contentWidth,
            height: Layout.maximumContentHeight
        )
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        if !window.setFrameUsingName(Layout.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Layout.frameAutosaveName)
        applyInterfaceLayoutDirection(to: window, locale: settings.selectedAppLocale.locale)

        self.tabViewController = tabViewController
        self.window = window
        updateWindowForSelectedTab()
    }

    private func select(tab: SettingsTab) {
        guard let tabViewController,
              let index = SettingsTab.allCases.firstIndex(of: tab)
        else { return }

        tabViewController.selectedTabViewItemIndex = index
        updateWindowForSelectedTab()
    }

    private func updateWindowForSelectedTab() {
        guard let tabViewController,
              SettingsTab.allCases.indices.contains(tabViewController.selectedTabViewItemIndex)
        else { return }

        let tab = SettingsTab.allCases[tabViewController.selectedTabViewItemIndex]
        window?.title = tab.title(locale: settings.selectedAppLocale.locale)
    }

    private func reloadLocalizedStringsIfNeeded() {
        guard settings.selectedAppLocale != lastLocalizedAppLocale else { return }
        reloadLocalizedStrings()
    }
}

private final class SettingsTabViewController: NSTabViewController {
    var onSelectionChange: (() -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        onSelectionChange?()
    }
}

private struct SettingsPaneRoot: View {
    @ObservedObject var settings: SettingsStore
    let modelContainer: ModelContainer
    let launchAtLoginManager: LaunchAtLoginManager
    let updateService: UpdateService
    let tab: SettingsTab

    var body: some View {
        SettingsPaneContent(
            settings: settings,
            tab: tab,
            launchAtLoginManager: launchAtLoginManager,
            updateService: updateService
        )
        // Fixed width only; height comes from Form content so preferredContentSize
        // reflects the pane. Window contentMin/MaxSize clamp the host to 420…640.
        .frame(width: SettingsWindowController.Layout.contentWidth)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.locale, settings.selectedAppLocale.locale)
        .environment(\.layoutDirection, settings.selectedAppLocale.layoutDirection)
        .modelContainer(modelContainer)
    }
}
