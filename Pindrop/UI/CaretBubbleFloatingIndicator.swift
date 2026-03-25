//
//  CaretBubbleFloatingIndicator.swift
//  Pindrop
//
//  Created on 2026-03-06.
//

import AppKit
import SwiftUI

@MainActor
final class CaretBubbleFloatingIndicatorController: FloatingIndicatorPresenting, ObservableObject {
    let type: FloatingIndicatorType = .bubble
    let state: FloatingIndicatorState

    @Published var isHovered = false
    @Published private(set) var actionRevealWidth: CGFloat = 0
    @Published private(set) var isDragging = false

    private enum LayoutMetrics {
        static let panelSize = CGSize(width: 98, height: 40)
        static let centerBubbleSize = CGSize(width: 42, height: 28)
        static let actionBubbleSize = CGSize(width: 22, height: 22)
        static let actionSpacing: CGFloat = 6
        static let horizontalGap: CGFloat = 12
        static let verticalGap: CGFloat = 10
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

    private var panel: NSPanel?
    private var hostingView: NSHostingView<CaretBubbleIndicatorView>?
    private var actions = FloatingIndicatorActions()
    private var anchorRefreshTimer: Timer?
    private var isVisible = false
    private var dragStartMouseLocation: CGPoint?
    private var manualOffset: CGSize = .zero
    private var dragStartOffset: CGSize = .zero

    init(state: FloatingIndicatorState) {
        self.state = state
    }

    func configure(actions: FloatingIndicatorActions) {
        self.actions = actions
    }

    func showIdleIndicator() {
        hide()
    }

    func showForCurrentState() {
        if panel == nil {
            show()
        } else {
            panel?.orderFrontRegardless()
        }
    }

    func startRecording() {
        state.startRecording()
        isHovered = false
        actionRevealWidth = 0
        show()
        refreshAnchorPosition(animated: false)
    }

    func transitionToProcessing() {
        state.transitionToProcessing()
        isHovered = false
        actionRevealWidth = 0
        show()
        refreshAnchorPosition(animated: false)
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
        let localPanel = panel
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            localPanel.animator().alphaValue = 0
        }) { [weak self] in
            localPanel.orderOut(nil)
            Task { @MainActor [weak self] in
                self?.panel = nil
                self?.hostingView = nil
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
        actionRevealWidth = hovering ? (LayoutMetrics.actionBubbleSize.width + LayoutMetrics.actionSpacing) : 0
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
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: LayoutMetrics.panelSize),
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

            let contentView = CaretBubbleIndicatorView(controller: self, state: state)
            let hostingView = NSHostingView(rootView: contentView)
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            hostingView.wantsLayer = true
            hostingView.frame = NSRect(origin: .zero, size: LayoutMetrics.panelSize)

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
        let size = LayoutMetrics.panelSize
        let anchorRect = actions.anchorProvider?().map(convertToAppKitScreenCoordinates)
        let screen = preferredScreen(for: anchorRect) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        guard let anchorRect, !anchorRect.isEmpty else {
            return applyManualOffset(
                to: NSRect(origin: fallbackOrigin(in: visibleFrame), size: size),
                within: visibleFrame
            )
        }

        for placement in BubblePlacement.allCases {
            if let frame = frame(for: placement, anchorRect: anchorRect, visibleFrame: visibleFrame) {
                return applyManualOffset(to: frame, within: visibleFrame)
            }
        }

        return applyManualOffset(
            to: clampedFrame(
                x: anchorRect.midX - (LayoutMetrics.centerBubbleSize.width / 2) - actionRevealWidth,
                y: anchorRect.maxY + LayoutMetrics.verticalGap - verticalBubbleInset,
                within: visibleFrame
            ),
            within: visibleFrame
        )
    }

    private func frame(for placement: BubblePlacement, anchorRect: CGRect, visibleFrame: CGRect) -> NSRect? {
        switch placement {
        case .above:
            let y = anchorRect.maxY + LayoutMetrics.verticalGap - verticalBubbleInset
            guard y + LayoutMetrics.panelSize.height <= visibleFrame.maxY - LayoutMetrics.screenInset else { return nil }
            let x = anchorRect.midX - (LayoutMetrics.centerBubbleSize.width / 2) - actionRevealWidth
            return clampedFrame(x: x, y: y, within: visibleFrame)

        case .left:
            let x = anchorRect.minX - LayoutMetrics.horizontalGap - LayoutMetrics.centerBubbleSize.width - actionRevealWidth
            guard x >= visibleFrame.minX + LayoutMetrics.screenInset else { return nil }
            let y = anchorRect.midY - (LayoutMetrics.centerBubbleSize.height / 2) - verticalBubbleInset
            return clampedFrame(x: x, y: y, within: visibleFrame)

        case .right:
            let x = anchorRect.maxX + LayoutMetrics.horizontalGap - actionRevealWidth
            guard x + LayoutMetrics.panelSize.width <= visibleFrame.maxX - LayoutMetrics.screenInset else { return nil }
            let y = anchorRect.midY - (LayoutMetrics.centerBubbleSize.height / 2) - verticalBubbleInset
            return clampedFrame(x: x, y: y, within: visibleFrame)

        case .below:
            let y = anchorRect.minY - LayoutMetrics.verticalGap - LayoutMetrics.centerBubbleSize.height - verticalBubbleInset
            guard y >= visibleFrame.minY + LayoutMetrics.screenInset else { return nil }
            let x = anchorRect.midX - (LayoutMetrics.centerBubbleSize.width / 2) - actionRevealWidth
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
            x: visibleFrame.maxX - LayoutMetrics.panelSize.width - 24,
            y: visibleFrame.minY + LayoutMetrics.fallbackBottomInset
        )
    }

    private var verticalBubbleInset: CGFloat {
        (LayoutMetrics.panelSize.height - LayoutMetrics.centerBubbleSize.height) / 2
    }

    private func clampedFrame(x: CGFloat, y: CGFloat, within visibleFrame: CGRect) -> NSRect {
        NSRect(
            x: clamp(
                x,
                min: visibleFrame.minX + LayoutMetrics.screenInset,
                max: visibleFrame.maxX - LayoutMetrics.panelSize.width - LayoutMetrics.screenInset
            ),
            y: clamp(
                y,
                min: visibleFrame.minY + LayoutMetrics.screenInset,
                max: visibleFrame.maxY - LayoutMetrics.panelSize.height - LayoutMetrics.screenInset
            ),
            width: LayoutMetrics.panelSize.width,
            height: LayoutMetrics.panelSize.height
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

    private var showsHoverActions: Bool {
        state.isRecording && controller.isHovered
    }

    var body: some View {
        ZStack(alignment: .leading) {
            actionBubble(icon: "xmark", isDestructive: false, action: controller.handleCancelTapped)
                .opacity(showsHoverActions ? 1 : 0)
                .offset(
                    x: controller.actionRevealWidth == 0 ? 10 : 0,
                    y: 9
                )

            centerBubble
                .offset(x: controller.actionRevealWidth, y: 6)

            actionBubble(icon: nil, isDestructive: true, action: controller.handleStopTapped)
                .opacity(showsHoverActions ? 1 : 0)
                .offset(
                    x: controller.actionRevealWidth + 48,
                    y: 9
                )
        }
        .frame(width: 98, height: 40, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { controller.setHover($0) }
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: showsHoverActions)
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
                Capsule()
                    .fill(AppColors.overlaySurface)
                    .hairlineStroke(Capsule(), style: AppColors.overlayLine)
                    .shadow(color: AppColors.shadowColor.opacity(0.18), radius: 8, y: 4)

                if state.isProcessing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(AppColors.overlayTextPrimary.opacity(0.92))
                } else {
                    FloatingIndicatorWaveformView(
                        audioLevel: state.audioLevel,
                        isRecording: state.isRecording,
                        style: .bubble
                    )
                        .frame(width: 24, height: 12)
                }
            }
            .frame(width: 42, height: 28)
            .scaleEffect(controller.isHovered && state.isRecording ? 1.03 : 1)
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
        .allowsHitTesting(showsHoverActions)
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
    let controller = CaretBubbleFloatingIndicatorController(state: state)
    state.isRecording = true
    state.audioLevel = 0.7
    controller.isHovered = true

    return CaretBubbleIndicatorView(controller: controller, state: state)
        .padding()
        .background(AppColors.windowBackground)
}

@MainActor
private var caretBubbleProcessingPreview: some View {
    let state = FloatingIndicatorState()
    let controller = CaretBubbleFloatingIndicatorController(state: state)
    state.isProcessing = true

    return CaretBubbleIndicatorView(controller: controller, state: state)
        .padding()
        .background(AppColors.windowBackground)
}
