//
//  FloatingIndicator.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI
import AppKit

private enum NotchPanelMetrics {
    static let fallbackNotchWidth: CGFloat = 186
    static let minimumNotchWidth: CGFloat = 150
    static let baseSideWidth: CGFloat = 102
    static let minimumSideWidth: CGFloat = 82
    static let maximumSideWidth: CGFloat = 118
    static let panelHeightMinimum: CGFloat = 30
    static let horizontalInset: CGFloat = 12
    static let cornerRadius: CGFloat = 14
    static let showHideDuration: TimeInterval = 0.2
    static let hideDuration: TimeInterval = 0.15
    static let sectionDividerOpacity: CGFloat = 0.18
    static let sidePadding: CGFloat = 10
}

extension NSScreen {
    var notchAreaWidth: CGFloat? {
        guard safeAreaInsets.left > 0 else { return nil }
        return safeAreaInsets.left * 2
    }
    
    var hasNotch: Bool {
        safeAreaInsets.top > 0 || notchAreaWidth != nil
    }
    
    var menuBarHeight: CGFloat {
        frame.maxY - visibleFrame.maxY
    }
    
    var notchPanelHeight: CGFloat {
        let notchHeight = safeAreaInsets.top
        return notchHeight > 0 ? notchHeight : menuBarHeight
    }
    
    func notchPanelWidth(fallback: CGFloat = NotchPanelMetrics.fallbackNotchWidth) -> CGFloat {
        guard let areaWidth = notchAreaWidth else { return fallback }
        return max(NotchPanelMetrics.minimumNotchWidth, areaWidth)
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]
        
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false
    }
}

struct NotchShape: Shape {
    let cornerRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.width - cornerRadius, y: rect.height - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: cornerRadius, y: rect.height))
        path.addArc(
            center: CGPoint(x: cornerRadius, y: rect.height - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 0, y: 0))
        
        return path
    }
}

@MainActor
final class FloatingIndicatorController: FloatingIndicatorPresenting {
    let type: FloatingIndicatorType = .notch
    let state: FloatingIndicatorState

    private var panel: NotchPanel?
    private var hostingView: NSHostingView<NotchIndicatorView>?
    private var actions = FloatingIndicatorActions()
    private var screenTrackingTimer: Timer?
    private var lastScreen: NSScreen?

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

    private func show() {
        guard panel == nil else {
            panel?.orderFrontRegardless()
            return
        }
        
        guard let screen = Optional(preferredScreen()) else { return }
        
        let notchWidth = screen.notchPanelWidth(fallback: NotchPanelMetrics.fallbackNotchWidth)
        let maxPanelWidth = max(0, screen.visibleFrame.width - (NotchPanelMetrics.horizontalInset * 2))
        let sideWidthBudget = max(0, maxPanelWidth - notchWidth)
        let dynamicSideWidth = max(
            NotchPanelMetrics.minimumSideWidth,
            min(NotchPanelMetrics.baseSideWidth, sideWidthBudget / 2)
        )
        let sideWidth = min(NotchPanelMetrics.maximumSideWidth, dynamicSideWidth)
        let panelHeight = screen.hasNotch
            ? screen.notchPanelHeight
            : max(NotchPanelMetrics.panelHeightMinimum, screen.notchPanelHeight)
        let expandedWidth = notchWidth + (sideWidth * 2)
        let panelWidth = min(expandedWidth, maxPanelWidth)
        
        let xPosition = screen.visibleFrame.midX - (panelWidth / 2)
        let yPosition = screen.frame.maxY - panelHeight
        
        let clampedXPosition = max(
            screen.visibleFrame.minX + NotchPanelMetrics.horizontalInset,
            min(
                xPosition,
                screen.visibleFrame.maxX - panelWidth - NotchPanelMetrics.horizontalInset
            )
        )
        let contentRect = NSRect(
            x: clampedXPosition,
            y: yPosition,
            width: panelWidth,
            height: panelHeight
        )
        let panel = NotchPanel(contentRect: contentRect)
        
        let contentView = NotchIndicatorView(
            state: state,
            notchWidth: notchWidth,
            sideWidth: sideWidth,
            height: panelHeight,
            onStopRecording: { [weak self] in
                self?.handleStopButtonTapped()
            }
        )
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        self.hostingView = hostingView
        
        panel.contentView = hostingView
        self.panel = panel
        self.lastScreen = screen
        
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        
        let localPanel = panel
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NotchPanelMetrics.showHideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            localPanel.animator().alphaValue = 1
        }
        
        startScreenTracking()
    }
    
    func hide() {
        stopScreenTracking()
        guard let panel = panel else { return }
        let localPanel = panel
        let localHostingView = hostingView

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NotchPanelMetrics.hideDuration
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
    
    func startRecording() {
        state.startRecording()
        show()
    }
    
    func transitionToProcessing() {
        state.transitionToProcessing()
    }
    
    func finishProcessing() {
        state.finishSession()
        hide()
    }

    func handleStopButtonTapped() {
        actions.onStopRecording?(type)
    }
    
    private func startScreenTracking() {
        screenTrackingTimer?.invalidate()
        screenTrackingTimer = Timer.pindrop_scheduleRepeating(interval: 0.05) { [weak self] _ in
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
    
    private func checkAndUpdateScreenPosition() {
        guard let panel = panel else { return }
        guard let currentScreen = Optional(preferredScreen()) else { return }
        
        if lastScreen?.pindrop_isSameDisplay(as: currentScreen) == false || lastScreen == nil {
            lastScreen = currentScreen
            
            let notchWidth = currentScreen.notchPanelWidth(fallback: NotchPanelMetrics.fallbackNotchWidth)
            let maxPanelWidth = max(0, currentScreen.visibleFrame.width - (NotchPanelMetrics.horizontalInset * 2))
            let sideWidthBudget = max(0, maxPanelWidth - notchWidth)
            let dynamicSideWidth = max(
                NotchPanelMetrics.minimumSideWidth,
                min(NotchPanelMetrics.baseSideWidth, sideWidthBudget / 2)
            )
            let sideWidth = min(NotchPanelMetrics.maximumSideWidth, dynamicSideWidth)
            let panelHeight = currentScreen.hasNotch
                ? currentScreen.notchPanelHeight
                : max(NotchPanelMetrics.panelHeightMinimum, currentScreen.notchPanelHeight)
            let expandedWidth = notchWidth + (sideWidth * 2)
            let panelWidth = min(expandedWidth, maxPanelWidth)
            
            let xPosition = currentScreen.visibleFrame.midX - (panelWidth / 2)
            let yPosition = currentScreen.frame.maxY - panelHeight
            
            let clampedXPosition = max(
                currentScreen.visibleFrame.minX + NotchPanelMetrics.horizontalInset,
                min(
                    xPosition,
                    currentScreen.visibleFrame.maxX - panelWidth - NotchPanelMetrics.horizontalInset
                )
            )
            
            let newFrame = NSRect(
                x: clampedXPosition,
                y: yPosition,
                width: panelWidth,
                height: panelHeight
            )
            panel.setFrame(newFrame, display: true, animate: true)
        }
    }

    private func preferredScreen() -> NSScreen {
        actions.preferredScreenProvider?() ?? NSScreen.screenUnderMouse()
    }
}

struct NotchIndicatorView: View {
    @ObservedObject var state: FloatingIndicatorState
    let notchWidth: CGFloat
    let sideWidth: CGFloat
    let height: CGFloat
    let onStopRecording: () -> Void
    
    private var formattedDuration: String {
        let minutes = Int(state.recordingDuration) / 60
        let seconds = Int(state.recordingDuration) % 60
        let tenths = Int((state.recordingDuration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            leftSide
            centerSection
                .frame(width: notchWidth)
            rightSide
        }
        .frame(maxWidth: .infinity, maxHeight: height)
        .background(AppColors.overlaySurfaceStrong)
        .clipShape(NotchShape(cornerRadius: NotchPanelMetrics.cornerRadius))
        .themeRefresh()
    }
    
    private var leftSide: some View {
        HStack(spacing: 8) {
            if state.isRecording {
                stopButton
            } else {
                processingIndicator
            }

            timerDisplay
            Spacer(minLength: 0)
        }
        .padding(.leading, NotchPanelMetrics.sidePadding)
        .padding(.trailing, 8)
        .frame(width: sideWidth, height: height)
    }
    
    private var centerSection: some View {
        ZStack {
            AppColors.overlaySurface

            if state.isProcessing {
                ProgressView()
                    .controlSize(.mini)
                    .tint(AppColors.overlayTextPrimary.opacity(0.9))
            }
        }
        .frame(width: notchWidth, height: height)
    }

    private var rightSide: some View {
        FloatingIndicatorWaveformView(
            audioLevel: state.audioLevel,
            isRecording: state.isRecording,
            style: .notch
        )
        .frame(maxWidth: .infinity, maxHeight: 18, alignment: .leading)
        .padding(.leading, 10)
        .padding(.trailing, NotchPanelMetrics.sidePadding)
        .frame(width: sideWidth, height: height)
    }
    
    private var stopButton: some View {
        Button {
            onStopRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(AppColors.overlayRecording)
                    .frame(width: 18, height: 18)
                    .shadow(color: AppColors.overlayRecording.opacity(0.28), radius: 4)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.overlayTextPrimary)
                    .frame(width: 6, height: 6)
            }
        }
        .buttonStyle(.plain)
        .overlay(pulsingRing)
    }
    
    private var pulsingRing: some View {
        Circle()
            .stroke(AppColors.overlayRecording.opacity(0.5), lineWidth: 1.6)
            .frame(width: 18, height: 18)
            .scaleEffect(state.isRecording ? 1.4 : 1)
            .opacity(state.isRecording ? 0 : 0.2)
            .animation(
                state.isRecording
                    ? .easeOut(duration: 1.1).repeatForever(autoreverses: false)
                    : .easeInOut(duration: 0.2),
                value: state.isRecording
            )
    }
    
    private var processingIndicator: some View {
        ZStack {
            Circle()
                .fill(AppColors.overlayWarning)
                .frame(width: 20, height: 20)
            
            ProgressView()
                .scaleEffect(0.45)
                .tint(AppColors.overlayTextPrimary)
        }
    }
    
    private var timerDisplay: some View {
        HStack(spacing: 6) {
            Text(state.isProcessing ? "..." : formattedDuration)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.overlayTextPrimary)
            
            if state.escapePrimed {
                Circle()
                    .fill(AppColors.overlayWarning)
                    .frame(width: 6, height: 6)
                    .transition(.scale.combined(with: .opacity))
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.15), value: state.escapePrimed)
    }
}

#Preview("Notch Indicator - Recording") {
    notchRecordingPreview
}

#Preview("Notch Indicator - Processing") {
    notchProcessingPreview
}

@MainActor
private var notchRecordingPreview: some View {
    let state = FloatingIndicatorState()
    state.isRecording = true
    state.recordingDuration = 5.3
    state.audioLevel = 0.6

    return NotchIndicatorView(state: state, notchWidth: 185, sideWidth: 100, height: 38, onStopRecording: {})
        .frame(width: 385, height: 38)
        .background(AppColors.windowBackground)
}

@MainActor
private var notchProcessingPreview: some View {
    let state = FloatingIndicatorState()
    state.isRecording = false
    state.isProcessing = true
    state.recordingDuration = 12.7
    state.audioLevel = 0.0

    return NotchIndicatorView(state: state, notchWidth: 185, sideWidth: 100, height: 38, onStopRecording: {})
        .frame(width: 385, height: 38)
        .background(AppColors.windowBackground)
}
