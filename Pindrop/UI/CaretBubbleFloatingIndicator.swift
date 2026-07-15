//
//  CaretBubbleFloatingIndicator.swift
//  Pindrop
//
//  Created on 2026-03-06.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class CaretBubbleFloatingIndicatorController: FloatingIndicatorPresenting, ObservableObject {
    let type: FloatingIndicatorType = .bubble
    let state: FloatingIndicatorState
    let liveTranscript: LiveTranscriptState

    @Published var isHovered = false
    @Published private(set) var actionRevealWidth: CGFloat = 0
    @Published private(set) var isDragging = false

    fileprivate enum LayoutMetrics {
        static let panelSize = CGSize(width: 98, height: 40)
        static let centerBubbleSize = CGSize(width: 42, height: 28)
        /// Sizes while the live transcript card is showing (overlay streaming).
        static let streamingPanelSize = CGSize(width: 320, height: 116)
        static let streamingBubbleSize = CGSize(width: 264, height: 104)
        static let actionBubbleSize = CGSize(width: 22, height: 22)
        static let actionSpacing: CGFloat = 6
        /// Gaps between the anchor (caret) and the panel. The bare bubble hugs the
        /// caret; the streaming transcript card keeps a little more distance.
        static let horizontalGap: CGFloat = 8
        static let verticalGap: CGFloat = 8
        static let streamingHorizontalGap: CGFloat = 14
        static let streamingVerticalGap: CGFloat = 14
        static let screenInset: CGFloat = 8
        static let fallbackBottomInset: CGFloat = 60
        static let refreshInterval: TimeInterval = 0.25
    }

    private enum BubblePlacement: CaseIterable {
        case above
        case left
        case right
        case below
    }

    /// Effective sizes — swap to the transcript-card dimensions while streaming.
    private var panelSize: CGSize {
        liveTranscript.isActive ? LayoutMetrics.streamingPanelSize : LayoutMetrics.panelSize
    }
    fileprivate var centerBubbleSize: CGSize {
        liveTranscript.isActive ? LayoutMetrics.streamingBubbleSize : LayoutMetrics.centerBubbleSize
    }

    /// Placement preference: while the transcript card shows, prefer below/above so the
    /// card doesn't cover the line being written at the caret. The bare bubble hugs the
    /// caret's trailing side first, like an IME candidate window.
    private var placementOrder: [BubblePlacement] {
        liveTranscript.isActive ? [.below, .above, .left, .right] : [.right, .above, .below, .left]
    }

    /// Anchor-to-panel gaps — tight for the bare bubble, roomier for the transcript card.
    private var placementGapX: CGFloat {
        liveTranscript.isActive ? LayoutMetrics.streamingHorizontalGap : LayoutMetrics.horizontalGap
    }
    private var placementGapY: CGFloat {
        liveTranscript.isActive ? LayoutMetrics.streamingVerticalGap : LayoutMetrics.verticalGap
    }

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var actions = FloatingIndicatorActions()
    private var anchorRefreshTimer: Timer?
    private var isVisible = false
    private var dragStartMouseLocation: CGPoint?
    private var manualOffset: CGSize = .zero
    private var dragStartOffset: CGSize = .zero
    private var phaseCancellables = Set<AnyCancellable>()
    /// Bumped on every show/hide so a hide completion cannot orderOut/nil a
    /// panel reused for a newer active session.
    private var presentationGeneration: UInt = 0

    init(state: FloatingIndicatorState, liveTranscript: LiveTranscriptState) {
        self.state = state
        self.liveTranscript = liveTranscript

        // Resize the panel on transcript phase transitions only; while the card is up
        // the cancel/stop bubbles stay revealed (no hover needed mid-dictation).
        liveTranscript.$phase
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.liveTranscript.isActive {
                    self.actionRevealWidth =
                        LayoutMetrics.actionBubbleSize.width + LayoutMetrics.actionSpacing
                } else if !self.isHovered {
                    self.actionRevealWidth = 0
                }
                self.refreshAnchorPosition(animated: true)
            }
            .store(in: &phaseCancellables)
    }

    func configure(actions: FloatingIndicatorActions) {
        self.actions = actions
    }

    func showIdleIndicator() {
        hide()
    }

    func showForCurrentState() {
        // Always route through show() so an in-flight hide is invalidated
        // (presentationGeneration bump) and alpha / tracking / timers revive.
        show()
    }

    func startRecording() {
        state.startRecording()
        isHovered = false
        actionRevealWidth = streamingRevealWidth
        show()
        refreshAnchorPosition(animated: false)
    }

    func transitionToProcessing() {
        state.transitionToProcessing()
        isHovered = false
        actionRevealWidth = streamingRevealWidth
        show()
        refreshAnchorPosition(animated: false)
    }

    /// While the transcript card is up the action bubbles stay revealed.
    private var streamingRevealWidth: CGFloat {
        liveTranscript.isActive
            ? (LayoutMetrics.actionBubbleSize.width + LayoutMetrics.actionSpacing)
            : 0
    }

    func finishProcessing() {
        state.finishSession()
        hide()
    }

    func hide() {
        anchorRefreshTimer?.invalidate()
        anchorRefreshTimer = nil
        isHovered = false
        actionRevealWidth = 0
        isDragging = false
        dragStartMouseLocation = nil
        manualOffset = .zero
        dragStartOffset = .zero
        isVisible = false

        guard let panel else { return }

        presentationGeneration &+= 1
        let hideGeneration = presentationGeneration
        let localPanel = panel
        let localHostingView = hostingView

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            localPanel.animator().alphaValue = 0
        }) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard FloatingIndicatorPresentationLifecycle.shouldApplyHideCompletion(
                    hideGeneration: hideGeneration,
                    currentGeneration: self.presentationGeneration
                ) else {
                    return
                }
                guard self.panel === localPanel else { return }
                localPanel.orderOut(nil)
                self.panel = nil
                if self.hostingView === localHostingView {
                    self.hostingView = nil
                }
            }
        }
    }

    func setHover(_ hovering: Bool) {
        guard !isDragging else { return }
        guard state.isRecording else {
            isHovered = false
            actionRevealWidth = 0
            return
        }
        isHovered = hovering
        let revealed = hovering || liveTranscript.isActive
        actionRevealWidth = revealed ? (LayoutMetrics.actionBubbleSize.width + LayoutMetrics.actionSpacing) : 0
        refreshAnchorPosition(animated: true)
    }

    func handleStartTapped() {
        actions.onStartRecording?(type)
    }

    func handleStopTapped() {
        actions.onStopRecording?(type)
    }

    func handleCancelTapped() {
        actions.onCancelRecording?()
    }

    func beginDrag() {
        guard isVisible else { return }
        guard !isDragging else { return }

        isDragging = true
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartOffset = manualOffset
        isHovered = false
        actionRevealWidth = 0
        refreshAnchorPosition(animated: false)
    }

    func updateDrag(translation: CGSize) {
        guard isDragging else { return }
        guard let dragStartMouseLocation else { return }

        manualOffset = CGSize(
            width: dragStartOffset.width + (NSEvent.mouseLocation.x - dragStartMouseLocation.x),
            height: dragStartOffset.height + (NSEvent.mouseLocation.y - dragStartMouseLocation.y)
        )
        refreshAnchorPosition(animated: false)
    }

    func endDrag(translation: CGSize) {
        guard isDragging else { return }

        updateDrag(translation: translation)
        dragStartOffset = manualOffset
        isDragging = false
        dragStartMouseLocation = nil
    }

    private func show() {
        // Invalidate any in-flight hide completion before reusing/creating a panel.
        presentationGeneration &+= 1

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: panelSize),
                styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .mainMenu + 3
            panel.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
            panel.isReleasedWhenClosed = false

            let appLocale = AppLocale.currentSelection()
            let contentView = AnyView(
                CaretBubbleIndicatorView(controller: self, state: state, transcript: liveTranscript)
                    .environment(\.locale, appLocale.locale)
                    .environment(\.layoutDirection, .leftToRight))
            let hostingView = NSHostingView(rootView: contentView)
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            hostingView.wantsLayer = true
            hostingView.frame = NSRect(origin: .zero, size: panelSize)
            hostingView.userInterfaceLayoutDirection = .leftToRight

            panel.contentView = hostingView
            panel.alphaValue = 0
            panel.orderFrontRegardless()

            self.panel = panel
            self.hostingView = hostingView
        }

        panel?.orderFrontRegardless()
        isVisible = true
        startAnchorRefresh()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.panel?.animator().alphaValue = 1
        }
    }

    private func startAnchorRefresh() {
        anchorRefreshTimer?.invalidate()
        anchorRefreshTimer = Timer.pindrop_scheduleRepeating(interval: LayoutMetrics.refreshInterval) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAnchorPosition(animated: false)
            }
        }
    }

    private func refreshAnchorPosition(animated: Bool) {
        guard isVisible, let panel else { return }

        let frame = targetFrame()
        hostingView?.frame = NSRect(origin: .zero, size: frame.size)
        if animated {
            panel.animator().setFrame(frame, display: true)
        } else {
            // Match pill screen jumps: no implicit Core Animation interpolation across displays.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                panel.setFrame(frame, display: false, animate: false)
            }
        }
    }

    private func targetFrame() -> NSRect {
        let size = panelSize
        let anchorRect = actions.anchorProvider?().map(convertToAppKitScreenCoordinates)
        let screen = preferredScreen(for: anchorRect) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        guard let anchorRect, !anchorRect.isEmpty else {
            return applyManualOffset(
                to: NSRect(origin: fallbackOrigin(in: visibleFrame), size: size),
                within: visibleFrame
            )
        }

        for placement in placementOrder {
            if let frame = frame(for: placement, anchorRect: anchorRect, visibleFrame: visibleFrame) {
                return applyManualOffset(to: frame, within: visibleFrame)
            }
        }

        return applyManualOffset(
            to: clampedFrame(
                x: anchorRect.midX - (centerBubbleSize.width / 2) - actionRevealWidth,
                y: anchorRect.maxY + placementGapY - verticalBubbleInset,
                within: visibleFrame
            ),
            within: visibleFrame
        )
    }

    private func frame(for placement: BubblePlacement, anchorRect: CGRect, visibleFrame: CGRect) -> NSRect? {
        switch placement {
        case .above:
            let y = anchorRect.maxY + placementGapY - verticalBubbleInset
            guard y + panelSize.height <= visibleFrame.maxY - LayoutMetrics.screenInset else { return nil }
            let x = anchorRect.midX - (centerBubbleSize.width / 2) - actionRevealWidth
            return clampedFrame(x: x, y: y, within: visibleFrame)

        case .left:
            let x = anchorRect.minX - placementGapX - centerBubbleSize.width - actionRevealWidth
            guard x >= visibleFrame.minX + LayoutMetrics.screenInset else { return nil }
            let y = anchorRect.midY - (centerBubbleSize.height / 2) - verticalBubbleInset
            return clampedFrame(x: x, y: y, within: visibleFrame)

        case .right:
            let x = anchorRect.maxX + placementGapX - actionRevealWidth
            guard x + panelSize.width <= visibleFrame.maxX - LayoutMetrics.screenInset else { return nil }
            let y = anchorRect.midY - (centerBubbleSize.height / 2) - verticalBubbleInset
            return clampedFrame(x: x, y: y, within: visibleFrame)

        case .below:
            let y = anchorRect.minY - placementGapY - centerBubbleSize.height - verticalBubbleInset
            guard y >= visibleFrame.minY + LayoutMetrics.screenInset else { return nil }
            let x = anchorRect.midX - (centerBubbleSize.width / 2) - actionRevealWidth
            return clampedFrame(x: x, y: y, within: visibleFrame)
        }
    }

    private func preferredScreen(for anchorRect: CGRect?) -> NSScreen? {
        guard let anchorRect else { return NSScreen.main }
        let anchorPoint = CGPoint(x: anchorRect.midX, y: anchorRect.midY)
        return NSScreen.screens.first { $0.frame.contains(anchorPoint) }
            ?? NSScreen.screens.first { $0.frame.intersects(anchorRect) }
            ?? NSScreen.main
    }

    private func fallbackOrigin(in visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: visibleFrame.maxX - panelSize.width - 24,
            y: visibleFrame.minY + LayoutMetrics.fallbackBottomInset
        )
    }

    private var verticalBubbleInset: CGFloat {
        (panelSize.height - centerBubbleSize.height) / 2
    }

    private func clampedFrame(x: CGFloat, y: CGFloat, within visibleFrame: CGRect) -> NSRect {
        NSRect(
            x: clamp(
                x,
                min: visibleFrame.minX + LayoutMetrics.screenInset,
                max: visibleFrame.maxX - panelSize.width - LayoutMetrics.screenInset
            ),
            y: clamp(
                y,
                min: visibleFrame.minY + LayoutMetrics.screenInset,
                max: visibleFrame.maxY - panelSize.height - LayoutMetrics.screenInset
            ),
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func applyManualOffset(to frame: NSRect, within visibleFrame: CGRect) -> NSRect {
        clampedFrame(
            x: frame.origin.x + manualOffset.width,
            y: frame.origin.y + manualOffset.height,
            within: visibleFrame
        )
    }

    private func convertToAppKitScreenCoordinates(_ rect: CGRect) -> CGRect {
        for screen in NSScreen.screens {
            let convertedRect = CGRect(
                x: rect.minX,
                y: screen.frame.maxY - rect.maxY,
                width: rect.width,
                height: rect.height
            )

            if screen.frame.intersects(convertedRect) {
                return convertedRect.standardized
            }
        }

        if let desktopFrame = NSScreen.screens.map(\.frame).reduce(nil, { partialResult, frame in
            partialResult?.union(frame) ?? frame
        }) {
            return CGRect(
                x: rect.minX,
                y: desktopFrame.maxY - rect.maxY,
                width: rect.width,
                height: rect.height
            ).standardized
        }

        return rect.standardized
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }
}

private struct CaretBubbleIndicatorView: View {
    @ObservedObject var controller: CaretBubbleFloatingIndicatorController
    @ObservedObject var state: FloatingIndicatorState
    @ObservedObject var transcript: LiveTranscriptState
    @ObservedObject private var theme = PindropThemeController.shared
    @State private var idlePulse: Bool = false

    private var showsTranscript: Bool {
        transcript.isActive && (state.isRecording || state.isProcessing)
    }

    private var showsActions: Bool {
        showsTranscript || (state.isRecording && controller.isHovered)
    }

    private var bubbleSize: CGSize { controller.centerBubbleSize }

    private var panelSize: CGSize {
        showsTranscript
            ? CaretBubbleFloatingIndicatorController.LayoutMetrics.streamingPanelSize
            : CaretBubbleFloatingIndicatorController.LayoutMetrics.panelSize
    }

    var body: some View {
        ZStack(alignment: .leading) {
            actionBubble(icon: "xmark", isDestructive: false, action: controller.handleCancelTapped)
                .opacity(showsActions ? 1 : 0)
                .offset(
                    x: controller.actionRevealWidth == 0 ? 10 : 0,
                    y: 9
                )

            centerBubble
                .offset(x: controller.actionRevealWidth, y: 6)

            actionBubble(icon: nil, isDestructive: true, action: controller.handleStopTapped)
                .opacity(showsActions ? 1 : 0)
                .offset(
                    x: controller.actionRevealWidth + bubbleSize.width + 6,
                    y: 9
                )

        }
        .frame(width: panelSize.width, height: panelSize.height, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { controller.setHover($0) }
        .themeRefresh()
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: showsActions)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: showsTranscript)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: controller.actionRevealWidth)
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

    private var centerBubble: some View {
        Button {
            if !state.isRecording && !state.isProcessing {
                controller.handleStartTapped()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: showsTranscript ? 14 : bubbleSize.height / 2, style: .continuous)
                    .fill(AppColors.overlaySurface)
                    .hairlineStroke(
                        RoundedRectangle(cornerRadius: showsTranscript ? 14 : bubbleSize.height / 2, style: .continuous),
                        style: AppColors.overlayLine
                    )
                    .shadow(color: AppColors.shadowColor.opacity(0.18), radius: 8, y: 4)

                if showsTranscript {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            if state.isProcessing {
                                IndicatorProcessingView(dotCount: 3, dotDiameter: 4, spacing: 3)
                            } else {
                                FloatingIndicatorWaveformView(
                                    audioLevel: { state.audioLevel },
                                    isRecording: state.isRecording,
                                    style: .bubble
                                )
                                .frame(width: 24, height: 12)
                            }
                            Spacer(minLength: 0)
                        }
                        LiveTranscriptView(transcript: transcript, fontSize: 11, lineLimit: 3)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                } else if state.isProcessing {
                    IndicatorProcessingView(dotCount: 3, dotDiameter: 4, spacing: 3)
                } else {
                    FloatingIndicatorWaveformView(
                        audioLevel: { state.audioLevel },
                        isRecording: state.isRecording,
                        style: .bubble
                    )
                    .frame(width: 24, height: 12)
                }
            }
            .frame(width: bubbleSize.width, height: bubbleSize.height)
            .scaleEffect(controller.isHovered && state.isRecording && !showsTranscript ? 1.03 : 1)
            .scaleEffect(!state.isRecording && !state.isProcessing ? (idlePulse ? 1.04 : 0.97) : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    idlePulse = true
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func actionBubble(icon: String?, isDestructive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        isDestructive
                            ? AppColors.overlayRecording
                            : AppColors.overlaySurface
                    )
                    .hairlineStroke(Circle(), style: AppColors.overlayLine.opacity(isDestructive ? 0.72 : 1))

                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AppColors.overlayTextPrimary.opacity(0.92))
                } else {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(AppColors.overlayTextPrimary)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 22, height: 22)
            .shadow(color: isDestructive ? AppColors.overlayRecording.opacity(0.2) : AppColors.shadowColor.opacity(0.16), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(showsActions)
    }
}

#Preview("Caret Bubble - Recording") {
    caretBubbleRecordingPreview
}

#Preview("Caret Bubble - Processing") {
    caretBubbleProcessingPreview
}

@MainActor
private var caretBubbleRecordingPreview: some View {
    let state = FloatingIndicatorState()
    let controller = CaretBubbleFloatingIndicatorController(state: state, liveTranscript: LiveTranscriptState())
    state.isRecording = true
    state.updateAudioLevel(0.7)
    controller.isHovered = true

    return CaretBubbleIndicatorView(controller: controller, state: state, transcript: controller.liveTranscript)
        .padding()
        .background(AppColors.windowBackground)
}

@MainActor
private var caretBubbleProcessingPreview: some View {
    let state = FloatingIndicatorState()
    let controller = CaretBubbleFloatingIndicatorController(state: state, liveTranscript: LiveTranscriptState())
    state.isProcessing = true

    return CaretBubbleIndicatorView(controller: controller, state: state, transcript: controller.liveTranscript)
        .padding()
        .background(AppColors.windowBackground)
}
