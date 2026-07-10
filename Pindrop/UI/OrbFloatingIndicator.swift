//
//  OrbFloatingIndicator.swift
//  Pindrop
//
//  Created on 2026-07-06.
//
//  The Orb floating indicator: a liquid-glass orb resting in a screen corner
//  (bottom-right by default). Its interior renders three audio-reactive band
//  blobs; hovering (or tapping to start) makes the orb itself swell and churn.
//  While recording, a compact pill pops out of the orb's side carrying the timer
//  and stop control; while overlay streaming is active the same pill grows to
//  hold the live transcript with the timer/actions row on top. Orb and pill are
//  rendered as one liquid surface by the analytic `orbGooField` Metal shader
//  (SDF lobes → blurred-silhouette alpha → threshold + rim light).
//

import SwiftUI
import AppKit
import Combine

// MARK: - Layout constants (size-independent only)

private enum OrbMetrics {
    /// Padding between panel edge and the liquid assembly.
    static let edgeInset: CGFloat = 10
    /// Minimum gap between the orb centre and the visible screen boundary.
    static let screenInset: CGFloat = 16

    static let hoverMonitorInterval: TimeInterval = 1.0 / 60.0
    static let hoverCollapseDelay: TimeInterval = 0.18
    static let hoverActivationInset: CGFloat = 22

    static let showDuration: TimeInterval = 0.22
    static let hideDuration: TimeInterval = 0.15

    /// Softness (σ) of the analytic goo field: the shader models each lobe's
    /// alpha as a Gaussian-blurred silhouette of this radius, preserving the
    /// look of the earlier raster-blur pipeline.
    static let gooSoftness: CGFloat = 5

    /// Resting gap between the orb's edge and the detached pill. The shader
    /// bridges two surfaces once the saddle point of their alpha fields crosses
    /// the 0.34 threshold — at ~1.9 × `gooSoftness` apart — so the gap must
    /// exceed that for the two to read as fully separate surfaces at rest; the
    /// liquid merge only appears mid-transition, while the pill's near edge
    /// travels through the orb's alpha field.
    static let pillSeparationGap: CGFloat = 10

    /// Screen-width fractions that pick the pill's exit side: orb in the right
    /// zone → pill exits left, left zone → exits right, middle band → exits
    /// vertically (up from the bottom half, down from the top half).
    static let leftZoneEnd: CGFloat = 0.4
    static let rightZoneStart: CGFloat = 0.6
}

/// Which side of the orb the pill extrudes from, named by the direction the pill
/// travels. Chosen from the orb's position on screen so the pill always opens
/// toward the roomy side.
enum OrbPillExitEdge {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
}

// MARK: - Size

/// Governs ALL dimensions of the indicator — the idle orb AND the pop-out pill.
enum OrbFloatingIndicatorSize: String, CaseIterable, Identifiable {
    case small  = "small"
    case medium = "medium"
    case large  = "large"

    var id: String { rawValue }

    // MARK: Orb

    var orbIdleDiameter: CGFloat {
        30
    }

    /// Hover swell: clearly bigger than idle while still short of the active size,
    /// so starting a session reads as a further step up.
    var orbHoverDiameter: CGFloat {
        44
    }

    var orbActiveDiameter: CGFloat {
        56
    }

    // MARK: Pill

    var pillHeight: CGFloat {
        32
    }

    /// Width of the pill while a finished recording is being transcribed.
    var pillProcessingWidth: CGFloat {
        148
    }

    var pillRecordingWidth: CGFloat {
        126
    }

    var pillStreamingWidth: CGFloat {
        250
    }

    var pillStreamingHeight: CGFloat {
        104
    }

    /// Vertical lift that keeps the compact pill centred on the orb when it exits
    /// horizontally; the streaming pill drops the lift so its bottom edge aligns
    /// with the orb's.
    var pillLift: CGFloat { (orbActiveDiameter - pillHeight) / 2 }

    // MARK: Type

    var timerFontSize: CGFloat {
        13
    }

    var textFontSize: CGFloat {
        14
    }

    var transcriptLineLimit: Int {
        3
    }

    // MARK: Controls

    var stopButtonDiameter: CGFloat {
        10
    }

    // MARK: Panel

    /// Panel dimensions depend on the pill's exit direction: horizontal exits lay
    /// orb and pill side by side (streaming pill bottom-aligned with the orb);
    /// vertical exits stack them.
    func panelSize(for edge: OrbPillExitEdge) -> CGSize {
        let inset = OrbMetrics.edgeInset * 2
        if edge.isHorizontal {
            return CGSize(
                width: pillStreamingWidth + OrbMetrics.pillSeparationGap + orbActiveDiameter + inset,
                height: max(orbActiveDiameter, pillStreamingHeight) + inset
            )
        }
        return CGSize(
            width: max(pillStreamingWidth, orbActiveDiameter) + inset,
            height: pillStreamingHeight + OrbMetrics.pillSeparationGap + orbActiveDiameter + inset
        )
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

private final class OrbHostingView: NSHostingView<AnyView> {
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
final class OrbFloatingIndicatorController: NSObject, ObservableObject, FloatingIndicatorPresenting,
                                             NSMenuDelegate {

    let type: FloatingIndicatorType = .orb
    let state: FloatingIndicatorState
    let liveTranscript: LiveTranscriptState

    @Published var isHovered: Bool = false
    @Published private(set) var pillExitEdge: OrbPillExitEdge = .left
    @Published private(set) var isDragging: Bool = false
    @Published var orbIndicatorSize: OrbFloatingIndicatorSize

    private let settingsStore: SettingsStore
    private var panel: NSPanel?
    private var hostingView: OrbHostingView?
    private var hoverTimer: Timer?
    private var actions = FloatingIndicatorActions()
    private var isVisible = false
    private var lastHoverContactAt: Date = .distantPast
    private var lastDragEndedAt: Date = .distantPast
    private var isPointerCursorActive = false
    private var monitorTickCount = 0
    private var dragStartMouseLocation: CGPoint?
    private var dragStartOffset: CGSize = .zero
    private var dragOffset: CGSize = .zero
    private var lastScreen: NSScreen?

    private var contextMenu: NSMenu?
    private var microphoneMenu: NSMenu?
    private var microphoneItem: NSMenuItem?
    private var languageMenu: NSMenu?
    private var languageItem: NSMenuItem?
    private var isContextMenuOpen = false

    init(
        state: FloatingIndicatorState,
        settingsStore: SettingsStore,
        liveTranscript: LiveTranscriptState
    ) {
        self.state = state
        self.settingsStore = settingsStore
        self.liveTranscript = liveTranscript
        self.dragOffset = settingsStore.orbFloatingIndicatorOffset
        self.orbIndicatorSize = OrbFloatingIndicatorSize(rawValue: settingsStore.orbFloatingIndicatorSize) ?? .medium
        super.init()
        contextMenu = makeContextMenu()
    }

    func configure(actions: FloatingIndicatorActions) {
        self.actions = actions
    }

    func reloadLocalizedStrings() {
        contextMenu = makeContextMenu()
        hostingView?.rootView = makeRootView()
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
        setPointerCursorActive(false)
        guard let panel else { isVisible = false; return }
        isVisible = false
        isHovered = false
        isDragging = false
        isContextMenuOpen = false
        lastScreen = nil

        let localPanel = panel
        let localHostingView = hostingView

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : OrbMetrics.hideDuration
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

    /// Tap on the orb toggles the session. The tap gesture's movement slop is
    /// wider than the drag gesture's 4pt threshold, so a small reposition nudge
    /// can fire both — ignore taps during or just after a drag.
    func handleOrbTapped() {
        guard !isDragging, Date().timeIntervalSince(lastDragEndedAt) > 0.25 else { return }
        if state.isRecording {
            handleStopTapped()
        } else if !state.isProcessing {
            handleStartTapped()
        }
    }

    /// Balanced push/pop for the orb's hover cursor. Closing the panel under the
    /// pointer never delivers the hover-exit callback, so `hide()` resets this to
    /// keep the app's cursor stack balanced.
    func setPointerCursorActive(_ active: Bool) {
        guard isPointerCursorActive != active else { return }
        isPointerCursorActive = active
        if active { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }

    // MARK: Drag

    func beginDrag() {
        guard isVisible, !isDragging else { return }
        isDragging = true
        isHovered = false

        let mouse = NSEvent.mouseLocation
        let screen = preferredScreen()
        let visible = screen.visibleFrame
        let r = orbIndicatorSize.orbActiveDiameter / 2

        let defaultOrbCX = visible.maxX - OrbMetrics.screenInset - r
        let defaultOrbCY = visible.minY + OrbMetrics.screenInset + r
        dragStartOffset = CGSize(width: mouse.x - defaultOrbCX, height: mouse.y - defaultOrbCY)
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
        settingsStore.orbFloatingIndicatorOffset = dragOffset
        dragStartOffset = dragOffset
        isDragging = false
        lastDragEndedAt = Date()
        dragStartMouseLocation = nil
        if let panel {
            panel.setFrame(panelFrame(for: preferredScreen()), display: true)
        }
    }

    // MARK: Context menu

    private func makeContextMenu() -> NSMenu {
        let locale = settingsStore.selectedAppLocale.locale
        let menu = NSMenu(title: localized("Pindrop Orb", locale: locale))
        menu.delegate = self

        // No Size submenu: U10 locked the orb to the spec's fixed state sizes, so the
        // old Small/Medium/Large picker no longer changes anything.
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
        applyInterfaceLayoutDirection(to: menu, locale: locale)
        return menu
    }

    private func refreshContextMenuState() {
        refreshMicrophoneMenuItems()
        refreshLanguageMenuItems()
    }

    private func refreshMicrophoneMenuItems() {
        guard let microphoneMenu else { return }
        microphoneMenu.removeAllItems()
        let selectedUID = actions.selectedInputDeviceUIDProvider?() ?? ""
        let devices = actions.availableInputDevicesProvider?() ?? []
        let locale = settingsStore.selectedAppLocale.locale

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
        let locale = settingsStore.selectedAppLocale.locale
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
        let bounds = hostingView.bounds
        let anchorX: CGFloat
        switch pillExitEdge {
        case .left:
            anchorX = bounds.width - OrbMetrics.edgeInset - orbIndicatorSize.orbActiveDiameter / 2
        case .right:
            anchorX = OrbMetrics.edgeInset + orbIndicatorSize.orbActiveDiameter / 2
        case .up, .down:
            anchorX = bounds.midX
        }
        // The orb sits at the panel top for `.down` exits and at the bottom otherwise.
        let orbAtPanelTop = pillExitEdge == .down
        let originX = anchorX - menuWidth * 0.5 + 3
        let nearBottom: CGFloat = 10
        let nearTop = bounds.height - 10
        let originY: CGFloat
        if hostingView.isFlipped {
            originY = orbAtPanelTop ? nearBottom : nearTop
        } else {
            originY = orbAtPanelTop ? nearTop : nearBottom
        }
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
        let hostingView = OrbHostingView(rootView: makeRootView())
        hostingView.layer?.backgroundColor = .clear
        hostingView.wantsLayer = true
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.userInterfaceLayoutDirection = .leftToRight
        hostingView.onRightMouseDown = { [weak self] event in self?.handleRightMouseDown(event) }
        panel.contentView = hostingView
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel; self.hostingView = hostingView
        self.isVisible = true; self.lastScreen = screen
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : OrbMetrics.showDuration
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

    private func makeRootView() -> AnyView {
        let locale = settingsStore.selectedAppLocale.locale
        return AnyView(
            OrbIndicatorView(controller: self, state: state, transcript: liveTranscript)
                .environment(\.locale, locale)
                // Panel geometry is physical (goo shader + exit edges use absolute
                // panel coords); RTL applies to text subtrees (LiveTranscriptView).
                .environment(\.layoutDirection, .leftToRight)
        )
    }

    private func refreshPanelFrame() {
        guard let panel, isVisible else { return }
        let screen = preferredScreen()
        let frame = panelFrame(for: screen)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: false)
        }
        hostingView?.frame = NSRect(origin: .zero, size: frame.size)
    }

    // MARK: Private — hover monitoring

    private func startHoverMonitoring() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.pindrop_scheduleRepeating(interval: OrbMetrics.hoverMonitorInterval) { [weak self] _ in
            Task { @MainActor in self?.monitorTick() }
        }
    }

    private func stopHoverMonitoring() {
        hoverTimer?.invalidate(); hoverTimer = nil; lastHoverContactAt = .distantPast
    }

    private func monitorTick() {
        guard isVisible else { return }
        // Hover proximity wants the full tick rate; the screen/exit-edge check
        // walks NSScreen.screens and doesn't — keep it off the animation frames.
        monitorTickCount &+= 1
        if monitorTickCount % 8 == 0 { checkScreenPosition() }
        evaluateHover()
    }

    private func evaluateHover() {
        guard isVisible, !isDragging, !state.isRecording, !state.isProcessing else { return }
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation; let now = Date()
        let orbRect = orbScreenRect(for: panel.frame)
        let activationRect = orbRect.insetBy(dx: -OrbMetrics.hoverActivationInset, dy: -OrbMetrics.hoverActivationInset)
        if isHovered {
            if isContextMenuOpen || activationRect.contains(mouse) { lastHoverContactAt = now; return }
            if now.timeIntervalSince(lastHoverContactAt) >= OrbMetrics.hoverCollapseDelay { setHoverState(false) }
            return
        }
        if activationRect.contains(mouse) { lastHoverContactAt = now; setHoverState(true) }
    }

    private func orbScreenRect(for panelFrame: NSRect) -> NSRect {
        let d = orbIndicatorSize.orbActiveDiameter
        let x: CGFloat
        let y: CGFloat
        switch pillExitEdge {
        case .left:
            x = panelFrame.maxX - OrbMetrics.edgeInset - d
            y = panelFrame.minY + OrbMetrics.edgeInset
        case .right:
            x = panelFrame.minX + OrbMetrics.edgeInset
            y = panelFrame.minY + OrbMetrics.edgeInset
        case .up:
            x = panelFrame.midX - d / 2
            y = panelFrame.minY + OrbMetrics.edgeInset
        case .down:
            x = panelFrame.midX - d / 2
            y = panelFrame.maxY - OrbMetrics.edgeInset - d
        }
        return NSRect(x: x, y: y, width: d, height: d)
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
            let orbRect = orbScreenRect(for: panel.frame)
            let newEdge = exitEdge(forOrbCenter: CGPoint(x: orbRect.midX, y: orbRect.midY), on: currentScreen)
            if newEdge != pillExitEdge {
                pillExitEdge = newEdge
                // Panel dimensions and origin both change with the exit direction.
                refreshPanelFrame()
            }
        }
    }

    func setHoverState(_ hovering: Bool) {
        guard isVisible, !isDragging, !state.isRecording, !state.isProcessing else { return }
        guard isHovered != hovering else { return }
        isHovered = hovering
        if hovering { lastHoverContactAt = Date() }
    }

    // MARK: Private — layout maths

    /// The pill opens toward the roomy side of the screen: orb on the right half →
    /// pill exits left, left half → exits right, and in the middle band it exits
    /// vertically — up from the bottom half of the screen, down from the top half.
    private func exitEdge(forOrbCenter center: CGPoint, on screen: NSScreen) -> OrbPillExitEdge {
        let visible = screen.visibleFrame
        let fraction = (center.x - visible.minX) / max(1, visible.width)
        if fraction >= OrbMetrics.rightZoneStart { return .left }
        if fraction <= OrbMetrics.leftZoneEnd { return .right }
        return center.y <= visible.midY ? .up : .down
    }

    private func panelFrame(for screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let offset = isDragging ? dragOffset : settingsStore.orbFloatingIndicatorOffset
        let r = orbIndicatorSize.orbActiveDiameter / 2
        let e = OrbMetrics.edgeInset

        let defaultOrbCX = visible.maxX - OrbMetrics.screenInset - r
        let defaultOrbCY = visible.minY + OrbMetrics.screenInset + r
        let rawOrbCX = defaultOrbCX + offset.width
        let rawOrbCY = defaultOrbCY + offset.height

        let orbCX = max(visible.minX + OrbMetrics.screenInset + r,
                        min(rawOrbCX, visible.maxX - OrbMetrics.screenInset - r))

        let edge = exitEdge(forOrbCenter: CGPoint(x: orbCX, y: rawOrbCY), on: screen)
        if edge != pillExitEdge { pillExitEdge = edge }
        let size = orbIndicatorSize.panelSize(for: edge)

        // The panel extends past the orb in the pill's travel direction (headroom
        // for the streaming pill), so the orb's clamp on that axis is set by the
        // panel staying on-screen. Folding it into the orb-centre clamp keeps the
        // rendered orb tracking the cursor 1:1 during drags — no dead zone where a
        // panel clamp pins the orb while the offset keeps growing.
        let minOrbCY: CGFloat
        let maxOrbCY: CGFloat
        switch edge {
        case .left, .right, .up:
            // Orb anchors at the panel bottom; the panel rises `size.height` above it.
            minOrbCY = visible.minY + OrbMetrics.screenInset + r
            maxOrbCY = min(visible.maxY - OrbMetrics.screenInset - r,
                           visible.maxY - size.height + e + r)
        case .down:
            // Orb anchors at the panel top; the panel hangs `size.height` below it.
            minOrbCY = max(visible.minY + OrbMetrics.screenInset + r,
                           visible.minY + size.height - e - r)
            maxOrbCY = visible.maxY - OrbMetrics.screenInset - r
        }
        let orbCY = max(minOrbCY, min(rawOrbCY, maxOrbCY))

        var panelX: CGFloat
        let panelY: CGFloat
        switch edge {
        case .left:
            panelX = orbCX + r + e - size.width
            panelY = orbCY - r - e
        case .right:
            panelX = orbCX - r - e
            panelY = orbCY - r - e
        case .up:
            panelX = orbCX - size.width / 2
            panelY = orbCY - r - e
        case .down:
            panelX = orbCX - size.width / 2
            panelY = orbCY + r + e - size.height
        }
        panelX = max(visible.minX, min(panelX, visible.maxX - size.width))

        return NSRect(x: panelX, y: max(visible.minY, panelY), width: size.width, height: size.height)
    }

    private func preferredScreen() -> NSScreen {
        actions.preferredScreenProvider?() ?? NSScreen.screenUnderMouse()
    }
}

// MARK: - SwiftUI view

struct OrbIndicatorView: View {
    @ObservedObject var controller: OrbFloatingIndicatorController
    @ObservedObject var state: FloatingIndicatorState
    @ObservedObject var transcript: LiveTranscriptState
    @ObservedObject private var theme = PindropThemeController.shared
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sz: OrbFloatingIndicatorSize { controller.orbIndicatorSize }

    private var isActive: Bool { state.isRecording || state.isProcessing }
    private var showsTranscript: Bool { transcript.isActive && isActive }
    private var showsPill: Bool { isActive }

    private var orbDiameter: CGFloat {
        if state.isInputMuted { return sz.orbIdleDiameter }
        if state.isRecording || showsTranscript { return sz.orbActiveDiameter }
        if state.isProcessing { return sz.orbHoverDiameter }
        return controller.isHovered ? sz.orbHoverDiameter : sz.orbIdleDiameter
    }

    private var exit: OrbPillExitEdge { controller.pillExitEdge }

    private var ribbonPalette: OrbRibbonPalette {
        let appearance = NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let key = isDark
            ? PindropThemeStorageKeys.darkThemePresetID
            : PindropThemeStorageKeys.lightThemePresetID
        return OrbRibbonPalette.forPresetID(
            UserDefaults.standard.string(forKey: key),
            variant: isDark ? .dark : .light
        )
    }

    private var pillRestingSize: CGSize {
        if showsTranscript {
            return CGSize(width: sz.pillStreamingWidth, height: sz.pillStreamingHeight)
        }
        if state.isRecording {
            return CGSize(width: sz.pillRecordingWidth, height: sz.pillHeight)
        }
        return CGSize(width: sz.pillProcessingWidth, height: sz.pillHeight)
    }

    /// Hidden, the pill collapses along its travel axis so the pop-out reads as an
    /// extrusion from the orb rather than a fade-in.
    private var pillSize: CGSize {
        guard showsPill else {
            return exit.isHorizontal
                ? CGSize(width: 0, height: pillRestingSize.height)
                : CGSize(width: pillRestingSize.width, height: 0)
        }
        return pillRestingSize
    }

    private var pillCornerRadius: CGFloat {
        showsTranscript ? 16 : sz.pillHeight / 2
    }

    /// Distance from the orb-side content edge to the pill's near edge. At rest the
    /// pill floats fully detached (gap wider than the goo shader's bridging range);
    /// hidden, its near edge sits inside the orb, so the pop-out travels through the
    /// orb's alpha field and the shader renders an organic liquid separation.
    private var pillNearInset: CGFloat {
        showsPill
            ? sz.orbActiveDiameter + OrbMetrics.pillSeparationGap
            : sz.orbActiveDiameter * 0.35
    }

    private var assemblyAlignment: Alignment {
        switch exit {
        case .left:  return .bottomTrailing
        case .right: return .bottomLeading
        case .up:    return .bottom
        case .down:  return .top
        }
    }

    var body: some View {
        let panel = sz.panelSize(for: exit)
        return contentLayer
            .padding(OrbMetrics.edgeInset)
            .frame(width: panel.width, height: panel.height, alignment: assemblyAlignment)
            .background(
                OrbGooSurface(
                    orbCenter: orbCenterInPanel,
                    orbRadius: orbDiameter / 2,
                    pillCenter: pillCenterInPanel,
                    pillHalfWidth: pillSize.width / 2,
                    pillHalfHeight: pillSize.height / 2,
                    pillCornerRadius: pillCornerRadius
                )
            )
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82), value: showsPill)
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82), value: showsTranscript)
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84), value: isActive)
            .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.85), value: orbDiameter)
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82), value: exit)
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { _ in
                        if !controller.isDragging { controller.beginDrag() }
                        controller.updateDrag(translation: .zero)
                    }
                    .onEnded { _ in controller.endDrag(translation: .zero) }
            )
            .themeRefresh()
    }

    // MARK: Liquid surface geometry (full-panel coordinates, including edge inset)

    private var orbCenterInPanel: CGPoint {
        let panel = sz.panelSize(for: exit)
        let e = OrbMetrics.edgeInset
        let half = sz.orbActiveDiameter / 2
        switch exit {
        case .left:  return CGPoint(x: panel.width - e - half, y: panel.height - e - half)
        case .right: return CGPoint(x: e + half, y: panel.height - e - half)
        case .up:    return CGPoint(x: panel.width / 2, y: panel.height - e - half)
        case .down:  return CGPoint(x: panel.width / 2, y: e + half)
        }
    }

    private var pillCenterInPanel: CGPoint {
        let panel = sz.panelSize(for: exit)
        let e = OrbMetrics.edgeInset
        let lift = showsTranscript ? 0 : sz.pillLift
        switch exit {
        case .left:
            return CGPoint(x: panel.width - e - pillNearInset - pillSize.width / 2,
                           y: panel.height - e - lift - pillSize.height / 2)
        case .right:
            return CGPoint(x: e + pillNearInset + pillSize.width / 2,
                           y: panel.height - e - lift - pillSize.height / 2)
        case .up:
            return CGPoint(x: panel.width / 2,
                           y: panel.height - e - pillNearInset - pillSize.height / 2)
        case .down:
            return CGPoint(x: panel.width / 2,
                           y: e + pillNearInset + pillSize.height / 2)
        }
    }

    /// Anchors the fixed-size pill content within the animated reveal window so
    /// the wipe travels away from the orb, matching the pill's growth direction.
    private var pillRevealAlignment: Alignment {
        switch exit {
        case .left:      return .topTrailing
        case .right:     return .topLeading
        case .up, .down: return .top
        }
    }

    /// Positions the pill's near edge relative to the orb along the exit axis.
    /// Horizontal exits also lift the compact pill so it centres on the orb; the
    /// streaming pill drops the lift so its bottom edge aligns with the orb's.
    private var pillEdgeInsets: EdgeInsets {
        let lift = showsTranscript ? 0 : sz.pillLift
        switch exit {
        case .left:
            return EdgeInsets(top: 0, leading: 0, bottom: lift, trailing: pillNearInset)
        case .right:
            return EdgeInsets(top: 0, leading: pillNearInset, bottom: lift, trailing: 0)
        case .up:
            return EdgeInsets(top: 0, leading: 0, bottom: pillNearInset, trailing: 0)
        case .down:
            return EdgeInsets(top: pillNearInset, leading: 0, bottom: 0, trailing: 0)
        }
    }

    // MARK: Content overlay

    private var contentLayer: some View {
        ZStack(alignment: assemblyAlignment) {
            pillContent
                // Content lays out once at its resting size and is revealed
                // through the animated window below — re-laying-out the
                // transcript/scroll stack on every spring frame is the cost
                // this avoids. The nil transaction stops the resting-size frame
                // itself from animating; inner explicit `.animation(value:)`
                // modifiers (timer digits, processing dots) still run.
                .frame(width: pillRestingSize.width, height: pillRestingSize.height, alignment: .top)
                .transaction { $0.animation = nil }
                .frame(width: pillSize.width, height: pillSize.height, alignment: pillRevealAlignment)
                .background(
                    RoundedRectangle(cornerRadius: pillCornerRadius, style: .continuous)
                        .fill(AppColors.overlaySurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: pillCornerRadius, style: .continuous)
                                .strokeBorder(AppColors.overlayLine, lineWidth: 1)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: pillCornerRadius, style: .continuous))
                .shadow(color: Color.black.opacity(0.4), radius: 14, y: 4)
                .padding(pillEdgeInsets)
                .opacity(showsPill ? 1 : 0)
                .allowsHitTesting(showsPill)

            orbContent
                .frame(width: sz.orbActiveDiameter, height: sz.orbActiveDiameter)
                .overlay(alignment: .top) {
                    if let completion = state.recentCompletion, !state.isRecording, !state.isProcessing {
                        IndicatorCompletionOverlay(completion: completion)
                            .fixedSize()
                            .offset(y: exit == .down ? sz.orbActiveDiameter + 8 : -30)
                            .allowsHitTesting(false)
                            .appAnimation(.smooth, value: state.recentCompletion)
                    }
                }
        }
    }

    private var orbContent: some View {
        ZStack {
            OrbGlassFillView(
                palette: ribbonPalette,
                isHovered: controller.isHovered,
                isRecording: state.isRecording,
                isProcessing: state.isProcessing,
                isMuted: state.isInputMuted
            )

            Circle()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1.5)
                .blendMode(.plusLighter)

            if state.isRecording {
                Circle()
                    .stroke(
                        Color.white.opacity(0.14),
                        style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5])
                    )
                    .frame(width: 44, height: 44)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: orbDiameter, height: orbDiameter)
        .clipShape(Circle())
        .shadow(
            color: ribbonPalette.glowColor.opacity(state.isInputMuted ? 0 : (controller.isHovered ? 1 : 0.78)),
            radius: state.isRecording ? 26 : 18,
            y: state.isRecording ? 8 : 6
        )
        .opacity(state.isInputMuted ? 0.4 : 1)
        .contentShape(Circle())
        .onTapGesture { controller.handleOrbTapped() }
        .onHover { controller.setPointerCursorActive($0) }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(localized("Pindrop Orb", locale: locale))
        .accessibilityValue(
            localized(
                state.isInputMuted
                    ? "Microphone muted"
                    : (state.isRecording ? "Recording" : (state.isProcessing ? "Transcribing…" : "Ready")),
                locale: locale
            )
        )
        .accessibilityAction { controller.handleOrbTapped() }
        .keyboardFocusRing(Circle())
        .onKeyPress(.return) {
            controller.handleOrbTapped()
            return .handled
        }
    }

    // MARK: Pill content

    private var pillContent: some View {
        VStack(spacing: 0) {
            pillTopRow
                .frame(height: sz.pillHeight)
            if showsTranscript {
                LiveTranscriptView(
                    transcript: transcript,
                    fontSize: sz.textFontSize,
                    lineLimit: sz.transcriptLineLimit
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        // Compact pill height equals the row height, so the inset only applies to
        // the streaming layout — the row stays vertically centred otherwise.
        .padding(.top, showsTranscript ? 5 : 0)
    }

    @ViewBuilder
    private var pillTopRow: some View {
        if state.isRecording {
            HStack(spacing: 9) {
                Circle()
                    .fill(Color(nsColor: NSColor(pindropHex: "#D25B4C") ?? .systemRed))
                    .frame(width: showsTranscript ? 7 : 8, height: showsTranscript ? 7 : 8)

                Text(formattedDuration)
                    .font(FontLoader.font(
                        family: .jetbrainsMono,
                        size: showsTranscript ? 11 : 13,
                        weight: .medium
                    ))
                    .foregroundStyle(
                        Color(nsColor: NSColor(pindropHex: showsTranscript ? "#A59D8C" : "#EFEBE2") ?? .white)
                    )
                    .contentTransition(.numericText(countsDown: false))
                    .appAnimation(.fast, value: state.recordingDuration)
                    .fixedSize()

                Spacer(minLength: 0)

                if !showsTranscript {
                    Rectangle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 1, height: 14)
                }

                Button { controller.handleStopTapped() } label: {
                    RoundedRectangle(cornerRadius: showsTranscript ? 2 : 2.5, style: .continuous)
                        .fill(Color(nsColor: NSColor(pindropHex: "#EFEBE2") ?? .white).opacity(0.72))
                        .frame(
                            width: showsTranscript ? 9 : sz.stopButtonDiameter,
                            height: showsTranscript ? 9 : sz.stopButtonDiameter
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("Stop Recording", locale: locale))
            }
            .padding(.horizontal, showsTranscript ? 16 : 14)
        } else if state.isProcessing {
            HStack(spacing: 9) {
                IndicatorProcessingView(dotCount: 3, dotDiameter: 4, spacing: 3)
                Text(localized("Transcribing…", locale: locale))
                    .font(FontLoader.font(family: .inter, size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: NSColor(pindropHex: "#EFEBE2") ?? .white))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
        } else {
            // The pill only shows while a session is active; this branch renders
            // solely during the collapse animation after a session ends.
            Color.clear
        }
    }

    private var formattedDuration: String {
        FloatingIndicatorTimeFormatting.elapsed(state.recordingDuration)
    }
}

// MARK: - Liquid surface (analytic SDF metaball shader)

/// The orb+pill liquid surface, evaluated analytically per pixel in one fragment
/// pass (`orbGooField`). The predecessor rendered silhouettes through
/// compositingGroup → blur → threshold layerEffect; that chain re-rasterized on
/// every frame of the pop-out springs and dominated the transition's render
/// cost. `Animatable` lets the springs interpolate the field's geometry as plain
/// shader uniforms — an animation frame costs one quad draw.
private struct OrbGooSurface: View, Animatable {
    var orbCenter: CGPoint
    var orbRadius: CGFloat
    var pillCenter: CGPoint
    var pillHalfWidth: CGFloat
    var pillHalfHeight: CGFloat
    var pillCornerRadius: CGFloat

    typealias Quad = AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>

    var animatableData: AnimatablePair<Quad, Quad> {
        get {
            AnimatablePair(
                AnimatablePair(AnimatablePair(orbCenter.x, orbCenter.y),
                               AnimatablePair(orbRadius, pillCornerRadius)),
                AnimatablePair(AnimatablePair(pillCenter.x, pillCenter.y),
                               AnimatablePair(pillHalfWidth, pillHalfHeight))
            )
        }
        set {
            orbCenter = CGPoint(x: newValue.first.first.first, y: newValue.first.first.second)
            orbRadius = newValue.first.second.first
            pillCornerRadius = newValue.first.second.second
            pillCenter = CGPoint(x: newValue.second.first.first, y: newValue.second.first.second)
            pillHalfWidth = newValue.second.second.first
            pillHalfHeight = newValue.second.second.second
        }
    }

    var body: some View {
        Rectangle()
            .fill(Color.white)
            .colorEffect(
                ShaderLibrary.orbGooField(
                    .float2(orbCenter),
                    .float(orbRadius),
                    .float2(pillCenter),
                    .float2(pillHalfWidth, pillHalfHeight),
                    .float(pillCornerRadius),
                    .float(OrbMetrics.gooSoftness),
                    .color(OrbPalette.surface),
                    .color(OrbPalette.rim)
                )
            )
            .allowsHitTesting(false)
    }
}

private struct OrbGlassFillView: View {
    let palette: OrbRibbonPalette
    let isHovered: Bool
    let isRecording: Bool
    let isProcessing: Bool
    let isMuted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Shader time must be app-relative: absolute reference-date seconds (~8e8) exceed
    /// Float32 precision (ulp ≈ 32 s), which froze the aurora entirely.
    private static let animationEpoch = Date.timeIntervalSinceReferenceDate

    private var ribbonIntensity: Float {
        if isMuted { return 0 }
        if isHovered { return 1.15 }
        if isRecording { return 1 }
        if isProcessing { return 0.68 }
        return 0.5
    }

    private var animationInterval: TimeInterval {
        (isRecording || isProcessing || isHovered) ? (1.0 / 30.0) : (1.0 / 8.0)
    }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: animationInterval, paused: reduceMotion || isMuted)) { timeline in
                let baseTime = reduceMotion
                    ? 0
                    : timeline.date.timeIntervalSinceReferenceDate - Self.animationEpoch
                let speed = isProcessing ? 0.18 : 0.42

                Rectangle()
                    .fill(Color.white)
                    .colorEffect(
                        ShaderLibrary.orbGlassFill(
                            .float2(proxy.size),
                            .float(Float(baseTime * speed)),
                            .color(palette.primaryColor),
                            .color(palette.secondaryColor),
                            .float(ribbonIntensity),
                            .float(isRecording ? 1 : 0),
                            .float(isMuted ? 1 : 0)
                        )
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Palette

struct OrbRibbonPalette: Equatable {
    let primaryHex: String
    let secondaryHex: String
    let glowHex: String
    let glowOpacity: Double

    // Resolved once at init: the shader samples these every frame on an
    // always-visible window, so no per-frame hex parsing.
    let primaryColor: Color
    let secondaryColor: Color
    let glowColor: Color

    init(primaryHex: String, secondaryHex: String, glowHex: String, glowOpacity: Double) {
        self.primaryHex = primaryHex
        self.secondaryHex = secondaryHex
        self.glowHex = glowHex
        self.glowOpacity = glowOpacity
        self.primaryColor = Self.color(primaryHex)
        self.secondaryColor = Self.color(secondaryHex)
        self.glowColor = Self.color(glowHex).opacity(glowOpacity)
    }

    static func forPresetID(
        _ presetID: String?,
        variant: PindropThemeVariant = .light
    ) -> OrbRibbonPalette {
        switch presetID ?? PindropThemePresetCatalog.defaultPresetID {
        case "library":
            return OrbRibbonPalette(
                primaryHex: "#6FDCAF",
                secondaryHex: "#EFD9A8",
                glowHex: "#1F6D53",
                glowOpacity: 0.45
            )
        case "pindrop":
            return OrbRibbonPalette(
                primaryHex: "#F2B54A",
                secondaryHex: "#F7E3BC",
                glowHex: "#F2B54A",
                glowOpacity: 0.35
            )
        case "harbor":
            return OrbRibbonPalette(
                primaryHex: "#4FB3D1",
                secondaryHex: "#CFE9F0",
                glowHex: "#14708A",
                glowOpacity: 0.40
            )
        default:
            // Derived presets track the catalog accent for the active variant so the
            // ribbon hue matches the rest of the themed UI (spec §15).
            let accent = PindropThemePresetCatalog
                .profile(for: presetID, variant: variant)
                .accentHex
            return OrbRibbonPalette(
                primaryHex: accent,
                secondaryHex: mixedHex(accent, with: "#EFEBE2", ratio: 0.65),
                glowHex: accent,
                glowOpacity: 0.40
            )
        }
    }

    private static func mixedHex(_ first: String, with second: String, ratio: Double) -> String {
        func components(_ hex: String) -> (Double, Double, Double) {
            let cleaned = hex.replacingOccurrences(of: "#", with: "")
            guard let value = Int(cleaned, radix: 16), cleaned.count == 6 else { return (0, 0, 0) }
            return (
                Double((value >> 16) & 0xFF),
                Double((value >> 8) & 0xFF),
                Double(value & 0xFF)
            )
        }

        let a = components(first)
        let b = components(second)
        let t = min(1, max(0, ratio))
        let red = Int((a.0 + (b.0 - a.0) * t).rounded())
        let green = Int((a.1 + (b.1 - a.1) * t).rounded())
        let blue = Int((a.2 + (b.2 - a.2) * t).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func color(_ hex: String) -> Color {
        Color(nsColor: NSColor(pindropHex: hex) ?? .controlAccentColor)
    }
}

/// Literal dark floating-surface colors. The aurora itself is theme-driven by
/// `OrbRibbonPalette`; the body remains stable over arbitrary desktop content.
enum OrbPalette {
    static let surface = Color(nsColor: NSColor(pindropHex: "#181511") ?? .black).opacity(0.92)
    static let rim = Color.white.opacity(0.12)
    static let rimSoft = Color.white.opacity(0.14)
    static let depthTint = Color(nsColor: NSColor(pindropHex: "#1F6D53") ?? .systemGreen).opacity(0.22)

    static let bandLow = Color(nsColor: NSColor(pindropHex: "#17614A") ?? .systemGreen).opacity(0.6)
    static let bandMid = Color(nsColor: NSColor(pindropHex: "#6FDCAF") ?? .systemMint)
    static let bandHigh = Color(nsColor: NSColor(pindropHex: "#EFD9A8") ?? .systemYellow).opacity(0.75)
}

// MARK: - Band blobs (audio-reactive orb interior)

/// Phase state for the three band-driven blobs. Wobble and drift phases are
/// integrated per frame (dt-based) so churn speed can follow band energy without
/// phase jumps, and the levels get VU-meter ballistics (fast attack, slow
/// release) so the motion stays flowy instead of tracking every syllable spike.
final class OrbBlobModel {
    struct Blob {
        var wobblePhases: [Double]
        var driftPhase: Double
    }

    /// Integer harmonics keep each blob's outline closed (periodic in θ).
    static let harmonics: [Double] = [2, 3, 5]
    static let harmonicWeights: [Double] = [0.55, 0.30, 0.15]

    private(set) var blobs: [Blob]
    /// Smoothed low/mid/high levels, 0…1.
    private(set) var levels: [Double] = [0, 0, 0]
    private var lastTime: TimeInterval = 0

    init() {
        blobs = (0..<3).map { index in
            Blob(
                wobblePhases: [0.0, 2.1, 4.2].map { $0 + Double(index) * 1.3 },
                driftPhase: Double(index) * 2.09
            )
        }
    }

    func advance(to time: TimeInterval, bands: AudioBandLevels, overall: Float, isLive: Bool, isExcited: Bool) {
        let dt = lastTime == 0 ? 1.0 / 40.0 : min(0.1, max(0.0, time - lastTime))
        lastTime = time

        // Fall back to the overall level when band data isn't flowing (e.g. capture
        // backends that only report RMS) so the orb never looks dead while recording.
        var targets = [Double(bands.low), Double(bands.mid), Double(bands.high)]
        if targets.reduce(0, +) < 0.01 {
            let level = Double(overall)
            targets = [level, level * 0.7, level * 0.45]
        }
        if !isLive {
            if isExcited {
                // Hover: the orb perks up — a quicker, fuller pulse than the idle breath.
                let pulse = 0.34 + 0.10 * sin(time * 2.6)
                targets = [pulse, pulse * 0.78, pulse * 0.58]
            } else {
                // Idle: lazy drifting blobs with a slow breathing swell.
                let breath = 0.18 + 0.07 * sin(time * 1.15)
                targets = [breath, breath * 0.72, breath * 0.52]
            }
        }

        for index in levels.indices {
            let target = min(1.0, targets[index])
            let rate = target > levels[index] ? 9.0 : 2.0
            levels[index] += (target - levels[index]) * min(1.0, rate * dt)
        }

        for index in blobs.indices {
            let churn = 0.5 + levels[index] * 2.6
            for k in blobs[index].wobblePhases.indices {
                blobs[index].wobblePhases[k] += dt * churn * (0.8 + Double(k) * 0.5)
            }
            blobs[index].driftPhase += dt * (0.3 + levels[index] * 1.1)
        }
    }
}

/// The orb's interior: three translucent morphing blobs, one per frequency band,
/// drifting and churning with the voice under additive blending, plus a hot core
/// highlight — the flowy, organic look rather than a spiky trace.
struct OrbBlobsView: View {
    /// Deliberately NOT observed: the Canvas below polls band/level values on its
    /// own 40fps timeline, so per-audio-buffer `objectWillChange` invalidations
    /// would only add SwiftUI churn during recording.
    let state: FloatingIndicatorState
    let isLive: Bool
    let isExcited: Bool

    @State private var model = OrbBlobModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let blobColors = [OrbPalette.bandLow, OrbPalette.bandMid, OrbPalette.bandHigh]
    private static let baseRadiusFractions: [CGFloat] = [0.40, 0.34, 0.27]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 40.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                model.advance(
                    to: timeline.date.timeIntervalSinceReferenceDate,
                    bands: state.bandLevels,
                    overall: state.audioLevel,
                    isLive: isLive,
                    isExcited: isExcited
                )
                context.blendMode = .plusLighter

                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let scale = min(size.width, size.height) / 2
                for index in model.blobs.indices {
                    drawBlob(index: index, in: &context, center: center, scale: scale)
                }
                drawCore(in: &context, center: center, scale: scale)
            }
        }
        .allowsHitTesting(false)
    }

    private func drawBlob(index: Int, in context: inout GraphicsContext, center: CGPoint, scale: CGFloat) {
        let blob = model.blobs[index]
        let level = model.levels[index]
        let color = Self.blobColors[index]

        // The blob swells with its band and wanders around the orb centre.
        let radius = scale * Self.baseRadiusFractions[index] * (0.8 + level * 0.55)
        let wander = scale * (0.16 + level * 0.10)
        let blobCenter = CGPoint(
            x: center.x + cos(blob.driftPhase) * wander,
            y: center.y + sin(blob.driftPhase * 1.31 + Double(index)) * wander
        )
        let wobbleAmplitude = 0.10 + level * 0.35

        var path = Path()
        let steps = 72
        for step in 0...steps {
            let theta = Double(step) / Double(steps) * 2 * .pi
            var wobble = 0.0
            for (k, harmonic) in OrbBlobModel.harmonics.enumerated() {
                wobble += sin(harmonic * theta + blob.wobblePhases[k]) * OrbBlobModel.harmonicWeights[k]
            }
            let r = radius * (1 + wobble * wobbleAmplitude)
            let point = CGPoint(
                x: blobCenter.x + cos(theta) * r,
                y: blobCenter.y + sin(theta) * r
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()

        let shading = GraphicsContext.Shading.radialGradient(
            Gradient(colors: [color.opacity(0.72 + level * 0.2), color.opacity(0.05)]),
            center: blobCenter,
            startRadius: 0,
            endRadius: radius * 1.35
        )
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.6))
            layer.fill(path, with: shading)
        }
    }

    private func drawCore(in context: inout GraphicsContext, center: CGPoint, scale: CGFloat) {
        let energy = model.levels.reduce(0, +) / 3
        let radius = scale * (0.16 + energy * 0.16)
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let shading = GraphicsContext.Shading.radialGradient(
            Gradient(colors: [Color.white.opacity(0.55 + energy * 0.35), Color.white.opacity(0)]),
            center: center,
            startRadius: 0,
            endRadius: radius
        )
        context.fill(Path(ellipseIn: rect), with: shading)
    }
}

// MARK: - Previews

#Preview("Orb – Idle")       { orbPreview { _ in } }
#Preview("Orb – Hover")      { orbPreview { $0.isHovered = true } }
#Preview("Orb – Recording")  { orbPreview { $0.state.isRecording = true; $0.state.audioLevel = 0.65 } }
#Preview("Orb – Processing") { orbPreview { $0.state.isProcessing = true } }
#Preview("Orb – Streaming")  {
    orbPreview {
        $0.state.isRecording = true
        $0.state.audioLevel = 0.6
        $0.liveTranscript.begin()
        $0.liveTranscript.update(
            committed: "Remind me to review the release notes",
            tentative: "before thursday's build"
        )
    }
}

@MainActor
private func orbPreview(_ configure: (OrbFloatingIndicatorController) -> Void) -> some View {
    let controller = OrbFloatingIndicatorController(
        state: FloatingIndicatorState(),
        settingsStore: SettingsStore(),
        liveTranscript: LiveTranscriptState()
    )
    configure(controller)
    return OrbIndicatorView(controller: controller, state: controller.state, transcript: controller.liveTranscript)
        .frame(
            width: OrbFloatingIndicatorSize.medium.panelSize(for: .left).width,
            height: OrbFloatingIndicatorSize.medium.panelSize(for: .left).height
        )
        .background(AppColors.windowBackground)
}
