//
//  DotFloatingIndicator.swift
//  Pindrop
//
//  Created on 2026-04-15.
//

import SwiftUI
import AppKit

// MARK: - Layout constants (size-independent only)

private enum DotMetrics {
    /// Horizontal padding between panel edge and the pill / dot.
    static let edgeInset: CGFloat = 8
    /// Minimum gap between the dot centre and the visible screen boundary.
    static let screenInset: CGFloat = 16

    static let hoverMonitorInterval: TimeInterval = 1.0 / 60.0
    static let hoverCollapseDelay: TimeInterval = 0.18
    static let hoverActivationInset: CGFloat = 22

    static let showDuration: TimeInterval = 0.22
    static let hideDuration: TimeInterval = 0.15
}

// MARK: - Size

/// Governs ALL dimensions of the indicator — idle dot AND the expanded pill.
/// Choosing a smaller size shrinks everything, making the panel narrower so the
/// dot can be tucked further into a screen corner.
enum DotFloatingIndicatorSize: String, CaseIterable, Identifiable {
    case small  = "small"
    case medium = "medium"
    case large  = "large"

    var id: String { rawValue }

    // MARK: Idle dot

    var dotDiameter: CGFloat {
        switch self {
        case .small:  return 32
        case .medium: return 40
        case .large:  return 48
        }
    }

    var pebbleDiameter: CGFloat {
        switch self {
        case .small:  return 12
        case .medium: return 16
        case .large:  return 20
        }
    }

    // MARK: Expanded pill

    var expandedWidth: CGFloat {
        switch self {
        case .small:  return 192
        case .medium: return 256
        case .large:  return 320
        }
    }

    var expandedHeight: CGFloat {
        switch self {
        case .small:  return 40
        case .medium: return 48
        case .large:  return 56
        }
    }

    // MARK: Panel (pill + insets on each side)

    var panelWidth: CGFloat  { expandedWidth  + DotMetrics.edgeInset * 2 }
    /// Vertical inset is always 12 px on each side so the dot sits centred.
    var panelHeight: CGFloat { expandedHeight + DotMetrics.edgeInset * 2 }

    // MARK: Hover pill content

    var recordButtonDiameter: CGFloat {
        switch self {
        case .small:  return 28
        case .medium: return 34
        case .large:  return 40
        }
    }

    var recordButtonInnerDot: CGFloat {
        switch self {
        case .small:  return 11
        case .medium: return 13
        case .large:  return 16
        }
    }

    var micButtonDiameter: CGFloat {
        switch self {
        case .small:  return 22
        case .medium: return 27
        case .large:  return 32
        }
    }

    var expandedTextSize: CGFloat {
        switch self {
        case .small:  return 10
        case .medium: return 11
        case .large:  return 13
        }
    }

    var expandedHPadding: CGFloat {
        switch self {
        case .small:  return 5
        case .medium: return 7
        case .large:  return 8
        }
    }

    // MARK: Recording pill content

    var timerFontSize: CGFloat {
        switch self {
        case .small:  return 10
        case .medium: return 12
        case .large:  return 14
        }
    }

    var stopButtonDiameter: CGFloat {
        switch self {
        case .small:  return 22
        case .medium: return 27
        case .large:  return 32
        }
    }

    var stopButtonSquare: CGFloat {
        switch self {
        case .small:  return 8
        case .medium: return 10
        case .large:  return 12
        }
    }

    var waveformMaxHeight: CGFloat {
        switch self {
        case .small:  return 24
        case .medium: return 30
        case .large:  return 38
        }
    }

    var recordingLeadPadding: CGFloat {
        switch self {
        case .small:  return 10
        case .medium: return 12
        case .large:  return 16
        }
    }

    var recordingTrailPadding: CGFloat {
        switch self {
        case .small:  return 8
        case .medium: return 10
        case .large:  return 16
        }
    }

    // MARK: Processing pill content

    var processingLogoDiameter: CGFloat {
        switch self {
        case .small:  return 16
        case .medium: return 20
        case .large:  return 24
        }
    }

    var processingFontSize: CGFloat {
        switch self {
        case .small:  return 11
        case .medium: return 12
        case .large:  return 14
        }
    }

    // MARK: Localised display name

    func displayName(locale: Locale) -> String {
        switch self {
        case .small:  return localized("Small",  locale: locale)
        case .medium: return localized("Medium", locale: locale)
        case .large:  return localized("Large",  locale: locale)
        }
    }
}

// MARK: - Hosting view (enables right-click context menu)

private final class DotHostingView: NSHostingView<DotIndicatorView> {
    var onRightMouseDown: ((NSEvent) -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        onRightMouseDown?(event)
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 {
            onRightMouseDown?(event)
        } else {
            super.otherMouseDown(with: event)
        }
    }
}

// MARK: - Controller

@MainActor
final class DotFloatingIndicatorController: NSObject, ObservableObject, FloatingIndicatorPresenting,
                                             NSMenuDelegate {

    let type: FloatingIndicatorType = .dot
    let state: FloatingIndicatorState

    @Published var isHovered: Bool = false
    @Published private(set) var expandsRight: Bool = false
    @Published private(set) var isDragging: Bool = false
    @Published var dotIndicatorSize: DotFloatingIndicatorSize

    private let settingsStore: SettingsStore
    private var panel: NSPanel?
    private var hostingView: DotHostingView?
    private var hoverTimer: Timer?
    private var actions = FloatingIndicatorActions()
    private var isVisible = false
    private var lastHoverContactAt: Date = .distantPast
    private var dragStartMouseLocation: CGPoint?
    private var dragStartOffset: CGSize = .zero
    private var dragOffset: CGSize = .zero
    private var lastScreen: NSScreen?

    private var contextMenu: NSMenu?
    private var microphoneMenu: NSMenu?
    private var microphoneItem: NSMenuItem?
    private var languageMenu: NSMenu?
    private var languageItem: NSMenuItem?
    private var sizeMenu: NSMenu?
    private var sizeItem: NSMenuItem?
    private var isContextMenuOpen = false

    init(state: FloatingIndicatorState, settingsStore: SettingsStore) {
        self.state = state
        self.settingsStore = settingsStore
        self.dragOffset = settingsStore.dotFloatingIndicatorOffset
        self.dotIndicatorSize = DotFloatingIndicatorSize(rawValue: settingsStore.dotFloatingIndicatorSize) ?? .large
        super.init()
        contextMenu = makeContextMenu()
    }

    func configure(actions: FloatingIndicatorActions) {
        self.actions = actions
    }

    // MARK: FloatingIndicatorPresenting

    func showIdleIndicator() {
        guard !isVisible else { panel?.orderFrontRegardless(); return }
        show()
    }

    func showForCurrentState() {
        if !isVisible { show() } else { panel?.orderFrontRegardless() }
    }

    func startRecording() {
        isHovered = false
        lastHoverContactAt = .distantPast
        state.startRecording()
        if !isVisible { show() }
    }

    func transitionToProcessing() {
        state.transitionToProcessing()
        isHovered = false
        lastHoverContactAt = .distantPast
    }

    func finishProcessing() {
        state.finishSession()
        isHovered = false
        lastHoverContactAt = .distantPast
        hide()
    }

    func hide() {
        stopHoverMonitoring()
        guard let panel else { isVisible = false; return }
        isVisible = false
        isHovered = false
        isDragging = false
        isContextMenuOpen = false
        lastScreen = nil

        let localPanel = panel
        let localHostingView = hostingView

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = DotMetrics.hideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            localPanel.animator().alphaValue = 0
        }) { [weak self] in
            localPanel.close()
            DispatchQueue.main.async {
                guard let self else { return }
                if self.panel === localPanel { self.panel = nil }
                if self.hostingView === localHostingView { self.hostingView = nil }
            }
        }
    }

    // MARK: Action forwarding

    func handleStartTapped() { actions.onStartRecording?(type) }
    func handleStopTapped()  { actions.onStopRecording?(type) }

    // MARK: Drag

    func beginDrag() {
        guard isVisible, !isDragging else { return }
        isDragging = true
        isHovered = false

        let mouse = NSEvent.mouseLocation
        let screen = preferredScreen()
        let visible = screen.visibleFrame

        let defaultDotCX = visible.maxX - DotMetrics.screenInset - dotIndicatorSize.dotDiameter / 2
        let defaultDotCY = visible.minY + DotMetrics.screenInset + dotIndicatorSize.dotDiameter / 2
        dragStartOffset = CGSize(width: mouse.x - defaultDotCX, height: mouse.y - defaultDotCY)
        dragOffset = dragStartOffset
        dragStartMouseLocation = mouse

        panel?.setFrame(panelFrame(for: screen), display: true)
    }

    func updateDrag(translation: CGSize) {
        guard isDragging, let start = dragStartMouseLocation else { return }
        dragOffset = CGSize(
            width:  dragStartOffset.width  + (NSEvent.mouseLocation.x - start.x),
            height: dragStartOffset.height + (NSEvent.mouseLocation.y - start.y)
        )
        if let panel {
            panel.setFrame(panelFrame(for: preferredScreen()), display: false)
        }
    }

    func endDrag(translation: CGSize) {
        guard isDragging else { return }
        updateDrag(translation: translation)
        settingsStore.dotFloatingIndicatorOffset = dragOffset
        dragStartOffset = dragOffset
        isDragging = false
        dragStartMouseLocation = nil
        if let panel {
            panel.setFrame(panelFrame(for: preferredScreen()), display: true)
        }
    }

    // MARK: Context menu

    private func makeContextMenu() -> NSMenu {
        let locale = settingsStore.selectedAppLanguage.locale
        let menu = NSMenu(title: localized("Pindrop Dot", locale: locale))
        menu.delegate = self

        let sizeMenu = NSMenu(title: localized("Size", locale: locale))
        self.sizeMenu = sizeMenu
        let sizeItem = NSMenuItem(title: localized("Size", locale: locale), action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        self.sizeItem = sizeItem
        menu.addItem(sizeItem)

        menu.addItem(.separator())

        let items: [(String, Selector)] = [
            (localized("Hide this for 1 hour",   locale: locale), #selector(handleHideForOneHourMenuItem)),
            (localized("Report an issue",         locale: locale), #selector(handleReportIssueMenuItem)),
            (localized("Go to settings",          locale: locale), #selector(handleGoToSettingsMenuItem)),
        ]
        for (title, action) in items {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let micMenu = NSMenu(title: localized("Change microphone", locale: locale))
        self.microphoneMenu = micMenu
        let micItem = NSMenuItem(title: localized("Change microphone", locale: locale), action: nil, keyEquivalent: "")
        micItem.submenu = micMenu
        self.microphoneItem = micItem
        menu.addItem(micItem)

        let langMenu = NSMenu(title: localized("Select language", locale: locale))
        self.languageMenu = langMenu
        let langItem = NSMenuItem(title: localized("Select language", locale: locale), action: nil, keyEquivalent: "")
        langItem.submenu = langMenu
        self.languageItem = langItem
        menu.addItem(langItem)

        menu.addItem(.separator())

        let historyItem = NSMenuItem(
            title: localized("View transcript history", locale: locale),
            action: #selector(handleViewTranscriptHistoryMenuItem), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

        let pasteItem = NSMenuItem(
            title: localized("Paste last transcript ⌃⌘V", locale: locale),
            action: #selector(handlePasteLastTranscriptMenuItem), keyEquivalent: "")
        pasteItem.target = self
        menu.addItem(pasteItem)

        refreshContextMenuState()
        return menu
    }

    private func refreshContextMenuState() {
        refreshSizeMenuItems()
        refreshMicrophoneMenuItems()
        refreshLanguageMenuItems()
    }

    private func refreshSizeMenuItems() {
        guard let sizeMenu else { return }
        sizeMenu.removeAllItems()
        let locale = settingsStore.selectedAppLanguage.locale
        for size in DotFloatingIndicatorSize.allCases {
            let item = NSMenuItem(title: size.displayName(locale: locale),
                                  action: #selector(handleSizeMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size.rawValue
            item.state = dotIndicatorSize == size ? .on : .off
            sizeMenu.addItem(item)
        }
        sizeItem?.isEnabled = true
    }

    private func refreshMicrophoneMenuItems() {
        guard let microphoneMenu else { return }
        microphoneMenu.removeAllItems()
        let selectedUID = actions.selectedInputDeviceUIDProvider?() ?? ""
        let devices = actions.availableInputDevicesProvider?() ?? []
        let locale = settingsStore.selectedAppLanguage.locale

        let sysItem = NSMenuItem(title: localized("System Default", locale: locale),
                                 action: #selector(handleSelectInputDeviceMenuItem(_:)), keyEquivalent: "")
        sysItem.target = self; sysItem.representedObject = ""
        sysItem.state = selectedUID.isEmpty ? .on : .off
        microphoneMenu.addItem(sysItem)

        if !devices.isEmpty { microphoneMenu.addItem(.separator()) }
        for device in devices {
            let item = NSMenuItem(title: device.displayName,
                                  action: #selector(handleSelectInputDeviceMenuItem(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = device.uid
            item.state = device.uid == selectedUID ? .on : .off
            microphoneMenu.addItem(item)
        }
        if !selectedUID.isEmpty, !devices.contains(where: { $0.uid == selectedUID }) {
            microphoneMenu.addItem(.separator())
            let unavailable = NSMenuItem(title: localized("Unavailable device", locale: locale),
                                         action: nil, keyEquivalent: "")
            unavailable.isEnabled = false; unavailable.state = .on
            microphoneMenu.addItem(unavailable)
        }
        microphoneItem?.isEnabled = true
    }

    private func refreshLanguageMenuItems() {
        guard let languageMenu else { return }
        languageMenu.removeAllItems()
        let selected = actions.selectedLanguageProvider?() ?? .automatic
        let locale = settingsStore.selectedAppLanguage.locale
        for language in AppLanguage.allCases.filter(\.isSelectable) {
            let item = NSMenuItem(title: language.displayName(locale: locale),
                                  action: #selector(handleSelectLanguageMenuItem(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = language.rawValue
            item.state = selected == language ? .on : .off
            languageMenu.addItem(item)
        }
        let tier2 = AppLanguage.allCases.filter { !$0.isSelectable }
        if !tier2.isEmpty {
            languageMenu.addItem(.separator())
            let soon = NSMenuItem(title: localized("Coming Soon", locale: locale), action: nil, keyEquivalent: "")
            soon.isEnabled = false
            languageMenu.addItem(soon)
            for language in tier2 {
                let item = NSMenuItem(title: language.pickerLabel(locale: locale), action: nil, keyEquivalent: "")
                item.isEnabled = false
                languageMenu.addItem(item)
            }
        }
        languageItem?.isEnabled = true
    }

    private func handleRightMouseDown(_ event: NSEvent) {
        guard isVisible, !state.isRecording, !state.isProcessing else { return }
        guard let hostingView, let contextMenu else { return }
        isContextMenuOpen = true; isHovered = true; lastHoverContactAt = Date()
        refreshContextMenuState()
        contextMenu.update()
        contextMenu.appearance = NSApp.appearance
        let menuWidth = max(contextMenu.size.width, 240)
        let originX = hostingView.bounds.midX - menuWidth * 0.5 + 3
        let originY = hostingView.isFlipped ? hostingView.bounds.height - 10 : 10
        contextMenu.popUp(positioning: nil, at: NSPoint(x: originX, y: originY), in: hostingView)
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === contextMenu else { return }
        refreshContextMenuState(); isContextMenuOpen = true; isHovered = true; lastHoverContactAt = Date()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === contextMenu else { return }
        isContextMenuOpen = false; lastHoverContactAt = Date()
    }

    @objc private func handleSizeMenuItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let size = DotFloatingIndicatorSize(rawValue: rawValue) else { return }
        dotIndicatorSize = size
        settingsStore.dotFloatingIndicatorSize = rawValue
        refreshPanelFrame()
    }

    @objc private func handleHideForOneHourMenuItem()      { actions.onHideForOneHour?() }
    @objc private func handleReportIssueMenuItem()         { actions.onReportIssue?() }
    @objc private func handleGoToSettingsMenuItem()        { actions.onGoToSettings?() }
    @objc private func handleViewTranscriptHistoryMenuItem() { actions.onViewTranscriptHistory?() }
    @objc private func handlePasteLastTranscriptMenuItem() {
        Task { @MainActor in await actions.onPasteLastTranscript?() }
    }
    @objc private func handleSelectInputDeviceMenuItem(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        actions.onSelectInputDeviceUID?(uid)
    }
    @objc private func handleSelectLanguageMenuItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue) else { return }
        actions.onSelectLanguage?(language)
        refreshLanguageMenuItems()
    }

    // MARK: Private — panel lifecycle

    private func show() {
        let screen = preferredScreen()
        let frame = panelFrame(for: screen)
        let panel = makePanel(contentRect: frame)
        let contentView = DotIndicatorView(controller: self, state: state)
        let hostingView = DotHostingView(rootView: contentView)
        hostingView.layer?.backgroundColor = .clear
        hostingView.wantsLayer = true
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.onRightMouseDown = { [weak self] event in self?.handleRightMouseDown(event) }
        panel.contentView = hostingView
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel; self.hostingView = hostingView
        self.isVisible = true; self.lastScreen = screen
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DotMetrics.showDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        startHoverMonitoring()
    }

    private func makePanel(contentRect: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.isOpaque = false
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear; panel.isMovable = false; panel.hasShadow = false
        panel.level = .mainMenu + 1
        panel.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func refreshPanelFrame() {
        guard let panel, isVisible else { return }
        let screen = preferredScreen()
        let frame = panelFrame(for: screen)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: false)
        }
        hostingView?.frame = NSRect(origin: .zero, size: frame.size)
    }

    // MARK: Private — hover monitoring

    private func startHoverMonitoring() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.pindrop_scheduleRepeating(interval: DotMetrics.hoverMonitorInterval) { [weak self] _ in
            Task { @MainActor in self?.monitorTick() }
        }
    }

    private func stopHoverMonitoring() {
        hoverTimer?.invalidate(); hoverTimer = nil; lastHoverContactAt = .distantPast
    }

    private func monitorTick() {
        guard isVisible else { return }
        checkScreenPosition()
        evaluateHover()
    }

    private func evaluateHover() {
        guard isVisible, !isDragging, !state.isRecording, !state.isProcessing else { return }
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation; let now = Date()
        let dotRect = dotScreenRect(for: panel.frame)
        let activationRect = dotRect.insetBy(dx: -DotMetrics.hoverActivationInset, dy: -DotMetrics.hoverActivationInset)
        let retentionRect = panel.frame.insetBy(dx: -12, dy: -10)
        if isHovered {
            if isContextMenuOpen || retentionRect.contains(mouse) { lastHoverContactAt = now; return }
            if now.timeIntervalSince(lastHoverContactAt) >= DotMetrics.hoverCollapseDelay { setHoverState(false) }
            return
        }
        if activationRect.contains(mouse) { lastHoverContactAt = now; setHoverState(true) }
    }

    private func dotScreenRect(for panelFrame: NSRect) -> NSRect {
        let r = dotIndicatorSize.dotDiameter / 2
        let cx = dotCenterX(for: panelFrame)
        return NSRect(x: cx - r, y: panelFrame.midY - r, width: dotIndicatorSize.dotDiameter, height: dotIndicatorSize.dotDiameter)
    }

    private func checkScreenPosition() {
        guard isVisible, let panel else { return }
        let currentScreen = preferredScreen()
        if lastScreen?.pindrop_isSameDisplay(as: currentScreen) == false {
            lastScreen = currentScreen
            let newFrame = panelFrame(for: currentScreen)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0; context.allowsImplicitAnimation = false
                panel.setFrame(newFrame, display: false, animate: false)
            }
            return
        }
        if !isDragging {
            let dotCX = dotCenterX(for: panel.frame)
            let newExpand = shouldExpandRight(dotCenterX: dotCX, screen: currentScreen)
            if newExpand != expandsRight { expandsRight = newExpand }
        }
    }

    func setHoverState(_ hovering: Bool) {
        guard isVisible, !isDragging, !state.isRecording, !state.isProcessing else { return }
        guard isHovered != hovering else { return }
        isHovered = hovering
        if hovering { lastHoverContactAt = Date() }
    }

    // MARK: Private — layout maths

    private func panelFrame(for screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let offset = isDragging ? dragOffset : settingsStore.dotFloatingIndicatorOffset
        let r = dotIndicatorSize.dotDiameter / 2

        let defaultDotCX = visible.maxX - DotMetrics.screenInset - r
        let defaultDotCY = visible.minY + DotMetrics.screenInset + r

        let dotCX = max(visible.minX + DotMetrics.screenInset + r,
                        min(defaultDotCX + offset.width,
                            visible.maxX - DotMetrics.screenInset - r))
        let dotCY = max(visible.minY + DotMetrics.screenInset + r,
                        min(defaultDotCY + offset.height,
                            visible.maxY - DotMetrics.screenInset - r))

        if !isDragging {
            let newExpand = shouldExpandRight(dotCenterX: dotCX, screen: screen)
            if newExpand != expandsRight { expandsRight = newExpand }
        }

        let pw = dotIndicatorSize.panelWidth
        let panelX: CGFloat = expandsRight
            ? dotCX - r - DotMetrics.edgeInset
            : dotCX + r + DotMetrics.edgeInset - pw

        return NSRect(x: panelX, y: dotCY - dotIndicatorSize.panelHeight / 2,
                      width: pw, height: dotIndicatorSize.panelHeight)
    }

    private func shouldExpandRight(dotCenterX: CGFloat, screen: NSScreen) -> Bool {
        let pillLeftEdge = dotCenterX + dotIndicatorSize.dotDiameter / 2 - dotIndicatorSize.expandedWidth
        return pillLeftEdge < screen.visibleFrame.minX + DotMetrics.screenInset
    }

    private func dotCenterX(for panelFrame: NSRect) -> CGFloat {
        let r = dotIndicatorSize.dotDiameter / 2
        return expandsRight
            ? panelFrame.minX + DotMetrics.edgeInset + r
            : panelFrame.maxX - DotMetrics.edgeInset - r
    }

    private func preferredScreen() -> NSScreen {
        actions.preferredScreenProvider?() ?? NSScreen.screenUnderMouse()
    }
}

// MARK: - SwiftUI view

struct DotIndicatorView: View {
    @ObservedObject var controller: DotFloatingIndicatorController
    @ObservedObject var state: FloatingIndicatorState
    @ObservedObject private var theme = PindropThemeController.shared
    @Environment(\.locale) private var locale

    private var sz: DotFloatingIndicatorSize { controller.dotIndicatorSize }

    private var isExpanded: Bool { state.isRecording || state.isProcessing || controller.isHovered }
    private var pillWidth: CGFloat  { isExpanded ? sz.expandedWidth  : sz.dotDiameter }
    private var pillHeight: CGFloat { isExpanded ? sz.expandedHeight : sz.dotDiameter }

    var body: some View {
        Group {
            if controller.expandsRight {
                HStack(spacing: 0) {
                    morphingPill.padding(.leading, DotMetrics.edgeInset)
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    morphingPill.padding(.trailing, DotMetrics.edgeInset)
                }
            }
        }
        .frame(width: sz.panelWidth, height: sz.panelHeight)
        .animation(.spring(response: 0.36, dampingFraction: 0.80), value: isExpanded)
        .animation(.spring(response: 0.36, dampingFraction: 0.80), value: controller.expandsRight)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: sz.dotDiameter)
    }

    // MARK: Morphing pill

    private var morphingPill: some View {
        ZStack {
            Capsule()
                .fill(AppColors.overlaySurfaceStrong)
                .shadow(color: AppColors.shadowColor.opacity(0.36), radius: 12, y: 6)
                .hairlineStroke(Capsule(), style: AppColors.overlayLine.opacity(0.6))

            Circle()
                .fill(LinearGradient(
                    colors: [AppColors.overlayTooltipAccent, AppColors.accent],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: sz.pebbleDiameter, height: sz.pebbleDiameter)
                .opacity(isExpanded ? 0 : 1)
                .animation(.easeIn(duration: 0.08), value: isExpanded)

            expandedContent
                .opacity(isExpanded ? 1 : 0)
                .allowsHitTesting(isExpanded)
                .animation(.easeOut(duration: 0.16).delay(isExpanded ? 0.14 : 0), value: isExpanded)
        }
        .frame(width: pillWidth, height: pillHeight)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in
                    if !controller.isDragging { controller.beginDrag() }
                    controller.updateDrag(translation: .zero)
                }
                .onEnded { _ in controller.endDrag(translation: .zero) }
        )
    }

    // MARK: Expanded states

    @ViewBuilder
    private var expandedContent: some View {
        if state.isRecording      { recordingContent }
        else if state.isProcessing { processingContent }
        else                       { hoverContent }
    }

    private var hoverContent: some View {
        HStack(spacing: 0) {
            Button { controller.handleStartTapped() } label: {
                ZStack {
                    Circle()
                        .fill(AppColors.overlayRecording)
                        .frame(width: sz.recordButtonDiameter, height: sz.recordButtonDiameter)
                        .shadow(color: AppColors.overlayRecording.opacity(0.28), radius: 8, y: 4)
                    Circle()
                        .fill(AppColors.overlayTextPrimary)
                        .frame(width: sz.recordButtonInnerDot, height: sz.recordButtonInnerDot)
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            Text(localized("Ready to record", locale: locale))
                .font(.system(size: sz.expandedTextSize, weight: .regular, design: .rounded))
                .foregroundStyle(AppColors.overlayTextSecondary)
                .frame(maxWidth: .infinity)

            ZStack {
                Circle()
                    .fill(AppColors.overlaySurface.opacity(0.5))
                    .frame(width: sz.micButtonDiameter, height: sz.micButtonDiameter)
                Image(systemName: "mic.fill")
                    .font(.system(size: sz.expandedTextSize, weight: .medium))
                    .foregroundStyle(AppColors.overlayTextSecondary)
            }
        }
        .padding(.horizontal, sz.expandedHPadding)
    }

    private var recordingContent: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(LinearGradient(
                    colors: [AppColors.overlayRecording, AppColors.overlayRecording.opacity(0.45)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: 3)
                .padding(.vertical, 8)
                .padding(.leading, sz.recordingLeadPadding)

            FloatingIndicatorWaveformView(
                audioLevel: state.audioLevel,
                isRecording: state.isRecording,
                style: .dot)
            .frame(maxWidth: .infinity, maxHeight: sz.waveformMaxHeight)
            .clipped()
            .padding(.horizontal, 6)

            HStack(spacing: 8) {
                Text(formattedDuration)
                    .font(.system(size: sz.timerFontSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.overlayTextPrimary)
                    .fixedSize()

                Button { controller.handleStopTapped() } label: {
                    ZStack {
                        Circle()
                            .fill(AppColors.overlayRecording)
                            .frame(width: sz.stopButtonDiameter, height: sz.stopButtonDiameter)
                            .shadow(color: AppColors.overlayRecording.opacity(0.28), radius: 6, y: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColors.overlayTextPrimary)
                            .frame(width: sz.stopButtonSquare, height: sz.stopButtonSquare)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, sz.recordingTrailPadding)
        }
    }

    private var processingContent: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(LinearGradient(
                    colors: [AppColors.overlayTooltipAccent, AppColors.accent],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: sz.processingLogoDiameter, height: sz.processingLogoDiameter)

            Text(localized("Processing transcript", locale: locale))
                .font(.system(size: sz.processingFontSize, weight: .regular))
                .foregroundStyle(AppColors.overlayTextPrimary)
                .frame(maxWidth: .infinity)

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { DotLoadingDot(index: $0) }
            }
        }
        .padding(.horizontal, sz.recordingLeadPadding)
    }

    private var formattedDuration: String {
        String(format: "%d:%02d", Int(state.recordingDuration) / 60, Int(state.recordingDuration) % 60)
    }
}

// MARK: - Animated loading dot

private struct DotLoadingDot: View {
    let index: Int
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.06)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = (t * 2.2 + Double(index) * 0.45).truncatingRemainder(dividingBy: 3.0)
            Circle()
                .fill(AppColors.overlayTextSecondary.opacity(phase < 1.0 ? 0.85 : 0.28))
                .frame(width: 5, height: 5)
                .animation(.easeInOut(duration: 0.22), value: phase < 1.0)
        }
    }
}

// MARK: - Previews

#Preview("Dot – Idle / Large")  { dotPreview(size: .large)  }
#Preview("Dot – Idle / Medium") { dotPreview(size: .medium) }
#Preview("Dot – Idle / Small")  { dotPreview(size: .small)  }
#Preview("Dot – Hover")         { dotHoverPreview }
#Preview("Dot – Recording")     { dotRecordingPreview }
#Preview("Dot – Processing")    { dotProcessingPreview }

@MainActor
private func dotPreview(size: DotFloatingIndicatorSize) -> some View {
    let settings = SettingsStore()
    settings.dotFloatingIndicatorSize = size.rawValue
    let controller = DotFloatingIndicatorController(state: FloatingIndicatorState(), settingsStore: settings)
    return DotIndicatorView(controller: controller, state: controller.state)
        .frame(width: size.panelWidth, height: size.panelHeight)
        .background(AppColors.windowBackground)
}

@MainActor
private var dotHoverPreview: some View {
    let controller = DotFloatingIndicatorController(state: FloatingIndicatorState(), settingsStore: SettingsStore())
    controller.isHovered = true
    return DotIndicatorView(controller: controller, state: controller.state)
        .frame(width: DotFloatingIndicatorSize.large.panelWidth, height: DotFloatingIndicatorSize.large.panelHeight)
        .background(AppColors.windowBackground)
}

@MainActor
private var dotRecordingPreview: some View {
    let controller = DotFloatingIndicatorController(state: FloatingIndicatorState(), settingsStore: SettingsStore())
    controller.state.isRecording = true; controller.state.audioLevel = 0.65
    return DotIndicatorView(controller: controller, state: controller.state)
        .frame(width: DotFloatingIndicatorSize.large.panelWidth, height: DotFloatingIndicatorSize.large.panelHeight)
        .background(AppColors.windowBackground)
}

@MainActor
private var dotProcessingPreview: some View {
    let controller = DotFloatingIndicatorController(state: FloatingIndicatorState(), settingsStore: SettingsStore())
    controller.state.isProcessing = true
    return DotIndicatorView(controller: controller, state: controller.state)
        .frame(width: DotFloatingIndicatorSize.large.panelWidth, height: DotFloatingIndicatorSize.large.panelHeight)
        .background(AppColors.windowBackground)
}
