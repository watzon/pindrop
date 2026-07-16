//
//  OrbFloatingIndicator.swift
//  Pindrop
//
//  Created on 2026-07-06.
//
//  The Orb floating indicator: a liquid-glass orb resting in a screen corner
//  (bottom-right by default). Its interior renders three subtly offset,
//  audio-reactive frequency-band waveforms that rest flat below the input floor.
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

    static let hoverCollapseDelay: TimeInterval = 0.18
    static let hoverActivationInset: CGFloat = 22

    /// Movement (pt) past which a press on the orb/pill becomes a reposition
    /// drag instead of a tap.
    static let dragActivationDistance: CGFloat = 4

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

// MARK: - Hosting view

private final class OrbHostingView: NSHostingView<AnyView> {
    /// The panel reserves transparent space for the streaming pill; only the
    /// visible orb/pill surfaces should claim mouse events from the app below.
    var allowsHitTestingAtPoint: ((NSPoint) -> Bool)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard allowsHitTestingAtPoint?(point) ?? true else {
            return nil
        }
        return super.hitTest(point)
    }

    /// The panel never becomes key, so every click is a "first mouse"; without
    /// this the initial click can be consumed by window activation.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

// MARK: - Panel (owns tap, drag, and right-click routing)

/// ALL pointer interaction is intercepted in `sendEvent`, before AppKit
/// dispatches to the SwiftUI hosting view: NSHostingView stopped delivering
/// clicks to SwiftUI content in this borderless non-activating panel (taps,
/// gestures, and view-level mouse overrides all went dead), so the SwiftUI
/// `Button`s inside are decorative/accessibility-only. Window-level routing has
/// no such dependency: any event delivered to the panel is seen here first.
private final class OrbPanel: NSPanel {
    weak var interactionController: OrbFloatingIndicatorController?

    override func sendEvent(_ event: NSEvent) {
        guard let controller = interactionController else {
            super.sendEvent(event)
            return
        }
        switch event.type {
        case .rightMouseDown:
            if controller.handlePanelRightMouseDown(event) { return }
        case .otherMouseDown where event.buttonNumber == 2:
            if controller.handlePanelRightMouseDown(event) { return }
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            controller.handlePanelLeftMouseEvent(event)
        default:
            break
        }
        super.sendEvent(event)
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
    private var pointerMonitor: FloatingIndicatorPointerMonitor?
    private var hoverCollapseTimer: Timer?
    private var stateCancellable: AnyCancellable?

    private var actions = FloatingIndicatorActions()
    private var isVisible = false
    private var lastHoverContactAt: Date = .distantPast
    private var lastDragEndedAt: Date = .distantPast
    private var isPointerCursorActive = false
    private var dragStartMouseLocation: CGPoint?
    private var dragStartOffset: CGSize = .zero
    private var dragOffset: CGSize = .zero
    /// Mouse-down location of a possible reposition drag, pending the movement
    /// threshold. Set only when the press lands on the visible orb/pill.
    private var pendingDragStartScreenPoint: NSPoint?
    /// Debounces tap activations: taps arrive via panel routing today and would
    /// also arrive via the SwiftUI buttons if the hosting view's click delivery
    /// returns in a future macOS — one physical click must never toggle twice.
    private var lastTapAcceptedAt: Date = .distantPast
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
        stateCancellable = Publishers.CombineLatest4(
            state.$isRecording,
            state.$isProcessing,
            state.$isInputMuted,
            liveTranscript.$phase
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _, _ in
            guard let self else { return }
            self.updatePanelMousePassthrough()
            self.actions.onToastAnchorChanged?()
        }

    }

    func configure(actions: FloatingIndicatorActions) {
        self.actions = actions
    }

    func reloadLocalizedStrings() {
        contextMenu = makeContextMenu()
        hostingView?.rootView = makeRootView()
    }

    // MARK: FloatingIndicatorPresenting

    func toastAnchor() -> FloatingIndicatorToastAnchor? {
        guard isVisible else { return nil }
        let screen = lastScreen ?? preferredScreen()
        let panelFrame = panel?.frame ?? panelFrame(for: screen)
        let frames = visibleIndicatorFrames(for: panelFrame)
        let footprint = frames.pill.map(frames.orb.union) ?? frames.orb
        // Keep horizontal alignment on the sphere while avoiding the complete
        // vertical footprint of any recording or transcript pill.
        let rect = NSRect(
            x: frames.orb.minX,
            y: footprint.minY,
            width: frames.orb.width,
            height: footprint.height
        )
        return FloatingIndicatorToastAnchor(
            rect: rect,
            visibleFrame: screen.visibleFrame,
            edge: .automatic
        )
    }

    func showIdleIndicator() {
        pointerMonitor?.setPointerActivityEnabled(true)
        guard !isVisible else {
            panel?.orderFrontRegardless()
            updatePanelMousePassthrough()
            actions.onToastAnchorChanged?()
            return
        }
        show()
    }

    func showForCurrentState() {
        if !isVisible {
            show()
        } else {
            panel?.orderFrontRegardless()
            updatePanelMousePassthrough()
            actions.onToastAnchorChanged?()
        }
    }

    func startRecording() {
        isHovered = false
        cancelHoverCollapseTimer()
        pointerMonitor?.setPointerActivityEnabled(true)
        lastHoverContactAt = .distantPast
        state.startRecording()
        if !isVisible { show() }
        updatePanelMousePassthrough()
        actions.onToastAnchorChanged?()
    }

    func transitionToProcessing() {
        state.transitionToProcessing()
        cancelHoverCollapseTimer()
        pointerMonitor?.setPointerActivityEnabled(true)
        isHovered = false
        lastHoverContactAt = .distantPast
        updatePanelMousePassthrough()
        actions.onToastAnchorChanged?()
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
        guard let panel else {
            isVisible = false
            actions.onToastAnchorChanged?()
            return
        }
        isVisible = false
        actions.onToastAnchorChanged?()
        isHovered = false
        isDragging = false
        pendingDragStartScreenPoint = nil
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

    /// Tap on the orb toggles the session. Ignores taps during or just after a
    /// drag (a reposition nudge releases at its final position, which must not
    /// also toggle), and duplicate activations of the same click.
    func handleOrbTapped() {
        guard !isDragging, Date().timeIntervalSince(lastDragEndedAt) > 0.25 else { return }
        guard acceptTap() else { return }
        if state.isRecording {
            handleStopTapped()
        } else if !state.isProcessing {
            handleStartTapped()
        }
    }

    /// Entry point for the pill's stop control (panel routing and the SwiftUI
    /// button both land here).
    func handlePillStopTapped() {
        guard acceptTap() else { return }
        handleStopTapped()
    }

    /// `true` once per physical click; duplicate delivery paths are dropped.
    private func acceptTap() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastTapAcceptedAt) > 0.25 else { return false }
        lastTapAcceptedAt = now
        return true
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
        panel?.ignoresMouseEvents = false
        actions.onToastAnchorChanged?()
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
        actions.onToastAnchorChanged?()
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
        updatePanelMousePassthrough()
        actions.onToastAnchorChanged?()
        Log.ui.debug("Orb reposition drag ended offset=(\(dragOffset.width), \(dragOffset.height))")
    }

    // MARK: Panel event routing (see OrbPanel.sendEvent)

    /// Drives taps and the reposition drag from raw window events: a press on
    /// the orb/pill becomes a drag past the movement threshold, otherwise the
    /// release dispatches as a tap.
    fileprivate func handlePanelLeftMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let screenPoint = screenLocation(of: event)
            pendingDragStartScreenPoint =
                allowsHitTesting(atScreenPoint: screenPoint) ? screenPoint : nil
        case .leftMouseDragged:
            let screenPoint = screenLocation(of: event)
            if !isDragging {
                guard let start = pendingDragStartScreenPoint,
                      hypot(screenPoint.x - start.x, screenPoint.y - start.y)
                          >= OrbMetrics.dragActivationDistance else {
                    return
                }
                Log.ui.debug("Orb reposition drag began")
                beginDrag()
            }
            updateDrag(translation: .zero)
        case .leftMouseUp:
            let pressBeganOnIndicator = pendingDragStartScreenPoint != nil
            pendingDragStartScreenPoint = nil
            if isDragging {
                endDrag(translation: .zero)
            } else if pressBeganOnIndicator {
                handlePanelTap(atScreenPoint: screenLocation(of: event))
            }
        default:
            break
        }
    }

    /// Dispatches a completed click (press + sub-threshold release) to the
    /// control under the release point.
    private func handlePanelTap(atScreenPoint point: NSPoint) {
        guard isVisible, let panel else { return }
        let frames = visibleIndicatorFrames(for: panel.frame)

        if NSBezierPath(ovalIn: frames.orb).contains(point) {
            Log.ui.debug("Orb tapped via panel routing")
            handleOrbTapped()
            return
        }

        // The pill's only control is stop, shown while recording. Its control
        // row (timer + stop square) is the tap target; the transcript area of
        // the streaming pill stays inert.
        guard state.isRecording, let pillFrame = frames.pill else { return }
        let rowHeight = liveTranscript.phase == .inactive
            ? pillFrame.height
            : min(orbIndicatorSize.pillHeight + 5, pillFrame.height)
        let controlRow = NSRect(
            x: pillFrame.minX,
            y: pillFrame.maxY - rowHeight,
            width: pillFrame.width,
            height: rowHeight
        )
        if controlRow.contains(point) {
            Log.ui.debug("Pill stop tapped via panel routing")
            handlePillStopTapped()
        }
    }

    /// Handles a right-click (or middle-button equivalent) delivered to the
    /// panel. Returns `true` when consumed — menu shown, or suppressed during a
    /// session — so dispatch stops; clicks outside the visible orb/pill fall
    /// through to normal handling.
    fileprivate func handlePanelRightMouseDown(_ event: NSEvent) -> Bool {
        guard allowsHitTesting(atScreenPoint: screenLocation(of: event)) else {
            return false
        }
        guard isVisible, !state.isRecording, !state.isProcessing else { return true }
        Log.ui.debug("Orb context menu opened via panel right-click")
        showContextMenu()
        return true
    }

    private func screenLocation(of event: NSEvent) -> NSPoint {
        guard let window = event.window else { return NSEvent.mouseLocation }
        return window.convertToScreen(
            NSRect(origin: event.locationInWindow, size: .zero)
        ).origin
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

    private func showContextMenu() {
        guard let hostingView, let contextMenu else { return }
        isContextMenuOpen = true; isHovered = true; lastHoverContactAt = Date()
        panel?.ignoresMouseEvents = false
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
        actions.onToastAnchorChanged?()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === contextMenu else { return }
        isContextMenuOpen = false; lastHoverContactAt = Date()
        evaluateHover()
        updatePanelMousePassthrough()
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
        hostingView.allowsHitTestingAtPoint = { [weak self] point in
            self?.allowsHitTesting(at: point) ?? false
        }
        panel.contentView = hostingView
        panel.alphaValue = 0
        self.panel = panel; self.hostingView = hostingView
        self.isVisible = true; self.lastScreen = screen
        updatePanelMousePassthrough()
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : OrbMetrics.showDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        startHoverMonitoring()
        actions.onToastAnchorChanged?()
    }

    private func makePanel(contentRect: NSRect) -> NSPanel {
        let panel = OrbPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.interactionController = self
        panel.isFloatingPanel = true; panel.isOpaque = false
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear; panel.isMovable = false; panel.hasShadow = false
        panel.ignoresMouseEvents = true
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
        actions.onToastAnchorChanged?()
    }

    // MARK: Private — hover monitoring

    private func startHoverMonitoring() {
        if pointerMonitor == nil {
            pointerMonitor = FloatingIndicatorPointerMonitor(
                onPointerActivity: { [weak self] in
                    self?.monitorTick()
                },
                onScreenParametersChanged: { [weak self] in
                    self?.checkScreenPosition(force: true)
                }
            )
        }
        pointerMonitor?.setPointerActivityEnabled(true)
        pointerMonitor?.start()
        // Catch current pointer position immediately (no wait for first move).
        monitorTick()
    }

    private func stopHoverMonitoring() {
        pointerMonitor?.stop()
        pointerMonitor = nil
        cancelHoverCollapseTimer()
        lastHoverContactAt = .distantPast
    }

    /// Screen follow + hover on real pointer activity (and screen reconfiguration).
    /// Replaces the previous 60 Hz timer that allocated a MainActor Task every tick.
    private func monitorTick() {
        guard isVisible else { return }
        checkScreenPosition()
        evaluateHover()
        updatePanelMousePassthrough()
    }

    private func evaluateHover() {
        guard isVisible, !isDragging, !state.isRecording, !state.isProcessing else {
            cancelHoverCollapseTimer()
            return
        }
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let now = Date()
        let orbRect = orbScreenRect(for: panel.frame)
        let activationRect = orbRect.insetBy(dx: -OrbMetrics.hoverActivationInset, dy: -OrbMetrics.hoverActivationInset)
        if isHovered {
            if isContextMenuOpen || activationRect.contains(mouse) {
                lastHoverContactAt = now
                cancelHoverCollapseTimer()
                return
            }
            let timeOutside = now.timeIntervalSince(lastHoverContactAt)
            if timeOutside >= OrbMetrics.hoverCollapseDelay {
                cancelHoverCollapseTimer()
                setHoverState(false)
            } else {
                scheduleHoverCollapseIfNeeded(
                    after: OrbMetrics.hoverCollapseDelay - timeOutside
                )
            }
            return
        }
        cancelHoverCollapseTimer()
        if activationRect.contains(mouse) {
            lastHoverContactAt = now
            setHoverState(true)
        }
    }

    private func scheduleHoverCollapseIfNeeded(after delay: TimeInterval) {
        guard hoverCollapseTimer == nil else { return }
        let timer = Timer(timeInterval: max(0, delay), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleHoverCollapseTimerFired()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverCollapseTimer = timer
    }

    private func cancelHoverCollapseTimer() {
        hoverCollapseTimer?.invalidate()
        hoverCollapseTimer = nil
    }

    private func handleHoverCollapseTimerFired() {
        hoverCollapseTimer = nil
        guard isVisible, isHovered else { return }
        evaluateHover()
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

    private func visibleIndicatorFrames(
        for panelFrame: NSRect
    ) -> (orb: NSRect, pill: NSRect?, pillCornerRadius: CGFloat) {
        let isActive = state.isRecording || state.isProcessing
        let showsTranscript = liveTranscript.phase != .inactive && isActive

        let orbDiameter: CGFloat
        if state.isInputMuted {
            orbDiameter = orbIndicatorSize.orbIdleDiameter
        } else if state.isRecording || showsTranscript {
            orbDiameter = orbIndicatorSize.orbActiveDiameter
        } else if state.isProcessing {
            orbDiameter = orbIndicatorSize.orbHoverDiameter
        } else {
            orbDiameter = isHovered
                ? orbIndicatorSize.orbHoverDiameter
                : orbIndicatorSize.orbIdleDiameter
        }

        let orbSlotFrame = orbScreenRect(for: panelFrame)
        let orbFrame = NSRect(
            x: orbSlotFrame.midX - orbDiameter / 2,
            y: orbSlotFrame.midY - orbDiameter / 2,
            width: orbDiameter,
            height: orbDiameter
        )
        guard isActive else {
            return (orb: orbFrame, pill: nil, pillCornerRadius: 0)
        }

        let pillSize: CGSize
        if showsTranscript {
            pillSize = CGSize(
                width: orbIndicatorSize.pillStreamingWidth,
                height: orbIndicatorSize.pillStreamingHeight
            )
        } else if state.isRecording {
            pillSize = CGSize(
                width: orbIndicatorSize.pillRecordingWidth,
                height: orbIndicatorSize.pillHeight
            )
        } else {
            pillSize = CGSize(
                width: orbIndicatorSize.pillProcessingWidth,
                height: orbIndicatorSize.pillHeight
            )
        }

        let pillNearInset = orbIndicatorSize.orbActiveDiameter + OrbMetrics.pillSeparationGap
        let lift = showsTranscript ? 0 : orbIndicatorSize.pillLift
        let edgeInset = OrbMetrics.edgeInset
        let pillCenter: CGPoint
        switch pillExitEdge {
        case .left:
            pillCenter = CGPoint(
                x: panelFrame.maxX - edgeInset - pillNearInset - pillSize.width / 2,
                y: panelFrame.minY + edgeInset + lift + pillSize.height / 2
            )
        case .right:
            pillCenter = CGPoint(
                x: panelFrame.minX + edgeInset + pillNearInset + pillSize.width / 2,
                y: panelFrame.minY + edgeInset + lift + pillSize.height / 2
            )
        case .up:
            pillCenter = CGPoint(
                x: panelFrame.midX,
                y: panelFrame.minY + edgeInset + pillNearInset + pillSize.height / 2
            )
        case .down:
            pillCenter = CGPoint(
                x: panelFrame.midX,
                y: panelFrame.maxY - edgeInset - pillNearInset - pillSize.height / 2
            )
        }

        let pillFrame = NSRect(
            x: pillCenter.x - pillSize.width / 2,
            y: pillCenter.y - pillSize.height / 2,
            width: pillSize.width,
            height: pillSize.height
        )
        let pillCornerRadius = min(
            showsTranscript ? 16 : orbIndicatorSize.pillHeight / 2,
            min(pillSize.width, pillSize.height) / 2
        )
        return (orb: orbFrame, pill: pillFrame, pillCornerRadius: pillCornerRadius)
    }

    private func allowsHitTesting(at point: NSPoint) -> Bool {
        guard let hostingView,
              let window = hostingView.window else {
            return false
        }

        let windowPoint = hostingView.convert(point, to: nil)
        return allowsHitTesting(
            atScreenPoint: window.convertPoint(toScreen: windowPoint)
        )
    }

    private func allowsHitTesting(atScreenPoint screenPoint: NSPoint) -> Bool {
        guard isVisible, let panel else { return false }
        let frames = visibleIndicatorFrames(for: panel.frame)

        if NSBezierPath(ovalIn: frames.orb).contains(screenPoint) {
            return true
        }

        guard let pillFrame = frames.pill else { return false }
        return NSBezierPath(
            roundedRect: pillFrame,
            xRadius: frames.pillCornerRadius,
            yRadius: frames.pillCornerRadius
        ).contains(screenPoint)
    }

    private func updatePanelMousePassthrough() {
        guard isVisible, let panel else { return }
        let receivesMouseEvents = isDragging
            || isContextMenuOpen
            || allowsHitTesting(atScreenPoint: NSEvent.mouseLocation)
        let shouldIgnoreMouseEvents = !receivesMouseEvents
        if panel.ignoresMouseEvents != shouldIgnoreMouseEvents {
            panel.ignoresMouseEvents = shouldIgnoreMouseEvents
        }
    }

    private func checkScreenPosition(force: Bool = false) {
        guard isVisible, let panel else { return }
        let currentScreen = preferredScreen()
        if force || lastScreen?.pindrop_isSameDisplay(as: currentScreen) == false {
            lastScreen = currentScreen
            let newFrame = panelFrame(for: currentScreen)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0; context.allowsImplicitAnimation = false
                panel.setFrame(newFrame, display: false, animate: false)
            }
            updatePanelMousePassthrough()
            actions.onToastAnchorChanged?()
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
        // SwiftUI `.onHover` doesn't fire in this panel (see OrbPanel); the
        // pointing-hand affordance rides the same signal as the hover swell.
        setPointerCursorActive(hovering)
        if hovering { lastHoverContactAt = Date() }
        updatePanelMousePassthrough()
        actions.onToastAnchorChanged?()
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

/// Limits the hosting panel's interaction region to the visible orb and pill.
/// The panel remains larger than the rendered surface to provide room for the
/// pill animation, but empty panel space must not intercept clicks from apps
/// underneath it.
private struct OrbIndicatorHitRegion: Shape {
    let orbCenter: CGPoint
    let orbRadius: CGFloat
    let pillCenter: CGPoint
    let pillSize: CGSize
    let pillCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(
            in: CGRect(
                x: orbCenter.x - orbRadius,
                y: orbCenter.y - orbRadius,
                width: orbRadius * 2,
                height: orbRadius * 2
            )
        )

        guard pillSize.width > 0, pillSize.height > 0 else {
            return path
        }

        let pillRect = CGRect(
            x: pillCenter.x - pillSize.width / 2,
            y: pillCenter.y - pillSize.height / 2,
            width: pillSize.width,
            height: pillSize.height
        )
        path.addRoundedRect(
            in: pillRect,
            cornerSize: CGSize(
                width: min(pillCornerRadius, pillSize.width / 2),
                height: min(pillCornerRadius, pillSize.height / 2)
            ),
            style: .continuous
        )
        return path
    }
}

// MARK: - SwiftUI view

struct OrbIndicatorView: View {
    @ObservedObject var controller: OrbFloatingIndicatorController
    @ObservedObject var state: FloatingIndicatorState
    /// Not `@ObservedObject`: text partials only need to re-render `LiveTranscriptView`.
    /// Phase is mirrored into local state so layout transitions still track session
    /// begin/enhance/end without rebuilding the whole orb+pill shell on every token.
    let transcript: LiveTranscriptState
    @ObservedObject private var theme = PindropThemeController.shared
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var transcriptPhase: LiveTranscriptState.Phase = .inactive

    private var sz: OrbFloatingIndicatorSize { controller.orbIndicatorSize }
    private var exit: OrbPillExitEdge { controller.pillExitEdge }

    private var isActive: Bool { state.isRecording || state.isProcessing }
    private var showsTranscript: Bool { transcriptPhase != .inactive && isActive }
    private var showsPill: Bool { isActive }

    private var orbDiameter: CGFloat {
        if state.isInputMuted { return sz.orbIdleDiameter }
        if state.isRecording || showsTranscript { return sz.orbActiveDiameter }
        if state.isProcessing { return sz.orbHoverDiameter }
        return controller.isHovered ? sz.orbHoverDiameter : sz.orbIdleDiameter
    }

    private var waveformPalette: OrbWaveformPalette {
        // `theme.revision` invalidates only on real theme/appearance changes.
        // Audio/transcript/duration ticks must reuse the resolved palette.
        let _ = theme.revision
        let appearance = NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let key = isDark
            ? PindropThemeStorageKeys.darkThemePresetID
            : PindropThemeStorageKeys.lightThemePresetID
        return OrbWaveformPalette.cached(
            presetID: UserDefaults.standard.string(forKey: key),
            variant: isDark ? .dark : .light,
            themeRevision: theme.revision
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
                    // Undersized while the blob fill is on trial: the dark disc stays
                    // hidden behind the opaque blob's troughs but still anchors the
                    // pill's liquid bridge during pop-out.
                    orbRadius: orbDiameter / 2 * 0.62,
                    pillCenter: pillCenterInPanel,
                    pillHalfWidth: pillSize.width / 2,
                    pillHalfHeight: pillSize.height / 2,
                    pillCornerRadius: pillCornerRadius
                )
            )
            .contentShape(
                OrbIndicatorHitRegion(
                    orbCenter: orbCenterInPanel,
                    orbRadius: orbDiameter / 2,
                    pillCenter: pillCenterInPanel,
                    pillSize: pillSize,
                    pillCornerRadius: pillCornerRadius
                )
            )
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82), value: showsPill)
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82), value: showsTranscript)
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84), value: isActive)
            .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.85), value: orbDiameter)
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82), value: exit)
            .onAppear { transcriptPhase = transcript.phase }
            .onReceive(transcript.$phase) { transcriptPhase = $0 }
            // Reposition dragging is intentionally NOT a SwiftUI gesture: it is
            // driven from raw window events in OrbPanel.sendEvent, which keeps
            // working regardless of how the hosting view routes gestures.
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
        }
    }

    private var orbContent: some View {
        Button {
            controller.handleOrbTapped()
        } label: {
            OrbBlobFillView(
                palette: waveformPalette,
                // Closure, not values: meters are deliberately non-@Published, so
                // the blob timeline polls them without invalidating the orb shell.
                sample: { [weak state] _ in
                    (state?.bandLevels ?? .zero, state?.audioLevel ?? 0)
                },
                isHovered: controller.isHovered,
                isRecording: state.isRecording,
                isProcessing: state.isProcessing,
                isMuted: state.isInputMuted
            )
            .frame(width: orbDiameter, height: orbDiameter)
            .shadow(
                color: waveformPalette.glowColor.opacity(state.isInputMuted ? 0 : (controller.isHovered ? 1 : 0.78)),
                radius: state.isRecording ? 26 : 18,
                y: state.isRecording ? 8 : 6
            )
            .opacity(state.isInputMuted ? 0.4 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .onHover { controller.setPointerCursorActive($0) }
        .accessibilityLabel(localized("Pindrop Orb", locale: locale))
        .accessibilityValue(
            localized(
                state.isInputMuted
                    ? "Microphone muted"
                    : (state.isRecording ? "Recording" : (state.isProcessing ? "Transcribing…" : "Ready")),
                locale: locale
            )
        )
        // Floating indicators stay non-key by design; the global hotkey is the keyboard path.
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

                Button { controller.handlePillStopTapped() } label: {
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

/// Converts the RMS-derived, AGC-normalized meters into restrained waveform
/// amplitudes. The input floor acts as the visual equivalent of a noise gate:
/// below it every band resolves to exactly zero, so all three traces stay flat.
enum OrbWaveformResponse {
    static let baselineLevel: Float = 0.07
    static let bandFloor: Float = 0.025
    static let fullResponseLevel: Float = 0.28
    static let fullBandLevel: Float = 0.72
    static let maximumResponse: Float = 0.92

    static func levels(bands: AudioBandLevels, overall: Float) -> AudioBandLevels {
        let inputResponse = smoothstep(
            edge0: baselineLevel,
            edge1: fullResponseLevel,
            value: overall
        )
        guard inputResponse > 0 else { return .zero }

        func response(for band: Float) -> Float {
            let bandResponse = smoothstep(
                edge0: bandFloor,
                edge1: fullBandLevel,
                value: band
            )
            return maximumResponse * bandResponse * inputResponse
        }

        return AudioBandLevels(
            low: response(for: bands.low),
            mid: response(for: bands.mid),
            high: response(for: bands.high)
        )
    }

    private static func smoothstep(edge0: Float, edge1: Float, value: Float) -> Float {
        let t = min(1, max(0, (value - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}

struct OrbGlassFillView: View {
    let palette: OrbWaveformPalette
    /// Sampled once per timeline tick — see the call sites for why this is a closure.
    let sample: (Date) -> (bands: AudioBandLevels, overall: Float)
    let isHovered: Bool
    let isRecording: Bool
    let isProcessing: Bool
    let isMuted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Shader time must be app-relative: absolute reference-date seconds (~8e8) exceed
    /// Float32 precision (ulp ≈ 32 s), which would freeze the waveform phase.
    private static let animationEpoch = Date.timeIntervalSinceReferenceDate

    private var waveformIntensity: Float {
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
                let meter = isRecording && !isMuted && !reduceMotion
                    ? sample(timeline.date)
                    : (bands: AudioBandLevels.zero, overall: Float.zero)
                let waveformLevels = OrbWaveformResponse.levels(
                    bands: meter.bands,
                    overall: meter.overall
                )

                Rectangle()
                    .fill(Color.white)
                    .colorEffect(
                        ShaderLibrary.orbGlassFill(
                            .float2(proxy.size),
                            .float(Float(baseTime * speed)),
                            .color(palette.primaryColor),
                            .color(palette.secondaryColor),
                            .float(waveformIntensity),
                            .float(isMuted ? 1 : 0),
                            .float(waveformLevels.low),
                            .float(waveformLevels.mid),
                            .float(waveformLevels.high)
                        )
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Amorphous blob fill (website-orb port, on trial)

/// The pindrop.dev orb, ported to the indicator: an amorphous blob whose
/// outline undulates through layered sines and swells with the live input
/// level. Replaces the circular glass fill + interior waveform traces with
/// whole-body motion; one Canvas path per frame instead of a per-pixel
/// shader pass, so it renders cheaper than `OrbGlassFillView`.
private struct OrbBlobFillView: View {
    let palette: OrbWaveformPalette
    /// Sampled once per timeline tick — see the call site for why this is a closure.
    let sample: (Date) -> (bands: AudioBandLevels, overall: Float)
    let isHovered: Bool
    let isRecording: Bool
    let isProcessing: Bool
    let isMuted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Shader-time rule applies here too: keep time app-relative so phase
    /// precision never degrades.
    private static let animationEpoch = Date.timeIntervalSinceReferenceDate

    private static let vertexCount = 14
    /// Deterministic per-vertex phases/speeds (golden-angle spread), so the
    /// blob's character is stable across shell re-renders and app launches.
    private static let phases: [Double] = (0..<vertexCount).map { (index: Int) -> Double in
        let raw: Double = Double(index) * 2.399963
        return raw.truncatingRemainder(dividingBy: Double.pi * 2)
    }
    private static let speeds: [Double] = (0..<vertexCount).map { (index: Int) -> Double in
        let seed: Int = (index * 73 + 19) % 97
        let fraction: Double = Double(seed) / 97.0
        return 0.55 + 0.5 * fraction
    }

    /// Eased meters persisted across ticks without invalidating the view.
    /// Fast attack / slow release, so plosives read instantly and the body
    /// relaxes rather than snapping shut between words.
    private final class LevelSmoother {
        var level: Double = 0
        var mid: Double = 0
        var high: Double = 0

        func advance(level levelTarget: Double, mid midTarget: Double, high highTarget: Double) {
            step(&level, toward: levelTarget)
            step(&mid, toward: midTarget)
            step(&high, toward: highTarget)
        }

        private func step(_ current: inout Double, toward target: Double) {
            let rate = target > current ? 0.5 : 0.10
            current += (target - current) * rate
        }
    }
    @State private var smoother = LevelSmoother()

    private var animationInterval: TimeInterval {
        if isRecording && !isMuted { return 1.0 / 60.0 }
        if isProcessing || isHovered { return 1.0 / 30.0 }
        return 1.0 / 8.0
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: animationInterval, paused: reduceMotion || isMuted)) { timeline in
            Canvas { context, size in
                let time = reduceMotion
                    ? 0
                    : timeline.date.timeIntervalSinceReferenceDate - Self.animationEpoch
                let meter = (isRecording && !isMuted && !reduceMotion)
                    ? sample(timeline.date)
                    : (bands: AudioBandLevels.zero, overall: Float.zero)
                // Same visual noise gate as the waveform traces: below the input
                // floor the blob only breathes.
                let shaped = OrbWaveformResponse.levels(bands: meter.bands, overall: meter.overall)
                smoother.advance(
                    level: Self.smoothstep(edge0: 0.06, edge1: 0.24, value: Double(meter.overall)),
                    mid: Double(shaped.mid) / Double(OrbWaveformResponse.maximumResponse),
                    high: Double(shaped.high) / Double(OrbWaveformResponse.maximumResponse)
                )

                draw(
                    in: context,
                    size: size,
                    time: time,
                    level: smoother.level,
                    mid: smoother.mid,
                    high: smoother.high
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(
        in context: GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        level: Double,
        mid: Double,
        high: Double
    ) {
        let cx = size.width / 2
        let cy = size.height / 2
        let half = min(size.width, size.height) / 2
        // Budgeted so the loudest excursion stays inside the canvas:
        // 0.84 × (1 + 0.022 + 0.158) ≈ 0.99 — the blob can never clip flat.
        let base = half * (0.76 + level * 0.08)
        let breath = sin(time * 0.9) * 0.022
        let wobble = 0.028 + mid * 0.13
        // Processing reads calmer, matching the old fill's slowed phase.
        let speedScale = isProcessing ? 0.45 : 1.0
        let n = Self.vertexCount

        var points: [CGPoint] = []
        points.reserveCapacity(n)
        for i in 0..<n {
            let angle = (Double(i) / Double(n)) * .pi * 2
            // Two slow layers carry the idle character; the fast third layer
            // only exists while the high band is hot, so sibilants shimmer.
            let noise =
                sin(time * Self.speeds[i] * speedScale + Self.phases[i]) * 0.55 +
                sin(time * Self.speeds[i] * 1.7 * speedScale + Self.phases[i] * 2.3) * 0.30 +
                sin(time * Self.speeds[i] * 4.3 + Self.phases[i] * 3.1) * 0.15 * high
            let radius = base * (1 + breath + noise * wobble)
            points.append(CGPoint(x: cx + cos(angle) * radius, y: cy + sin(angle) * radius))
        }

        var path = Path()
        for i in 0..<n {
            let current = points[i]
            let next = points[(i + 1) % n]
            let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            if i == 0 {
                path.move(to: mid)
            } else {
                path.addQuadCurve(to: mid, control: current)
            }
        }
        let first = points[0]
        let second = points[1]
        path.addQuadCurve(
            to: CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2),
            control: first
        )
        path.closeSubpath()

        let resolved = Self.resolvedPalette(for: palette)

        // 1. The jewel: lit from the upper left, hue rotating deeper toward the
        //    rim (that rotation, not plain darkening, is what reads as depth).
        context.fill(
            path,
            with: .radialGradient(
                resolved.jewel,
                center: CGPoint(x: cx - base * 0.30, y: cy - base * 0.34),
                startRadius: base * 0.08,
                endRadius: base * 1.18
            )
        )

        // 2. Rim shading from the lower right, inside the silhouette only:
        //    gives the body a shadowed underside and real volume.
        context.fill(
            path,
            with: .radialGradient(
                resolved.rimShade,
                center: CGPoint(x: cx + base * 0.55, y: cy + base * 0.62),
                startRadius: base * 0.3,
                endRadius: base * 1.45
            )
        )

        // 3. Specular sheen where the light hits.
        let sheenCenter = CGPoint(x: cx - base * 0.38, y: cy - base * 0.44)
        let sheen = Path(ellipseIn: CGRect(
            x: sheenCenter.x - base * 0.34,
            y: sheenCenter.y - base * 0.28,
            width: base * 0.68,
            height: base * 0.56
        ))
        context.fill(
            sheen,
            with: .radialGradient(
                resolved.sheen,
                center: sheenCenter,
                startRadius: 0,
                endRadius: base * 0.36
            )
        )
    }

    // MARK: Resolved palette (derived from the theme accent, cached per hue)

    private struct ResolvedBlobPalette {
        let jewel: Gradient
        let rimShade: Gradient
        let sheen: Gradient
    }

    nonisolated(unsafe) private static var paletteCache: [String: ResolvedBlobPalette] = [:]
    private static let paletteCacheLock = NSLock()

    private static func resolvedPalette(for palette: OrbWaveformPalette) -> ResolvedBlobPalette {
        paletteCacheLock.lock()
        defer { paletteCacheLock.unlock() }
        if let cached = paletteCache[palette.primaryHex] { return cached }

        let hex = palette.primaryHex
        let jewel = Gradient(stops: [
            .init(color: shifted(hex, hue: 0.015, sat: 0.40, bri: 1.30), location: 0),
            .init(color: shifted(hex, hue: 0.005, sat: 0.75, bri: 1.10), location: 0.30),
            .init(color: shifted(hex, hue: 0, sat: 1.0, bri: 1.0), location: 0.58),
            .init(color: shifted(hex, hue: -0.035, sat: 1.18, bri: 0.70), location: 0.82),
            .init(color: shifted(hex, hue: -0.065, sat: 1.28, bri: 0.44), location: 1),
        ])
        let shadow = shifted(hex, hue: -0.075, sat: 1.2, bri: 0.28)
        let rimShade = Gradient(stops: [
            .init(color: shadow.opacity(0), location: 0),
            .init(color: shadow.opacity(0), location: 0.45),
            .init(color: shadow.opacity(0.38), location: 1),
        ])
        let highlight = shifted(hex, hue: 0.02, sat: 0.18, bri: 1.4)
        let sheenGradient = Gradient(stops: [
            .init(color: highlight.opacity(0.55), location: 0),
            .init(color: highlight.opacity(0), location: 1),
        ])

        let resolved = ResolvedBlobPalette(jewel: jewel, rimShade: rimShade, sheen: sheenGradient)
        paletteCache[palette.primaryHex] = resolved
        return resolved
    }

    /// HSB-space shift off the theme accent. Hue wraps; saturation and
    /// brightness clamp to [0, 1].
    private static func shifted(_ hex: String, hue hueDelta: CGFloat, sat satScale: CGFloat, bri briScale: CGFloat) -> Color {
        guard let ns = (NSColor(pindropHex: hex) ?? .controlAccentColor).usingColorSpace(.deviceRGB) else {
            return Color(nsColor: .controlAccentColor)
        }
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var hue = (h + hueDelta).truncatingRemainder(dividingBy: 1)
        if hue < 0 { hue += 1 }
        return Color(
            hue: Double(hue),
            saturation: Double(min(1, max(0, s * satScale))),
            brightness: Double(min(1, max(0, b * briScale)))
        )
    }

    private static func smoothstep(edge0: Double, edge1: Double, value: Double) -> Double {
        let t = min(1, max(0, (value - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}

// MARK: - Palette

struct OrbWaveformPalette: Equatable {
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

    private struct CacheKey: Hashable {
        let presetID: String
        let variant: PindropThemeVariant
        let themeRevision: Int
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedThemeRevision: Int?
    // A revision change invalidates all prior palettes. Keeping only the current
    // revision prevents accessibility/theme refreshes from growing this cache forever.
    nonisolated(unsafe) private static var cache: [CacheKey: OrbWaveformPalette] = [:]

    /// Cached by preset ID, appearance variant, and theme revision so root
    /// audio/transcript/duration invalidations reuse the resolved palette.
    static func cached(
        presetID: String?,
        variant: PindropThemeVariant,
        themeRevision: Int
    ) -> OrbWaveformPalette {
        let resolvedPresetID = presetID ?? PindropThemePresetCatalog.defaultPresetID
        let key = CacheKey(
            presetID: resolvedPresetID,
            variant: variant,
            themeRevision: themeRevision
        )

        cacheLock.lock()
        if cachedThemeRevision != themeRevision {
            cache.removeAll(keepingCapacity: true)
            cachedThemeRevision = themeRevision
        }
        if let cached = cache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let palette = forPresetID(resolvedPresetID, variant: variant)

        cacheLock.lock()
        if cachedThemeRevision == themeRevision {
            cache[key] = palette
        }
        cacheLock.unlock()
        return palette
    }

    static func forPresetID(
        _ presetID: String?,
        variant: PindropThemeVariant = .light
    ) -> OrbWaveformPalette {
        switch presetID ?? PindropThemePresetCatalog.defaultPresetID {
        case "library":
            return OrbWaveformPalette(
                primaryHex: "#6FDCAF",
                secondaryHex: "#EFD9A8",
                glowHex: "#1F6D53",
                glowOpacity: 0.45
            )
        case "pindrop":
            return OrbWaveformPalette(
                primaryHex: "#F2B54A",
                secondaryHex: "#F7E3BC",
                glowHex: "#F2B54A",
                glowOpacity: 0.35
            )
        case "harbor":
            return OrbWaveformPalette(
                primaryHex: "#4FB3D1",
                secondaryHex: "#CFE9F0",
                glowHex: "#14708A",
                glowOpacity: 0.40
            )
        default:
            // Derived presets track the catalog accent for the active variant so the
            // waveform hue matches the rest of the themed UI (spec §15).
            let accent = PindropThemePresetCatalog
                .profile(for: presetID, variant: variant)
                .accentHex
            return OrbWaveformPalette(
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

/// Literal dark floating-surface colors. The waveform itself is theme-driven by
/// `OrbWaveformPalette`; the body remains stable over arbitrary desktop content.
enum OrbPalette {
    static let surface = Color(nsColor: NSColor(pindropHex: "#181511") ?? .black).opacity(0.92)
    static let rim = Color.white.opacity(0.12)
    static let rimSoft = Color.white.opacity(0.14)
}


// MARK: - Previews

#Preview("Orb – Idle")       { orbPreview { _ in } }
#Preview("Orb – Hover")      { orbPreview { $0.isHovered = true } }
#Preview("Orb – Recording")  { orbPreview { $0.state.isRecording = true; $0.state.updateAudioLevel(1.0) } }
#Preview("Orb – Processing") { orbPreview { $0.state.isProcessing = true } }
#Preview("Orb – Streaming")  {
    orbPreview {
        $0.state.isRecording = true
        $0.state.updateAudioLevel(1.0)
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
