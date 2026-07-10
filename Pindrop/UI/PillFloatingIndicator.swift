//
//  PillFloatingIndicator.swift
//  Pindrop
//
//  Created on 2026-01-29.
//

import SwiftUI
import AppKit
import Combine

private final class PillHostingView: NSHostingView<AnyView> {
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

@MainActor
final class PillFloatingIndicatorController: NSObject, ObservableObject, NSMenuDelegate, FloatingIndicatorPresenting {
    let type: FloatingIndicatorType = .pill
    let state: FloatingIndicatorState
    let liveTranscript: LiveTranscriptState
    private let settingsStore: SettingsStore
    private var phaseCancellables = Set<AnyCancellable>()

    private enum LayoutState {
        case compact
        case hover
        case recording
        case processing
    }

    private enum LayoutMetrics {
        static let compactSize = CGSize(width: 44, height: 10)
        static let compactPillBottomPadding: CGFloat = 6
        static let hoverSize = CGSize(width: 332, height: 68)
        static let recordingSize = CGSize(width: 178, height: 44)
        static let processingSize = CGSize(width: 160, height: 44)
        /// Panel size while the live transcript card is showing (overlay streaming).
        static let streamingSize = CGSize(width: 282, height: 118)
        /// The transcript card itself (pill row + transcript area), bottom-aligned in
        /// the panel like the plain recording pill.
        static let streamingCardSize = CGSize(width: 270, height: 104)

        static let compactBottomInset: CGFloat = 6
        static let expandedBottomInset: CGFloat = 10

        static let hoverActivationInsetX: CGFloat = 20
        static let hoverActivationInsetY: CGFloat = 20
        static let hoverRetentionInsetX: CGFloat = 10
        static let hoverRetentionInsetY: CGFloat = 8
        static let hoverCollapseDelay: TimeInterval = 0.14
        static let hoverMonitorInterval: TimeInterval = 1.0 / 60.0
        static let hoverTooltipDelay: TimeInterval = 0.08
    }

    private var panel: NSPanel?
    private var hostingView: PillHostingView?
    private var contextMenu: NSMenu?
    private var microphoneMenu: NSMenu?
    private var microphoneItem: NSMenuItem?
    private var languageMenu: NSMenu?
    private var languageItem: NSMenuItem?

    @Published var isHovered: Bool = false
    @Published var isHoverTooltipVisible: Bool = false
    @Published private(set) var isDragging = false
    private var hoverIntentTimer: Timer?
    private var hoverTooltipTimer: Timer?
    private var lastScreen: NSScreen?
    private var lastHoverContactAt: Date = .distantPast
    private var isContextMenuOpen = false
    private var dragStartMouseLocation: CGPoint?
    private var dragStartOffset: CGSize = .zero
    private var dragOffset: CGSize = .zero

    private var actions = FloatingIndicatorActions()

    private var isVisible: Bool = false

    init(
        state: FloatingIndicatorState,
        settingsStore: SettingsStore,
        liveTranscript: LiveTranscriptState
    ) {
        self.state = state
        self.settingsStore = settingsStore
        self.liveTranscript = liveTranscript
        self.dragOffset = settingsStore.pillFloatingIndicatorOffset
        super.init()
        contextMenu = makeContextMenu()

        // The panel swaps to `streamingSize` while the live transcript is active —
        // resize on phase transitions only, never on text growth.
        liveTranscript.$phase
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshLayout(animated: true, duration: 0.24)
            }
            .store(in: &phaseCancellables)
    }

    func configure(actions: FloatingIndicatorActions) {
        self.actions = actions
    }

    func reloadLocalizedStrings() {
        contextMenu = makeContextMenu()
        hostingView?.rootView = makeRootView(isCompact: true)
        hostingView?.userInterfaceLayoutDirection = .leftToRight
    }

    private var layoutState: LayoutState {
        if state.isRecording {
            return .recording
        }

        if state.isProcessing {
            return .processing
        }

        return isHovered ? .hover : .compact
    }

    func showIdleIndicator() {
        guard !isVisible else {
            refreshLayout(animated: false)
            panel?.orderFrontRegardless()
            return
        }

        guard let screen = Optional(preferredScreen()) else { return }

        let state = layoutState

        let panel = createPanel(contentRect: frame(for: screen, state: state))

        let contentView = PillIndicatorView(
            controller: self,
            state: self.state,
            transcript: liveTranscript,
            isCompact: true
        )
        let hostingView = makeHostingView(for: contentView, size: size(for: state))
        self.hostingView = hostingView

        panel.contentView = hostingView
        self.panel = panel

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        isVisible = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        lastScreen = screen
        startHoverIntentMonitoring()
    }

    func showForCurrentState() {
        if !isVisible {
            showIdleIndicator()
        } else {
            refreshLayout(animated: true, duration: 0.24)
        }
    }

    private func startHoverIntentMonitoring() {
        hoverIntentTimer?.invalidate()
        hoverIntentTimer = Timer.pindrop_scheduleRepeating(interval: LayoutMetrics.hoverMonitorInterval) { [weak self] _ in
            Task { @MainActor in
                self?.pillMonitorTick()
            }
        }
    }

    /// Screen follow + hover: runs on the main run loop in `.common` modes (same cadence as hover),
    /// so the pill tracks the cursor across displays while idle, recording, or processing.
    private func pillMonitorTick() {
        guard isVisible else { return }
        checkAndUpdateScreenPosition()
        evaluateHoverIntent()
    }

    private func stopHoverIntentMonitoring() {
        hoverIntentTimer?.invalidate()
        hoverIntentTimer = nil
        lastHoverContactAt = .distantPast
    }

    private func scheduleHoverTooltipReveal() {
        hoverTooltipTimer?.invalidate()
        hoverTooltipTimer = Timer.scheduledTimer(withTimeInterval: LayoutMetrics.hoverTooltipDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                guard self.isHovered, !self.state.isRecording, !self.state.isProcessing, !self.isContextMenuOpen else { return }
                self.isHoverTooltipVisible = true
            }
        }
    }

    private func hideHoverTooltip() {
        hoverTooltipTimer?.invalidate()
        hoverTooltipTimer = nil
        isHoverTooltipVisible = false
    }

    private func makeContextMenu() -> NSMenu {
        let locale = settingsStore.selectedAppLocale.locale
        let menu = NSMenu(title: localized("Pindrop Pill", locale: locale))
        menu.delegate = self

        let hideForOneHourItem = NSMenuItem(
            title: localized("Hide this for 1 hour", locale: locale),
            action: #selector(handleHideForOneHourMenuItem),
            keyEquivalent: ""
        )
        hideForOneHourItem.target = self
        menu.addItem(hideForOneHourItem)

        let reportIssueItem = NSMenuItem(
            title: localized("Report an issue", locale: locale),
            action: #selector(handleReportIssueMenuItem),
            keyEquivalent: ""
        )
        reportIssueItem.target = self
        menu.addItem(reportIssueItem)

        let goToSettingsItem = NSMenuItem(
            title: localized("Go to settings", locale: locale),
            action: #selector(handleGoToSettingsMenuItem),
            keyEquivalent: ""
        )
        goToSettingsItem.target = self
        menu.addItem(goToSettingsItem)

        menu.addItem(.separator())

        let microphoneMenu = NSMenu(title: localized("Change microphone", locale: locale))
        self.microphoneMenu = microphoneMenu

        let microphoneItem = NSMenuItem(title: localized("Change microphone", locale: locale), action: nil, keyEquivalent: "")
        microphoneItem.submenu = microphoneMenu
        self.microphoneItem = microphoneItem
        menu.addItem(microphoneItem)

        let languageMenu = NSMenu(title: localized("Select language", locale: locale))
        self.languageMenu = languageMenu

        let languageItem = NSMenuItem(title: localized("Select language", locale: locale), action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu
        self.languageItem = languageItem
        menu.addItem(languageItem)

        menu.addItem(.separator())

        let viewHistoryItem = NSMenuItem(
            title: localized("View transcript history", locale: locale),
            action: #selector(handleViewTranscriptHistoryMenuItem),
            keyEquivalent: ""
        )
        viewHistoryItem.target = self
        menu.addItem(viewHistoryItem)

        let pasteLastTranscriptItem = NSMenuItem(
            title: localized("Paste last transcript ⌃⌘V", locale: locale),
            action: #selector(handlePasteLastTranscriptMenuItem),
            keyEquivalent: ""
        )
        pasteLastTranscriptItem.target = self
        menu.addItem(pasteLastTranscriptItem)

        refreshContextMenuState()
        applyInterfaceLayoutDirection(to: menu, locale: locale)

        return menu
    }

    private func refreshContextMenuState() {
        refreshMicrophoneMenuItems()
        refreshLanguageMenuItems()
    }

    private func refreshMicrophoneMenuItems() {
        guard let microphoneMenu = microphoneMenu else { return }

        microphoneMenu.removeAllItems()

        let selectedUID = actions.selectedInputDeviceUIDProvider?() ?? ""
        let availableDevices = actions.availableInputDevicesProvider?() ?? []

        let systemDefaultItem = NSMenuItem(
            title: localized("System Default", locale: settingsStore.selectedAppLocale.locale),
            action: #selector(handleSelectInputDeviceMenuItem(_:)),
            keyEquivalent: ""
        )
        systemDefaultItem.target = self
        systemDefaultItem.representedObject = ""
        systemDefaultItem.state = selectedUID.isEmpty ? NSControl.StateValue.on : NSControl.StateValue.off
        microphoneMenu.addItem(systemDefaultItem)

        if !availableDevices.isEmpty {
            microphoneMenu.addItem(.separator())
        }

        for device in availableDevices {
            let item = NSMenuItem(
                title: device.displayName,
                action: #selector(handleSelectInputDeviceMenuItem(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device.uid
            item.state = device.uid == selectedUID ? NSControl.StateValue.on : NSControl.StateValue.off
            microphoneMenu.addItem(item)
        }

        if !selectedUID.isEmpty, !availableDevices.contains(where: { $0.uid == selectedUID }) {
            microphoneMenu.addItem(.separator())

            let unavailableItem = NSMenuItem(title: localized("Unavailable device", locale: settingsStore.selectedAppLocale.locale), action: nil, keyEquivalent: "")
            unavailableItem.isEnabled = false
            unavailableItem.state = NSControl.StateValue.on
            microphoneMenu.addItem(unavailableItem)
        }

        microphoneItem?.isEnabled = true
    }

    private func refreshLanguageMenuItems() {
        guard let languageMenu = languageMenu else { return }

        languageMenu.removeAllItems()

        let selectedLanguage = actions.selectedLanguageProvider?() ?? .automatic
        let tier1Languages = AppLanguage.allCases.filter(\.isSelectable)
        let tier2Languages = AppLanguage.allCases.filter { !$0.isSelectable }

        for language in tier1Languages {
            let item = NSMenuItem(
                title: language.displayName(locale: settingsStore.selectedAppLocale.locale),
                action: #selector(handleSelectLanguageMenuItem(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = language.rawValue
            item.state = selectedLanguage == language ? .on : .off
            languageMenu.addItem(item)
        }

        if !tier2Languages.isEmpty {
            languageMenu.addItem(.separator())

            let upcomingItem = NSMenuItem(title: localized("Coming Soon", locale: settingsStore.selectedAppLocale.locale), action: nil, keyEquivalent: "")
            upcomingItem.isEnabled = false
            languageMenu.addItem(upcomingItem)

            for language in tier2Languages {
                let item = NSMenuItem(title: language.pickerLabel(locale: settingsStore.selectedAppLocale.locale), action: nil, keyEquivalent: "")
                item.isEnabled = false
                languageMenu.addItem(item)
            }
        }

        languageItem?.isEnabled = true
    }

    @objc
    private func handleHideForOneHourMenuItem() {
        actions.onHideForOneHour?()
    }

    @objc
    private func handleReportIssueMenuItem() {
        actions.onReportIssue?()
    }

    @objc
    private func handleGoToSettingsMenuItem() {
        actions.onGoToSettings?()
    }

    @objc
    private func handleViewTranscriptHistoryMenuItem() {
        actions.onViewTranscriptHistory?()
    }

    @objc
    private func handlePasteLastTranscriptMenuItem() {
        Task { @MainActor in
            await actions.onPasteLastTranscript?()
        }
    }

    @objc
    private func handleSelectInputDeviceMenuItem(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        actions.onSelectInputDeviceUID?(uid)
    }

    @objc
    private func handleSelectLanguageMenuItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue) else { return }
        actions.onSelectLanguage?(language)
        refreshLanguageMenuItems()
    }

    private func evaluateHoverIntent() {
        guard isVisible, !isDragging, !state.isRecording, !state.isProcessing else { return }
        guard let panel = panel else { return }

        let mouseLocation = NSEvent.mouseLocation
        let now = Date()

        if isContextMenuOpen {
            lastHoverContactAt = now
            return
        }

        let activationRect = compactPillFrame(in: panel.frame).insetBy(
            dx: -LayoutMetrics.hoverActivationInsetX,
            dy: -LayoutMetrics.hoverActivationInsetY
        )
        let retentionRect = panel.frame.insetBy(
            dx: -LayoutMetrics.hoverRetentionInsetX,
            dy: -LayoutMetrics.hoverRetentionInsetY
        )

        if isHovered {
            if retentionRect.contains(mouseLocation) {
                lastHoverContactAt = now
                return
            }

            let timeOutside = now.timeIntervalSince(lastHoverContactAt)
            if timeOutside >= LayoutMetrics.hoverCollapseDelay {
                setHoverState(false)
            }
            return
        }

        if activationRect.contains(mouseLocation) {
            lastHoverContactAt = now
            setHoverState(true)
        }
    }

    private func compactPillFrame(in panelFrame: NSRect) -> NSRect {
        let width = LayoutMetrics.compactSize.width
        let height = LayoutMetrics.compactSize.height

        return NSRect(
            x: panelFrame.midX - (width / 2),
            y: panelFrame.minY + LayoutMetrics.compactPillBottomPadding,
            width: width,
            height: height
        )
    }

    private func handleRightMouseDown(_ event: NSEvent) {
        guard isVisible, !state.isRecording, !state.isProcessing else { return }
        guard let hostingView = hostingView, let contextMenu = contextMenu else { return }

        setHoverState(true)
        lastHoverContactAt = Date()
        isContextMenuOpen = true
        isHoverTooltipVisible = true

        refreshContextMenuState()
        contextMenu.update()

        let pillHeight: CGFloat = isHovered ? 22 : 10
        let pillTopFromBottom: CGFloat = 6 + pillHeight
        let menuGap: CGFloat = 8

        let measuredMenuWidth = contextMenu.size.width
        let menuWidth = max(measuredMenuWidth, 250)

        let menuHorizontalAdjustment: CGFloat = 3
        let originX = hostingView.bounds.midX - (menuWidth * 0.5) + menuHorizontalAdjustment
        let originYFromBottom = pillTopFromBottom + menuGap
        let originY = hostingView.isFlipped
            ? (hostingView.bounds.height - originYFromBottom)
            : originYFromBottom

        let menuOrigin = NSPoint(x: originX, y: originY)
        contextMenu.popUp(positioning: nil, at: menuOrigin, in: hostingView)
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu == contextMenu else { return }
        refreshContextMenuState()
        isContextMenuOpen = true
        setHoverState(true)
        lastHoverContactAt = Date()
        isHoverTooltipVisible = true
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu == contextMenu else { return }
        isContextMenuOpen = false
        lastHoverContactAt = Date()
    }

    private func checkAndUpdateScreenPosition() {
        guard isVisible, let panel else { return }

        let currentScreen = preferredScreen()
        if let last = lastScreen, currentScreen.pindrop_isSameDisplay(as: last) {
            return
        }

        lastScreen = currentScreen
        let newFrame = frame(for: currentScreen, state: layoutState)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            panel.setFrame(newFrame, display: false, animate: false)
        }
    }

    func setHoverState(_ hovering: Bool) {
        guard isVisible, !isDragging, !state.isRecording, !state.isProcessing else { return }
        guard isHovered != hovering else { return }

        isHovered = hovering
        if hovering {
            lastHoverContactAt = Date()
            scheduleHoverTooltipReveal()
        }
        if !hovering {
            hideHoverTooltip()
        }

        if hovering {
            refreshLayout(animated: false)
        } else {
            refreshLayout(animated: true, duration: 0.16)
        }
    }

    func startRecording() {
        isHovered = false
        hideHoverTooltip()
        lastHoverContactAt = .distantPast
        state.startRecording()

        if !isVisible {
            showIdleIndicator()
            return
        }

        refreshLayout(animated: true, duration: 0.24)
    }

    func transitionToProcessing() {
        state.transitionToProcessing()
        hideHoverTooltip()
        lastHoverContactAt = .distantPast
        refreshLayout(animated: true, duration: 0.2)
    }

    func finishProcessing() {
        state.finishSession()
        isHovered = false
        hideHoverTooltip()
        lastHoverContactAt = .distantPast
        refreshLayout(animated: true, duration: 0.22)
        hide()
    }

    func hide() {
        guard let panel = panel else { return }
        let localPanel = panel
        let localHostingView = hostingView

        stopHoverIntentMonitoring()
        lastScreen = nil
        hideHoverTooltip()
        isVisible = false
        isDragging = false
        dragStartMouseLocation = nil
        isHovered = false
        isContextMenuOpen = false

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            localPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            localPanel.close()
            DispatchQueue.main.async {
                guard let self else { return }
                if self.panel === localPanel {
                    self.panel = nil
                }
                if self.hostingView === localHostingView {
                    self.hostingView = nil
                }
            }
        })
    }

    func handleStopButtonTapped() {
        actions.onStopRecording?(type)
    }

    func handleCancelButtonTapped() {
        actions.onCancelRecording?()
    }

    func handleCompactTapped() {
        actions.onStartRecording?(type)
    }

    func beginDrag() {
        guard isVisible, !isContextMenuOpen else { return }
        guard !isDragging else { return }

        isDragging = true
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartOffset = settingsStore.pillFloatingIndicatorOffset
        dragOffset = dragStartOffset
        isHovered = false
        hideHoverTooltip()
        refreshLayout(animated: false)
    }

    func updateDrag(translation: CGSize) {
        guard isDragging else { return }
        guard let dragStartMouseLocation else { return }

        dragOffset = CGSize(
            width: dragStartOffset.width + (NSEvent.mouseLocation.x - dragStartMouseLocation.x),
            height: dragStartOffset.height + (NSEvent.mouseLocation.y - dragStartMouseLocation.y)
        )
        refreshLayout(animated: false)
    }

    func endDrag(translation: CGSize) {
        guard isDragging else { return }

        updateDrag(translation: translation)
        settingsStore.pillFloatingIndicatorOffset = dragOffset
        dragStartOffset = dragOffset
        isDragging = false
        dragStartMouseLocation = nil
        refreshLayout(animated: false)
    }

    private func createPanel(contentRect: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
        panel.isMovable = false

        panel.collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]

        panel.isReleasedWhenClosed = false
        panel.level = .mainMenu + 1
        panel.hasShadow = false

        return panel
    }

    private func makeHostingView(for contentView: PillIndicatorView, size: CGSize) -> PillHostingView {
        let hostingView = PillHostingView(
            rootView: makeRootView(for: contentView)
        )
        hostingView.layer?.backgroundColor = .clear
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.userInterfaceLayoutDirection = .leftToRight
        hostingView.onRightMouseDown = { [weak self] event in
            self?.handleRightMouseDown(event)
        }
        return hostingView
    }

    private func makeRootView(isCompact: Bool) -> AnyView {
        makeRootView(for: PillIndicatorView(
            controller: self,
            state: state,
            transcript: liveTranscript,
            isCompact: isCompact
        ))
    }

    private func makeRootView(for contentView: PillIndicatorView) -> AnyView {
        AnyView(contentView
            .environment(\.locale, settingsStore.selectedAppLocale.locale)
            // Panel geometry is physical (drag/exit edges use screen coords);
            // RTL applies to text subtrees (LiveTranscriptView).
            .environment(\.layoutDirection, .leftToRight))
    }

    private func size(for layoutState: LayoutState) -> CGSize {
        switch layoutState {
        case .recording:
            return liveTranscript.isActive ? LayoutMetrics.streamingSize : LayoutMetrics.recordingSize
        case .processing:
            return liveTranscript.isActive ? LayoutMetrics.streamingSize : LayoutMetrics.processingSize
        case .compact, .hover:
            return LayoutMetrics.hoverSize
        }
    }

    private func bottomInset(for _: LayoutState) -> CGFloat {
        LayoutMetrics.compactBottomInset
    }

    private func frame(for screen: NSScreen, state: LayoutState) -> NSRect {
        let panelSize = size(for: state)
        let screenFrame = screen.visibleFrame
        let offset = isDragging ? dragOffset : settingsStore.pillFloatingIndicatorOffset

        let xPosition = screenFrame.midX - (panelSize.width / 2) + offset.width
        let yPosition = screenFrame.minY + bottomInset(for: state) + offset.height

        return NSRect(
            x: clamp(
                xPosition,
                min: screenFrame.minX,
                max: screenFrame.maxX - panelSize.width
            ),
            y: clamp(
                yPosition,
                min: screenFrame.minY,
                max: screenFrame.maxY - panelSize.height
            ),
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }

    private func preferredScreen() -> NSScreen {
        actions.preferredScreenProvider?() ?? NSScreen.screenUnderMouse()
    }

    private func refreshLayout(animated: Bool, duration: TimeInterval = 0.22) {
        guard let panel = panel else { return }
        let screen = preferredScreen()
        lastScreen = screen

        let state = layoutState

        let targetFrame = frame(for: screen, state: state)

        let applyContentSize: () -> Void = { [weak self] in
            guard let self = self else { return }
            let contentSize = targetFrame.size
            panel.contentView?.frame = NSRect(origin: .zero, size: contentSize)
            self.hostingView?.frame = NSRect(origin: .zero, size: contentSize)
        }

        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: false)
                applyContentSize()
            }
        } else {
            if panel.frame.size == targetFrame.size {
                panel.setFrameOrigin(targetFrame.origin)
            } else {
                panel.setFrame(targetFrame, display: false)
            }
            applyContentSize()
        }
    }

}

struct PillIndicatorView: View {
    @ObservedObject var controller: PillFloatingIndicatorController
    @ObservedObject var state: FloatingIndicatorState
    @ObservedObject var transcript: LiveTranscriptState
    let isCompact: Bool
    @Namespace private var pillShellNamespace
    @ObservedObject private var theme = PindropThemeController.shared
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsExpandedState: Bool {
        state.isRecording || state.isProcessing || !isCompact
    }

    /// Live transcript card replaces the small recording/processing pill while a
    /// streaming session is active.
    private var showsTranscript: Bool {
        transcript.isActive && (state.isRecording || state.isProcessing)
    }

    var body: some View {
        Group {
            if showsExpandedState {
                expandedView
            } else {
                compactView
            }
        }
        .animation(reduceMotion ? nil : AppTheme.Animation.smooth, value: showsExpandedState)
        .opacity(state.isInputMuted ? 0.4 : 1)
        .themeRefresh()
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in
                    if !controller.isDragging {
                        controller.beginDrag()
                    }
                    controller.updateDrag(translation: .zero)
                }
                .onEnded { _ in
                    controller.endDrag(translation: .zero)
                }
        )
    }

    private var compactView: some View {
        ZStack(alignment: .bottom) {
            Button {
                controller.handleCompactTapped()
            } label: {
                compactPillShell
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
            .keyboardFocusRing(Capsule())
            .accessibilityLabel(
                localized(state.isInputMuted ? "Microphone muted" : "Start Recording", locale: locale)
            )

            if controller.isHoverTooltipVisible {
                PillHoverTooltip(
                    toggleHotkey: state.toggleRecordingHotkey,
                    pushToTalkHotkey: state.pushToTalkHotkey
                )
                    .offset(y: -24)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)),
                            removal: .opacity
                        )
                    )
            }

            if let completion = state.recentCompletion {
                IndicatorCompletionOverlay(completion: completion)
                    .offset(y: -34)
                    .allowsHitTesting(false)
                    .appAnimation(.smooth, value: state.recentCompletion)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.86), value: controller.isHovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: controller.isHoverTooltipVisible)
    }

    private var expandedView: some View {
        ZStack {
            expandedPillShell

            if showsTranscript {
                VStack(spacing: 6) {
                    expandedControlsRow
                        .frame(height: 26)
                    LiveTranscriptView(transcript: transcript, fontSize: 14, lineLimit: 3)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            } else {
                expandedControlsRow
            }
        }
        .frame(width: expandedSize.width, height: expandedSize.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 6)
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.86), value: showsTranscript)
    }

    private var expandedSize: CGSize {
        if showsTranscript { return CGSize(width: 270, height: 104) }
        return state.isProcessing
            ? CGSize(width: 148, height: 32)
            : CGSize(width: 166, height: 32)
    }

    @ViewBuilder
    private var expandedControlsRow: some View {
        if state.isRecording {
            HStack(spacing: showsTranscript ? 8 : 9) {
                Circle()
                    .fill(Color(nsColor: NSColor(pindropHex: "#D25B4C") ?? .systemRed))
                    .frame(width: showsTranscript ? 7 : 8, height: showsTranscript ? 7 : 8)

                if showsTranscript {
                    Text(FloatingIndicatorTimeFormatting.elapsed(state.recordingDuration))
                        .font(FontLoader.font(family: .jetbrainsMono, size: 11, weight: .medium))
                        .foregroundStyle(Color(nsColor: NSColor(pindropHex: "#A59D8C") ?? .secondaryLabelColor))
                        .contentTransition(.numericText(countsDown: false))

                    Spacer(minLength: 0)

                    Text("en")
                        .font(FontLoader.font(family: .jetbrainsMono, size: 10, weight: .regular))
                        .foregroundStyle(Color(nsColor: NSColor(pindropHex: "#6E675B") ?? .tertiaryLabelColor))
                } else {
                    FloatingIndicatorWaveformView(
                        audioLevel: state.audioLevel,
                        isRecording: state.isRecording,
                        style: .pill
                    )
                    .frame(width: 44, height: 14)

                    Text(FloatingIndicatorTimeFormatting.elapsed(state.recordingDuration))
                        .font(FontLoader.font(family: .jetbrainsMono, size: 13, weight: .medium))
                        .foregroundStyle(Color(nsColor: NSColor(pindropHex: "#EFEBE2") ?? .white))
                        .contentTransition(.numericText(countsDown: false))

                    Rectangle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 1, height: 14)
                }

                Button {
                    controller.handleStopButtonTapped()
                } label: {
                    RoundedRectangle(cornerRadius: showsTranscript ? 2 : 2.5, style: .continuous)
                        .fill(Color(nsColor: NSColor(pindropHex: "#EFEBE2") ?? .white).opacity(0.72))
                        .frame(width: showsTranscript ? 9 : 10, height: showsTranscript ? 9 : 10)
                }
                .buttonStyle(.plain)
                .keyboardFocusRing(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .accessibilityLabel(localized("Stop Recording", locale: locale))
            }
            .padding(.horizontal, showsTranscript ? 16 : 14)
        } else {
            HStack(spacing: 9) {
                IndicatorProcessingView(dotCount: 3, dotDiameter: 4, spacing: 3)

                Text(localized("Transcribing…", locale: locale))
                    .font(FontLoader.font(family: .inter, size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: NSColor(pindropHex: "#EFEBE2") ?? .white))
            }
            .padding(.horizontal, 14)
        }
    }

    private var compactPillShell: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.20, green: 0.24, blue: 0.21).opacity(0.95),
                        Color(red: 0.10, green: 0.12, blue: 0.11).opacity(0.95),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.10), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .hairlineStroke(Capsule(), style: AppColors.overlayLine)
            .frame(width: 44, height: 10)
            .shadow(color: Color.black.opacity(0.4), radius: 10, y: 3)
            .matchedGeometryEffect(id: "pillShell", in: pillShellNamespace)
    }

    /// Capsule for the small recording/processing pill; rounded card while the live
    /// transcript shows. Same matched-geometry id so the capsule morphs into the card.
    private var expandedPillShell: some View {
        let shape = RoundedRectangle(
            cornerRadius: showsTranscript ? 16 : expandedSize.height / 2,
            style: .continuous
        )
        return shape
            .fill(AppColors.overlaySurface)
            .hairlineStroke(shape, style: AppColors.overlayLine)
            .shadow(color: Color.black.opacity(0.4), radius: 14, y: 4)
            .matchedGeometryEffect(id: "pillShell", in: pillShellNamespace)
    }
}

private struct PillHoverTooltip: View {
    @Environment(\.locale) private var locale
    let toggleHotkey: String
    let pushToTalkHotkey: String

    private enum PromptMode {
        case toggle(String)
        case pushToTalk(String)
        case noHotkey
    }

    private var promptMode: PromptMode {
        let normalizedToggle = normalizedHotkeyDisplay(toggleHotkey)
        if !normalizedToggle.isEmpty {
            return .toggle(normalizedToggle)
        }

        let normalizedPushToTalk = normalizedHotkeyDisplay(pushToTalkHotkey)
        if !normalizedPushToTalk.isEmpty {
            return .pushToTalk(normalizedPushToTalk)
        }

        return .noHotkey
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                switch promptMode {
                case .toggle(let hotkey):
                    Text(localized("Click or hold ", locale: locale))
                        .foregroundStyle(AppColors.overlayTextSecondary)

                    Text(hotkey)
                        .foregroundStyle(AppColors.overlayTooltipAccent)

                    Text(localized(" to start talking", locale: locale))
                        .foregroundStyle(AppColors.overlayTextSecondary)

                case .pushToTalk(let hotkey):
                    Text(localized("Click or press ", locale: locale))
                        .foregroundStyle(AppColors.overlayTextSecondary)

                    Text(hotkey)
                        .foregroundStyle(AppColors.overlayTooltipAccent)

                    Text(localized(" to start talking", locale: locale))
                        .foregroundStyle(AppColors.overlayTextSecondary)

                case .noHotkey:
                    Text(localized("Click or set a hotkey to start talking", locale: locale))
                        .foregroundStyle(AppColors.overlayTextSecondary)
                }
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppColors.overlaySurfaceStrong)
                    .hairlineStroke(
                        RoundedRectangle(cornerRadius: 10, style: .continuous),
                        style: AppColors.overlayLine.opacity(0.8)
                    )
                    .shadow(color: AppColors.shadowColor.opacity(0.42), radius: 14, y: 6)
            )

            TooltipPointer()
                .fill(AppColors.overlaySurfaceStrong)
                .frame(width: 12, height: 6)
                .hairlineStroke(TooltipPointer(), style: AppColors.overlayLine.opacity(0.8))
                .offset(y: -0.5)
        }
    }

    private func normalizedHotkeyDisplay(_ hotkey: String) -> String {
        let trimmed = hotkey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var normalized = trimmed
            .replacingOccurrences(of: " + ", with: "+")
            .replacingOccurrences(of: " +", with: "+")
            .replacingOccurrences(of: "+ ", with: "+")
            .replacingOccurrences(of: "command", with: "⌘", options: .caseInsensitive)
            .replacingOccurrences(of: "cmd", with: "⌘", options: .caseInsensitive)
            .replacingOccurrences(of: "control", with: "⌃", options: .caseInsensitive)
            .replacingOccurrences(of: "ctrl", with: "⌃", options: .caseInsensitive)
            .replacingOccurrences(of: "option", with: "⌥", options: .caseInsensitive)
            .replacingOccurrences(of: "opt", with: "⌥", options: .caseInsensitive)
            .replacingOccurrences(of: "alt", with: "⌥", options: .caseInsensitive)
            .replacingOccurrences(of: "shift", with: "⇧", options: .caseInsensitive)

        if normalized.contains("+") {
            normalized = normalized
                .split(separator: "+")
                .map(String.init)
                .map { token in
                    let lower = token.lowercased()
                    if lower == "space" || lower == "spacebar" {
                        return "Space"
                    }
                    return token
                }
                .joined()
        }

        return normalized
    }
}

private struct TooltipPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#Preview("Pill Compact") {
    pillCompactPreview
}

#Preview("Pill Hover") {
    pillHoverPreview
}

#Preview("Pill Expanded - Recording") {
    pillRecordingPreview
}

#Preview("Pill Expanded - Processing") {
    pillProcessingPreview
}

@MainActor
private var pillCompactPreview: some View {
    let state = FloatingIndicatorState()
    let controller = PillFloatingIndicatorController(state: state, settingsStore: SettingsStore(), liveTranscript: LiveTranscriptState())

    return PillIndicatorView(controller: controller, state: state, transcript: controller.liveTranscript, isCompact: true)
        .frame(width: 332, height: 68)
        .padding()
        .background(Color.black.opacity(0.1))
}

@MainActor
private var pillHoverPreview: some View {
    let state = FloatingIndicatorState()
    let controller = PillFloatingIndicatorController(state: state, settingsStore: SettingsStore(), liveTranscript: LiveTranscriptState())
    controller.isHovered = true
    controller.isHoverTooltipVisible = true
    state.toggleRecordingHotkey = "⌥Space"

    return PillIndicatorView(controller: controller, state: state, transcript: controller.liveTranscript, isCompact: true)
        .frame(width: 332, height: 68)
        .padding()
        .background(Color.black.opacity(0.1))
}

@MainActor
private var pillRecordingPreview: some View {
    let state = FloatingIndicatorState()
    let controller = PillFloatingIndicatorController(state: state, settingsStore: SettingsStore(), liveTranscript: LiveTranscriptState())
    state.isRecording = true
    state.audioLevel = 0.7

    return PillIndicatorView(controller: controller, state: state, transcript: controller.liveTranscript, isCompact: false)
        .frame(width: 124, height: 30)
        .padding()
        .background(Color.black.opacity(0.1))
}

@MainActor
private var pillProcessingPreview: some View {
    let state = FloatingIndicatorState()
    let controller = PillFloatingIndicatorController(state: state, settingsStore: SettingsStore(), liveTranscript: LiveTranscriptState())
    state.isRecording = false
    state.isProcessing = true

    return PillIndicatorView(controller: controller, state: state, transcript: controller.liveTranscript, isCompact: false)
        .frame(width: 124, height: 30)
        .padding()
        .background(Color.black.opacity(0.1))
}
