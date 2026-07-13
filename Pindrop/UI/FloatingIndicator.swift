//
//  FloatingIndicator.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI
import AppKit
import Combine

enum NotchPanelMetrics {
    static let fallbackNotchWidth: CGFloat = 186
    static let minimumNotchWidth: CGFloat = 150
    static let baseSideWidth: CGFloat = 102
    static let minimumSideWidth: CGFloat = 82
    static let maximumSideWidth: CGFloat = 118
    static let panelHeightMinimum: CGFloat = 30
    static let horizontalInset: CGFloat = 12
    static let cornerRadius: CGFloat = 14
    /// Softer bottom corners while the transcript drop is extended.
    static let expandedCornerRadius: CGFloat = 19
    /// Radius of the concave fillet where the panel's sides meet the screen's
    /// top edge — the outward curve of the hardware-notch silhouette.
    static let topFlareRadius: CGFloat = 7
    static let showHideDuration: TimeInterval = 0.2
    static let hideDuration: TimeInterval = 0.15
    static let sidePadding: CGFloat = 12
    /// Dynamic-Island-style downward extension while the live transcript is showing.
    /// Sized for three lines of 12 pt transcript plus padding (see `NotchIndicatorView`).
    static let transcriptDropHeight: CGFloat = 70
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
        // Round to avoid sub-pixel gaps when placing a panel flush with the screen top.
        (frame.maxY - visibleFrame.maxY).rounded(.up)
    }

    var notchPanelHeight: CGFloat {
        let notchHeight = safeAreaInsets.top
        // Use ceil so the panel always covers the full hardware notch even on fractional scales.
        return notchHeight > 0 ? ceil(notchHeight) : menuBarHeight
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

/// The hardware-notch silhouette: sides flare outward through a concave fillet
/// where they meet the screen's top edge (the black widens as it reaches the
/// edge, like the physical notch joining the display border), then drop to
/// rounded bottom corners.
struct NotchShape: Shape {
    var cornerRadius: CGFloat
    var topFlareRadius: CGFloat = NotchPanelMetrics.topFlareRadius

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let flare = min(topFlareRadius, rect.height / 2)
        let radius = cornerRadius
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        // Top-right flare: concave fillet from the top edge into the body side.
        path.addArc(
            center: CGPoint(x: rect.width, y: flare),
            radius: flare,
            startAngle: .degrees(270),
            endAngle: .degrees(180),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.width - flare, y: rect.height - radius))
        path.addArc(
            center: CGPoint(x: rect.width - flare - radius, y: rect.height - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: flare + radius, y: rect.height))
        path.addArc(
            center: CGPoint(x: flare + radius, y: rect.height - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: flare, y: flare))
        // Top-left flare, mirroring the right.
        path.addArc(
            center: CGPoint(x: 0, y: flare),
            radius: flare,
            startAngle: .degrees(0),
            endAngle: .degrees(270),
            clockwise: true
        )
        path.closeSubpath()

        return path
    }
}

/// Pure geometry for the notch panel, extracted from the controller so layout
/// rules (transcript drop, side-width budget, edge clamping) are unit-testable
/// without an `NSScreen`.
enum NotchPanelLayoutMath {
    struct Layout: Equatable {
        var frame: CGRect
        var notchWidth: CGFloat
        var sideWidth: CGFloat
        var rowHeight: CGFloat
    }

    static func compute(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        notchWidth: CGFloat,
        rowHeight: CGFloat,
        transcriptDropActive: Bool
    ) -> Layout {
        let maxPanelWidth = max(0, visibleFrame.width - (NotchPanelMetrics.horizontalInset * 2))
        let sideWidthBudget = max(0, maxPanelWidth - notchWidth)
        let dynamicSideWidth = max(
            NotchPanelMetrics.minimumSideWidth,
            min(NotchPanelMetrics.baseSideWidth, sideWidthBudget / 2)
        )
        let sideWidth = min(NotchPanelMetrics.maximumSideWidth, dynamicSideWidth)
        let panelHeight = rowHeight
            + (transcriptDropActive ? NotchPanelMetrics.transcriptDropHeight : 0)
        let expandedWidth = notchWidth + (sideWidth * 2)
        let panelWidth = min(expandedWidth, maxPanelWidth)

        let xPosition = visibleFrame.midX - (panelWidth / 2)
        // Anchor the panel's TOP edge to the very top of the screen frame; the
        // transcript drop extends downward.
        let yPosition = screenFrame.maxY - panelHeight

        let clampedXPosition = max(
            visibleFrame.minX + NotchPanelMetrics.horizontalInset,
            min(
                xPosition,
                visibleFrame.maxX - panelWidth - NotchPanelMetrics.horizontalInset
            )
        )
        return Layout(
            frame: CGRect(x: clampedXPosition, y: yPosition, width: panelWidth, height: panelHeight),
            notchWidth: notchWidth,
            sideWidth: sideWidth,
            rowHeight: rowHeight
        )
    }
}

@MainActor
final class FloatingIndicatorController: FloatingIndicatorPresenting {
    let type: FloatingIndicatorType = .notch
    let state: FloatingIndicatorState
    let liveTranscript: LiveTranscriptState

    private var panel: NotchPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var actions = FloatingIndicatorActions()
    private var screenTrackingTimer: Timer?
    private var lastScreen: NSScreen?
    private var phaseCancellables = Set<AnyCancellable>()
    /// Bumped on every show/hide so stale hide completions cannot tear down a
    /// panel that has been reused for a newer recording session.
    private var presentationGeneration: UInt = 0

    init(state: FloatingIndicatorState, liveTranscript: LiveTranscriptState) {
        self.state = state
        self.liveTranscript = liveTranscript

        // The notch extends downward while the live transcript shows — resize on
        // phase transitions only, never on text growth. DispatchQueue (not RunLoop)
        // delivery so the resize still lands during event-tracking run-loop modes
        // (open menus, window drags) instead of waiting for them to finish.
        liveTranscript.$phase
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyPanelFrameForCurrentScreen(animated: true)
            }
            .store(in: &phaseCancellables)
    }

    /// Geometry for the panel on `screen`, including the transcript drop when active.
    private func panelLayout(for screen: NSScreen) -> NotchPanelLayoutMath.Layout {
        let rowHeight = screen.hasNotch
            ? screen.notchPanelHeight
            : max(NotchPanelMetrics.panelHeightMinimum, screen.notchPanelHeight)
        return NotchPanelLayoutMath.compute(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            notchWidth: screen.notchPanelWidth(fallback: NotchPanelMetrics.fallbackNotchWidth),
            rowHeight: rowHeight,
            transcriptDropActive: liveTranscript.isActive
        )
    }

    private func applyPanelFrameForCurrentScreen(animated: Bool) {
        guard let panel else { return }
        let screen = lastScreen ?? preferredScreen()
        let layout = panelLayout(for: screen)
        panel.setFrame(layout.frame, display: true, animate: animated)
        hostingView?.frame = NSRect(origin: .zero, size: layout.frame.size)
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

    private func show() {
        // Invalidate any in-flight hide so its completion cannot close this panel.
        presentationGeneration &+= 1

        if let existingPanel = panel {
            lastScreen = preferredScreen()
            // A reused panel may carry a stale frame (different screen, or a
            // transcript drop that toggled while hidden) — resync before showing.
            applyPanelFrameForCurrentScreen(animated: false)
            existingPanel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NotchPanelMetrics.showHideDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                existingPanel.animator().alphaValue = 1
            }
            startScreenTracking()
            return
        }

        guard let screen = Optional(preferredScreen()) else { return }

        let layout = panelLayout(for: screen)
        let panel = NotchPanel(contentRect: layout.frame)

        let appLocale = AppLocale.currentSelection()
        let contentView = AnyView(NotchIndicatorView(
            state: state,
            transcript: liveTranscript,
            notchWidth: layout.notchWidth,
            sideWidth: layout.sideWidth,
            height: layout.rowHeight,
            onStopRecording: { [weak self] in
                self?.handleStopButtonTapped()
            }
        )
        .environment(\.locale, appLocale.locale)
        .environment(\.layoutDirection, .leftToRight))
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.userInterfaceLayoutDirection = .leftToRight
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

        presentationGeneration &+= 1
        let hideGeneration = presentationGeneration
        let localPanel = panel
        let localHostingView = hostingView

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NotchPanelMetrics.hideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            localPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                guard FloatingIndicatorPresentationLifecycle.shouldApplyHideCompletion(
                    hideGeneration: hideGeneration,
                    currentGeneration: self.presentationGeneration
                ) else {
                    return
                }
                guard self.panel === localPanel else { return }
                localPanel.close()
                self.panel = nil
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
        guard panel != nil else { return }
        guard let currentScreen = Optional(preferredScreen()) else { return }

        if lastScreen?.pindrop_isSameDisplay(as: currentScreen) == false || lastScreen == nil {
            lastScreen = currentScreen
            applyPanelFrameForCurrentScreen(animated: true)
        }
    }

    private func preferredScreen() -> NSScreen {
        actions.preferredScreenProvider?() ?? NSScreen.screenUnderMouse()
    }
}

struct NotchIndicatorView: View {
    @ObservedObject var state: FloatingIndicatorState
    @ObservedObject var transcript: LiveTranscriptState
    @ObservedObject private var theme = PindropThemeController.shared
    let notchWidth: CGFloat
    let sideWidth: CGFloat
    let height: CGFloat
    let onStopRecording: () -> Void

    private var formattedDuration: String {
        let minutes = Int(state.recordingDuration) / 60
        let seconds = Int(state.recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var showsTranscript: Bool { transcript.isActive }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leftWing
                // The hardware notch occludes this region on notched displays, so it
                // stays pure black and empty — content here would be invisible on the
                // very machines this indicator imitates.
                Color.clear
                    .frame(width: notchWidth)
                rightWing
            }
            .frame(height: height)

            if showsTranscript {
                // Dynamic-Island-style drop: full-width transcript area below the
                // notch row, same black surface so it reads as the notch extending.
                LiveTranscriptView(transcript: transcript, fontSize: 12, lineLimit: 3)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: NotchPanelMetrics.transcriptDropHeight)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .clipShape(NotchShape(
            cornerRadius: showsTranscript
                ? NotchPanelMetrics.expandedCornerRadius
                : NotchPanelMetrics.cornerRadius
        ))
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.2), value: showsTranscript)
        .themeRefresh()
    }

    private var leftWing: some View {
        ZStack {
            HStack(spacing: 8) {
                if state.isRecording {
                    stopButton
                } else {
                    IndicatorProcessingView(dotCount: 3, dotDiameter: 3.5, spacing: 2.5)
                        .frame(width: 18, height: 18)
                }

                timerDisplay
                Spacer(minLength: 0)
            }
            .opacity(state.recentCompletion != nil ? 0 : 1)

            if let completion = state.recentCompletion {
                HStack(spacing: 5) {
                    Image(systemName: completion.icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppColors.overlayTooltipAccent)
                    Text(completion.title(locale: .autoupdatingCurrent))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.overlayTextPrimary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .leading)),
                    removal: .opacity
                ))
            }
        }
        .padding(.leading, NotchPanelMetrics.sidePadding)
        .padding(.trailing, 8)
        .frame(width: sideWidth, height: height)
        .animation(AppTheme.Animation.smooth, value: state.recentCompletion)
    }

    private var rightWing: some View {
        FloatingIndicatorScrollingWaveformView(
            audioLevel: { state.audioLevel },
            isRecording: state.isRecording,
            color: AppColors.overlayWaveform
        )
        .frame(height: 15)
        .opacity(state.isRecording ? 1 : 0.4)
        .animation(AppTheme.Animation.smooth, value: state.isRecording)
        .padding(.leading, 8)
        .padding(.trailing, NotchPanelMetrics.sidePadding)
        .frame(width: sideWidth, height: height)
    }

    private var stopButton: some View {
        Button {
            onStopRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(AppColors.overlayRecording.opacity(0.16))
                Circle()
                    .strokeBorder(AppColors.overlayRecording.opacity(0.65), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(AppColors.overlayRecording)
                    .frame(width: 7, height: 7)
            }
            .frame(width: 18, height: 18)
            .shadow(color: AppColors.overlayRecording.opacity(0.35), radius: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized("Stop Recording", locale: .autoupdatingCurrent))
    }

    private var timerDisplay: some View {
        Text(formattedDuration)
            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(AppColors.overlayTextPrimary.opacity(state.isProcessing ? 0.55 : 0.92))
            .contentTransition(.numericText(countsDown: false))
            .animation(AppTheme.Animation.fast, value: state.recordingDuration)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Notch Indicator - Recording") {
    notchRecordingPreview
}

#Preview("Notch Indicator - Streaming Transcript") {
    notchStreamingPreview
}

#Preview("Notch Indicator - Processing") {
    notchProcessingPreview
}

@MainActor
private var notchRecordingPreview: some View {
    let state = FloatingIndicatorState()
    state.isRecording = true
    state.recordingDuration = 5.3
    state.updateAudioLevel(0.6)

    return NotchIndicatorView(state: state, transcript: LiveTranscriptState(), notchWidth: 185, sideWidth: 100, height: 38, onStopRecording: {})
        .frame(width: 385, height: 38)
        .background(AppColors.windowBackground)
}

@MainActor
private var notchStreamingPreview: some View {
    let state = FloatingIndicatorState()
    state.isRecording = true
    state.recordingDuration = 8.2
    state.updateAudioLevel(0.5)

    let transcript = LiveTranscriptState()
    transcript.begin()
    transcript.update(
        committed: "The quick brown fox jumps over the lazy dog while the",
        tentative: "notch shows every word as it lands"
    )

    return NotchIndicatorView(state: state, transcript: transcript, notchWidth: 185, sideWidth: 100, height: 38, onStopRecording: {})
        .frame(width: 385, height: 38 + NotchPanelMetrics.transcriptDropHeight)
        .background(AppColors.windowBackground)
}

@MainActor
private var notchProcessingPreview: some View {
    let state = FloatingIndicatorState()
    state.isRecording = false
    state.isProcessing = true
    state.recordingDuration = 12.7
    state.updateAudioLevel(0.0)

    return NotchIndicatorView(state: state, transcript: LiveTranscriptState(), notchWidth: 185, sideWidth: 100, height: 38, onStopRecording: {})
        .frame(width: 385, height: 38)
        .background(AppColors.windowBackground)
}
