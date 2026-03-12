//
//  ToastWindowController.swift
//  Pindrop
//
//  Created on 2026-03-11.
//

import AppKit
import SwiftUI

private enum ToastMetrics {
    static let horizontalPadding: CGFloat = AppTheme.Spacing.lg
    static let verticalPadding: CGFloat = AppTheme.Spacing.md
    static let buttonSpacing: CGFloat = AppTheme.Spacing.sm
    static let toastSpacing: CGFloat = AppTheme.Spacing.md
    static let screenInset: CGFloat = 28
    static let bottomInset: CGFloat = 42
    static let maxWidth: CGFloat = 520
    static let minWidth: CGFloat = 180
    static let showDuration: TimeInterval = 0.18
    static let hideDuration: TimeInterval = 0.14
}

private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ToastWindowController: ToastPresenting {
    private var panel: ToastPanel?
    private var hostingView: NSHostingView<ToastView>?

    func show(payload: ToastPayload, onAction: @escaping (UUID) -> Void) {
        let rootView = ToastView(payload: payload, onAction: onAction)
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
        let frame = frameForToast(size: size, hintRect: payload.screenHintRect)

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

    private func frameForToast(size: CGSize, hintRect: CGRect?) -> NSRect {
        let screen = screen(for: hintRect) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let clampedWidth = min(size.width, max(ToastMetrics.minWidth, visibleFrame.width - (ToastMetrics.screenInset * 2)))
        let origin = CGPoint(
            x: visibleFrame.midX - (clampedWidth / 2),
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
}

private struct ToastView: View {
    let payload: ToastPayload
    let onAction: (UUID) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: ToastMetrics.toastSpacing) {
            Text(payload.message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

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
        .frame(maxWidth: ToastMetrics.maxWidth)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.full, style: .continuous)
                .fill(AppColors.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.full, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(0.16),
            radius: AppTheme.Shadow.lg.radius,
            x: AppTheme.Shadow.lg.x,
            y: AppTheme.Shadow.lg.y
        )
        .padding(.horizontal, ToastMetrics.screenInset)
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}

private struct ToastActionButtonStyle: ButtonStyle {
    let role: ToastActionRole

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.caption)
            .foregroundStyle(foregroundColor(isPressed: configuration.isPressed))
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(Capsule())
            .animation(AppTheme.Animation.fast, value: configuration.isPressed)
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        switch role {
        case .primary:
            return .white.opacity(isPressed ? 0.9 : 1.0)
        case .secondary:
            return AppColors.textSecondary.opacity(isPressed ? 0.7 : 1.0)
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch role {
        case .primary:
            return AppColors.accent.opacity(isPressed ? 0.75 : 1.0)
        case .secondary:
            return AppColors.surfaceBackground.opacity(isPressed ? 0.8 : 1.0)
        }
    }
}
