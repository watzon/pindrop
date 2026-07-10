//
//  ToastWindowController.swift
//  Pindrop
//
//  Created on 2026-03-11.
//

import AppKit
import SwiftUI

private enum ToastMetrics {
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 11
    static let buttonSpacing: CGFloat = 10
    static let toastSpacing: CGFloat = 10
    static let screenInset: CGFloat = 28
    static let bottomInset: CGFloat = 42
    static let maxWidth: CGFloat = 520
    static let minWidth: CGFloat = 120
    static let showDuration: TimeInterval = 0.18
    static let hideDuration: TimeInterval = 0.14
    static let cornerRadius: CGFloat = 12
}

private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ToastWindowController: ToastPresenting {
    private var panel: ToastPanel?
    private var hostingView: NSHostingView<AnyView>?

    func show(
        payload: ToastPayload,
        onAction: @escaping (UUID) -> Void,
        onHoverChange: @escaping (Bool) -> Void
    ) {
        let appLocale = AppLocale.currentSelection()
        let rootView = AnyView(ToastView(
            payload: payload,
            onAction: onAction,
            onHoverChange: { [weak self] (isHovering: Bool) in
                onHoverChange(isHovering)
                self?.updateToastFrame(for: payload)
            }
        )
        .environment(\.locale, appLocale.locale)
        .environment(\.layoutDirection, appLocale.layoutDirection))
        let hostingView = self.hostingView ?? NSHostingView(rootView: rootView)
        hostingView.rootView = rootView
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layoutSubtreeIfNeeded()

        let fittedSize = hostingView.fittingSize
        let size = CGSize(
            width: min(max(fittedSize.width, ToastMetrics.minWidth), ToastMetrics.maxWidth),
            height: fittedSize.height
        )
        let frame = frameForToast(
            size: size,
            hintRect: payload.screenHintRect,
            placement: payload.placement
        )

        if panel == nil {
            let panel = ToastPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .mainMenu + 2
            panel.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            panel.contentView = hostingView
            panel.alphaValue = 0
            applyInterfaceLayoutDirection(to: panel, locale: appLocale.locale)
            panel.orderFrontRegardless()

            self.panel = panel
            self.hostingView = hostingView

            NSAnimationContext.runAnimationGroup { context in
                context.duration = ToastMetrics.showDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
            return
        }

        self.hostingView = hostingView
        panel?.contentView = hostingView
        if let panel {
            applyInterfaceLayoutDirection(to: panel, locale: appLocale.locale)
        }
        panel?.setFrame(frame, display: true)
        panel?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = ToastMetrics.showDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel else { return }
        let closingPanel = panel

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = ToastMetrics.hideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            closingPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            closingPanel.orderOut(nil)
            Task { @MainActor [weak self] in
                self?.panel = nil
                self?.hostingView = nil
            }
        })
    }

    private func frameForToast(
        size: CGSize,
        hintRect: CGRect?,
        placement: ToastPlacement
    ) -> NSRect {
        let screen = screen(for: hintRect) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let clampedWidth = min(size.width, max(ToastMetrics.minWidth, visibleFrame.width - (ToastMetrics.screenInset * 2)))
        let originX: CGFloat
        switch placement {
        case .bottomCenter:
            originX = visibleFrame.midX - (clampedWidth / 2)
        case .bottomTrailing:
            originX = visibleFrame.maxX - clampedWidth - ToastMetrics.screenInset
        }
        let origin = CGPoint(
            x: originX,
            y: visibleFrame.minY + ToastMetrics.bottomInset
        )
        let rawFrame = NSRect(origin: origin, size: CGSize(width: clampedWidth, height: size.height))

        return NSRect(
            x: max(visibleFrame.minX + ToastMetrics.screenInset, min(rawFrame.origin.x, visibleFrame.maxX - rawFrame.width - ToastMetrics.screenInset)),
            y: max(visibleFrame.minY + ToastMetrics.screenInset, rawFrame.origin.y),
            width: rawFrame.width,
            height: rawFrame.height
        )
    }

    private func screen(for hintRect: CGRect?) -> NSScreen? {
        guard let hintRect, !hintRect.isEmpty else { return NSScreen.main }
        return NSScreen.screens.first(where: { $0.frame.intersects(hintRect) }) ?? NSScreen.main
    }

    private func updateToastFrame(for payload: ToastPayload) {
        guard let panel, let hostingView else { return }

        DispatchQueue.main.async { [weak self, weak panel, weak hostingView] in
            guard let self, let panel, let hostingView else { return }
            hostingView.layoutSubtreeIfNeeded()

            let fittedSize = hostingView.fittingSize
            let size = CGSize(
                width: min(max(fittedSize.width, ToastMetrics.minWidth), ToastMetrics.maxWidth),
                height: fittedSize.height
            )
            let frame = self.frameForToast(
                size: size,
                hintRect: payload.screenHintRect,
                placement: payload.placement
            )

            NSAnimationContext.runAnimationGroup { context in
                context.duration = ToastMetrics.showDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        }
    }
}

private struct ToastView: View {
    let payload: ToastPayload
    let onAction: (UUID) -> Void
    let onHoverChange: (Bool) -> Void

    @State private var isHovering = false
    @State private var showsWrappedText = false
    @State private var usesExpandedLayout = false
    @State private var wrapRevealTask: Task<Void, Never>?
    @State private var lockedWidth: CGFloat?
    @Environment(\.locale) private var locale

    private var expandedWidth: CGFloat? {
        guard usesExpandedLayout || showsWrappedText else { return nil }
        return lockedWidth
    }

    var body: some View {
        HStack(alignment: .center, spacing: ToastMetrics.toastSpacing) {
            Image(systemName: ToastVariantPresentation.systemImage(for: payload.variant, style: payload.style))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(leadingColor)
                .frame(width: 14, height: 14)

            ZStack(alignment: .leading) {
                if usesExpandedLayout && !showsWrappedText {
                    messageText(wrapped: true)
                        .hidden()
                        .accessibilityHidden(true)
                }

                messageText(wrapped: showsWrappedText)
            }
                .frame(maxWidth: .infinity, alignment: .leading)

            if let meta = ToastVariantPresentation.trailingText(for: payload.variant, locale: locale) {
                Text(meta)
                    .font(FontLoader.font(family: .jetbrainsMono, size: 11, weight: .regular))
                    .foregroundStyle(Color(nsColor: NSColor(pindropHex: "#A59D8C") ?? .secondaryLabelColor))
                    .fixedSize()
            }

            if !payload.actions.isEmpty {
                HStack(spacing: ToastMetrics.buttonSpacing) {
                    ForEach(Array(payload.actions.enumerated()), id: \.element.id) { _, action in
                        Button(action.title) {
                            onAction(action.id)
                        }
                        .buttonStyle(ToastActionButtonStyle(role: action.role))
                    }
                }
            }
        }
        .padding(.horizontal, ToastMetrics.horizontalPadding)
        .padding(.vertical, ToastMetrics.verticalPadding)
        .frame(width: expandedWidth, alignment: .leading)
        .frame(maxWidth: ToastMetrics.maxWidth)
        .background(
            RoundedRectangle(cornerRadius: ToastMetrics.cornerRadius, style: .continuous)
                .fill(Color(nsColor: NSColor(pindropHex: "#201D18") ?? .black))
        )
        .clipShape(RoundedRectangle(cornerRadius: ToastMetrics.cornerRadius, style: .continuous))
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        updateLockedWidth(to: geometry.size.width)
                    }
                    .onChange(of: geometry.size.width, initial: false) { _, newWidth in
                        updateLockedWidth(to: newWidth)
                    }
            }
        }
        .shadow(
            color: Color.black.opacity(0.4),
            radius: 14,
            x: 0,
            y: 4
        )
        .onHover { hovering in
            guard isHovering != hovering else { return }
            wrapRevealTask?.cancel()

            if hovering {
                isHovering = true
                setExpandedLayout(true)
                DispatchQueue.main.async {
                    onHoverChange(true)
                }

                wrapRevealTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(ToastMetrics.showDuration * 1_000_000_000))
                    guard !Task.isCancelled, isHovering else { return }
                    setWrappedText(true)
                }
                return
            }

            isHovering = false
            setWrappedText(false)
            setExpandedLayout(false)
            onHoverChange(false)
        }
    }

    private func messageText(wrapped: Bool) -> some View {
        Text(payload.message)
            .font(FontLoader.font(family: .inter, size: 13, weight: .medium))
            .foregroundStyle(Color(nsColor: NSColor(pindropHex: "#EFEBE2") ?? .white))
            .lineLimit(wrapped ? nil : 1)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: wrapped)
    }

    private var leadingColor: Color {
        switch payload.variant {
        case .microphoneUnavailable:
            return Color(nsColor: NSColor(pindropHex: "#D25B4C") ?? .systemRed)
        case .standard where payload.style == .error:
            return Color(nsColor: NSColor(pindropHex: "#D25B4C") ?? .systemRed)
        default:
            return Color(nsColor: NSColor(pindropHex: "#4CA582") ?? .systemGreen)
        }
    }

    private func setWrappedText(_ wrapped: Bool) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            showsWrappedText = wrapped
        }
    }

    private func setExpandedLayout(_ expanded: Bool) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            usesExpandedLayout = expanded
        }
    }

    private func updateLockedWidth(to width: CGFloat) {
        guard !usesExpandedLayout, !showsWrappedText else { return }
        guard width > 0 else { return }
        lockedWidth = min(width, ToastMetrics.maxWidth)
    }
}

private struct ToastTimerBorderView: View {
    @Environment(\.displayScale) private var displayScale

    private struct TimerState {
        let duration: TimeInterval
        let startDate: Date
        var pausedAt: Date?
        var accumulatedPauseDuration: TimeInterval = 0

        mutating func pause(at date: Date) {
            guard pausedAt == nil else { return }
            pausedAt = date
        }

        mutating func resume(at date: Date) {
            guard let pausedAt else { return }
            accumulatedPauseDuration += date.timeIntervalSince(pausedAt)
            self.pausedAt = nil
        }

        func progress(at date: Date) -> Double {
            guard duration > 0 else { return 0 }
            let currentDate = pausedAt ?? date
            let elapsed = max(0, currentDate.timeIntervalSince(startDate) - accumulatedPauseDuration)
            return max(0, min(1, 1 - (elapsed / duration)))
        }
    }

    let toastID: UUID
    let duration: TimeInterval?
    let style: ToastStyle
    let isPaused: Bool
    let cornerRadius: CGFloat

    @State private var timerState: TimerState?

    private var hairlineWidth: CGFloat {
        1 / max(displayScale, 1)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AppColors.border, lineWidth: hairlineWidth)

            if hasTimer {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isPaused)) { context in
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .trim(from: 0, to: timerState?.progress(at: context.date) ?? 1)
                        .stroke(
                            timerColor,
                            style: StrokeStyle(lineWidth: hairlineWidth, lineCap: .round, lineJoin: .round)
                        )
                }
            }
        }
        .onAppear {
            resetTimer()
        }
        .onChange(of: toastID, initial: false) { _, _ in
            resetTimer()
        }
        .onChange(of: isPaused, initial: false) { _, paused in
            updatePauseState(paused)
        }
    }

    private var hasTimer: Bool {
        guard let duration else { return false }
        return duration > 0
    }

    private var timerColor: Color {
        switch style {
        case .standard:
            return AppColors.accent
        case .error:
            return AppColors.error
        }
    }

    private func resetTimer() {
        guard let duration, duration > 0 else {
            timerState = nil
            return
        }

        var state = TimerState(duration: duration, startDate: Date())
        if isPaused {
            state.pause(at: Date())
        }
        timerState = state
    }

    private func updatePauseState(_ paused: Bool) {
        guard var timerState else { return }
        if paused {
            timerState.pause(at: Date())
        } else {
            timerState.resume(at: Date())
        }
        self.timerState = timerState
    }
}

private struct ToastActionButtonStyle: ButtonStyle {
    let role: ToastActionRole

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FontLoader.font(family: .inter, size: 12, weight: .semibold))
            .foregroundStyle(foregroundColor(isPressed: configuration.isPressed))
            .animation(AppTheme.Animation.fast, value: configuration.isPressed)
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        switch role {
        case .primary:
            return Color(nsColor: NSColor(pindropHex: "#4CA582") ?? .systemGreen)
                .opacity(isPressed ? 0.7 : 1)
        case .secondary:
            return Color(nsColor: NSColor(pindropHex: "#A59D8C") ?? .secondaryLabelColor)
                .opacity(isPressed ? 0.7 : 1)
        }
    }
}
