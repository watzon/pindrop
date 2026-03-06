//
//  PillFloatingIndicator.swift
//  Pindrop
//
//  Created on 2026-01-29.
//

import SwiftUI
import AppKit

private final class PillHostingView: NSHostingView<PillIndicatorView> {
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
    private let settingsStore: SettingsStore

    private enum LayoutState {
        case compact
        case hover
        case recording
        case processing
    }

    private enum LayoutMetrics {
        static let compactSize = CGSize(width: 40, height: 10)
        static let compactPillBottomPadding: CGFloat = 6
        static let hoverSize = CGSize(width: 332, height: 68)
        static let recordingSize = CGSize(width: 124, height: 30)
        static let processingSize = CGSize(width: 124, height: 30)

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

    @Published var isHovered: Bool = false
    @Published var isHoverTooltipVisible: Bool = false
    @Published private(set) var isDragging = false
    private var screenTrackingTimer: Timer?
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

    init(state: FloatingIndicatorState, settingsStore: SettingsStore) {
        self.state = state
        self.settingsStore = settingsStore
        self.dragOffset = settingsStore.pillFloatingIndicatorOffset
        super.init()
        contextMenu = makeContextMenu()
    }

    func configure(actions: FloatingIndicatorActions) {
        self.actions = actions
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

        guard let screen = NSScreen.main else { return }

        let state = layoutState

        let panel = createPanel(contentRect: frame(for: screen, state: state))

        let contentView = PillIndicatorView(
            controller: self,
            state: self.state,
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
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        lastScreen = screen
        startScreenTracking()
        startHoverIntentMonitoring()
    }

    private func startScreenTracking() {
        screenTrackingTimer?.invalidate()
        screenTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndUpdateScreenPosition()
            }
        }
    }

    private func stopScreenTracking() {
        screenTrackingTimer?.invalidate()
        screenTrackingTimer = nil
        lastScreen = nil
    }

    private func startHoverIntentMonitoring() {
        hoverIntentTimer?.invalidate()
        hoverIntentTimer = Timer.scheduledTimer(withTimeInterval: LayoutMetrics.hoverMonitorInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateHoverIntent()
            }
        }
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
        let menu = NSMenu(title: "Pindrop Pill")
        menu.delegate = self

        let hideForOneHourItem = NSMenuItem(
            title: "Hide this for 1 hour",
            action: #selector(handleHideForOneHourMenuItem),
            keyEquivalent: ""
        )
        hideForOneHourItem.target = self
        menu.addItem(hideForOneHourItem)

        let reportIssueItem = NSMenuItem(
            title: "Report an issue",
            action: #selector(handleReportIssueMenuItem),
            keyEquivalent: ""
        )
        reportIssueItem.target = self
        menu.addItem(reportIssueItem)

        let goToSettingsItem = NSMenuItem(
            title: "Go to settings",
            action: #selector(handleGoToSettingsMenuItem),
            keyEquivalent: ""
        )
        goToSettingsItem.target = self
        menu.addItem(goToSettingsItem)

        menu.addItem(.separator())

        let microphoneMenu = NSMenu(title: "Change microphone")
        self.microphoneMenu = microphoneMenu

        let microphoneItem = NSMenuItem(title: "Change microphone", action: nil, keyEquivalent: "")
        microphoneItem.submenu = microphoneMenu
        self.microphoneItem = microphoneItem
        menu.addItem(microphoneItem)

        let languageMenu = NSMenu(title: "Select language")
        let englishItem = NSMenuItem(title: "English (v1)", action: nil, keyEquivalent: "")
        englishItem.state = NSControl.StateValue.on
        englishItem.isEnabled = false
        languageMenu.addItem(englishItem)

        let languageItem = NSMenuItem(title: "Select language", action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        menu.addItem(.separator())

        let viewHistoryItem = NSMenuItem(
            title: "View transcript history",
            action: #selector(handleViewTranscriptHistoryMenuItem),
            keyEquivalent: ""
        )
        viewHistoryItem.target = self
        menu.addItem(viewHistoryItem)

        let pasteLastTranscriptItem = NSMenuItem(
            title: "Paste last transcript ⌃⌘V",
            action: #selector(handlePasteLastTranscriptMenuItem),
            keyEquivalent: ""
        )
        pasteLastTranscriptItem.target = self
        menu.addItem(pasteLastTranscriptItem)

        refreshContextMenuState()

        return menu
    }

    private func refreshContextMenuState() {
        refreshMicrophoneMenuItems()
    }

    private func refreshMicrophoneMenuItems() {
        guard let microphoneMenu = microphoneMenu else { return }

        microphoneMenu.removeAllItems()

        let selectedUID = actions.selectedInputDeviceUIDProvider?() ?? ""
        let availableDevices = actions.availableInputDevicesProvider?() ?? []

        let systemDefaultItem = NSMenuItem(
            title: "System Default",
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

            let unavailableItem = NSMenuItem(title: "Unavailable device", action: nil, keyEquivalent: "")
            unavailableItem.isEnabled = false
            unavailableItem.state = NSControl.StateValue.on
            microphoneMenu.addItem(unavailableItem)
        }

        microphoneItem?.isEnabled = true
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
        guard isVisible, !state.isRecording, !state.isProcessing else { return }
        guard let currentScreen = NSScreen.main, let panel = panel else { return }

        if lastScreen !== currentScreen {
            lastScreen = currentScreen
            let newFrame = frame(for: currentScreen, state: layoutState)
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
    }

    func hide() {
        guard let panel = panel else { return }
        let localPanel = panel

        stopScreenTracking()
        stopHoverIntentMonitoring()
        hideHoverTooltip()
        isVisible = false
        isDragging = false
        dragStartMouseLocation = nil
        isHovered = false
        isContextMenuOpen = false

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            localPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            localPanel.close()
            DispatchQueue.main.async {
                self?.panel = nil
                self?.hostingView = nil
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
        let hostingView = PillHostingView(rootView: contentView)
        hostingView.layer?.backgroundColor = .clear
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.onRightMouseDown = { [weak self] event in
            self?.handleRightMouseDown(event)
        }
        return hostingView
    }

    private func size(for _: LayoutState) -> CGSize {
        LayoutMetrics.hoverSize
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

    private func refreshLayout(animated: Bool, duration: TimeInterval = 0.22) {
        guard let panel = panel else { return }
        guard let screen = NSScreen.main ?? panel.screen ?? NSScreen.screens.first else { return }

        let state = layoutState

        let targetFrame = frame(for: screen, state: state)

        let applyContentSize: () -> Void = { [weak self] in
            guard let self = self else { return }
            let contentSize = targetFrame.size
            panel.contentView?.frame = NSRect(origin: .zero, size: contentSize)
            self.hostingView?.frame = NSRect(origin: .zero, size: contentSize)
        }

        if animated {
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
    let isCompact: Bool
    @Namespace private var pillShellNamespace

    private var showsExpandedState: Bool {
        state.isRecording || state.isProcessing || !isCompact
    }

    var body: some View {
        Group {
            if showsExpandedState {
                expandedView
            } else {
                compactView
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showsExpandedState)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: controller.isHovered)
        .animation(.easeOut(duration: 0.15), value: controller.isHoverTooltipVisible)
    }

    private var expandedView: some View {
        ZStack {
            expandedPillShell

            if state.isRecording {
                HStack(spacing: 8) {
                    Button {
                        controller.handleCancelButtonTapped()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.1))

                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.9))
                        }
                        .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)

                    FloatingIndicatorWaveformView(
                        audioLevel: state.audioLevel,
                        isRecording: state.isRecording,
                        style: .pill
                    )
                    .frame(width: 46, height: 14)

                    Button {
                        controller.handleStopButtonTapped()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.94, green: 0.38, blue: 0.38))

                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.white)
                                .frame(width: 6, height: 6)
                        }
                        .frame(width: 18, height: 18)
                        .shadow(color: Color.red.opacity(0.25), radius: 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 9)
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white.opacity(0.95))

                    Text("Processing")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: 124, height: 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 6)
    }

    private var compactPillShell: some View {
        Capsule()
            .fill(Color.black.opacity(controller.isHovered ? 0.84 : 0.68))
            .overlay(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(controller.isHovered ? 0.18 : 0.1),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(controller.isHovered ? 0.28 : 0.18), lineWidth: 0.65)
            )
            .overlay {
                if controller.isHovered {
                    PillStaticWaveformGlyph()
                }
            }
            .frame(width: controller.isHovered ? 86 : 40, height: controller.isHovered ? 22 : 10)
            .shadow(color: Color.black.opacity(controller.isHovered ? 0.42 : 0.3), radius: 12, y: 6)
            .matchedGeometryEffect(id: "pillShell", in: pillShellNamespace)
    }

    private var expandedPillShell: some View {
        Capsule()
            .fill(Color.black.opacity(0.82))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
            )
            .overlay(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.2), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .shadow(color: Color.black.opacity(0.42), radius: 14, y: 8)
            .matchedGeometryEffect(id: "pillShell", in: pillShellNamespace)
    }
}

private struct PillStaticWaveformGlyph: View {
    private let barHeights: [CGFloat] = [3, 6, 8, 6, 4]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(barHeights.enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.78))
                    .frame(width: 2, height: height)
            }
        }
        .frame(width: 18, height: 10)
    }
}

private struct PillHoverTooltip: View {
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
                    Text("Click or hold ")
                        .foregroundStyle(Color.white.opacity(0.78))

                    Text(hotkey)
                        .foregroundStyle(Color(red: 0.88, green: 0.67, blue: 0.79))

                    Text(" to start talking")
                        .foregroundStyle(Color.white.opacity(0.78))

                case .pushToTalk(let hotkey):
                    Text("Click or press ")
                        .foregroundStyle(Color.white.opacity(0.78))

                    Text(hotkey)
                        .foregroundStyle(Color(red: 0.88, green: 0.67, blue: 0.79))

                    Text(" to start talking")
                        .foregroundStyle(Color.white.opacity(0.78))

                case .noHotkey:
                    Text("Click or set a hotkey to start talking")
                        .foregroundStyle(Color.white.opacity(0.78))
                }
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.42), radius: 14, y: 6)
            )

            TooltipPointer()
                .fill(Color.black.opacity(0.9))
                .frame(width: 12, height: 6)
                .overlay(
                    TooltipPointer()
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                )
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
    let controller = PillFloatingIndicatorController(state: state, settingsStore: SettingsStore())

    return PillIndicatorView(controller: controller, state: state, isCompact: true)
        .frame(width: 332, height: 68)
        .padding()
        .background(Color.black.opacity(0.1))
}

@MainActor
private var pillHoverPreview: some View {
    let state = FloatingIndicatorState()
    let controller = PillFloatingIndicatorController(state: state, settingsStore: SettingsStore())
    controller.isHovered = true
    controller.isHoverTooltipVisible = true
    state.toggleRecordingHotkey = "⌥Space"

    return PillIndicatorView(controller: controller, state: state, isCompact: true)
        .frame(width: 332, height: 68)
        .padding()
        .background(Color.black.opacity(0.1))
}

@MainActor
private var pillRecordingPreview: some View {
    let state = FloatingIndicatorState()
    let controller = PillFloatingIndicatorController(state: state, settingsStore: SettingsStore())
    state.isRecording = true
    state.audioLevel = 0.7

    return PillIndicatorView(controller: controller, state: state, isCompact: false)
        .frame(width: 124, height: 30)
        .padding()
        .background(Color.black.opacity(0.1))
}

@MainActor
private var pillProcessingPreview: some View {
    let state = FloatingIndicatorState()
    let controller = PillFloatingIndicatorController(state: state, settingsStore: SettingsStore())
    state.isRecording = false
    state.isProcessing = true

    return PillIndicatorView(controller: controller, state: state, isCompact: false)
        .frame(width: 124, height: 30)
        .padding()
        .background(Color.black.opacity(0.1))
}
