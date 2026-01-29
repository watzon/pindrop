//
//  PillFloatingIndicator.swift
//  Pindrop
//
//  Created on 2026-01-29.
//

import SwiftUI
import AppKit
import Combine

@MainActor
final class PillFloatingIndicatorController: ObservableObject {

    private var panel: NSPanel?
    private var hostingView: NSHostingView<PillIndicatorView>?

    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    @Published var isProcessing: Bool = false
    @Published var isHovered: Bool = false

    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var screenTrackingTimer: Timer?
    private var lastScreen: NSScreen?

    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onCancelRecording: (() -> Void)?

    private var isVisible: Bool = false

    init() {}
    
    func showTab() {
        guard !isVisible else { return }

        guard let screen = NSScreen.main else { return }

        let compactSize = CGSize(width: 32, height: 8)
        let screenFrame = screen.visibleFrame

        let xPosition = screenFrame.midX - (compactSize.width / 2)
        let yPosition = screenFrame.minY + 4

        let contentRect = NSRect(x: xPosition, y: yPosition, width: compactSize.width, height: compactSize.height)
        let panel = createPanel(contentRect: contentRect)

        let contentView = PillIndicatorView(
            controller: self,
            isCompact: true
        )
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.layer?.backgroundColor = .clear
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

    private func checkAndUpdateScreenPosition() {
        guard isVisible, !isRecording, !isProcessing else { return }
        guard let currentScreen = NSScreen.main, let panel = panel else { return }

        if lastScreen !== currentScreen {
            lastScreen = currentScreen
            let screenFrame = currentScreen.visibleFrame

            let size = isHovered ? CGSize(width: 36, height: 10) : CGSize(width: 32, height: 8)
            let xPosition = screenFrame.midX - (size.width / 2)
            let yPosition = screenFrame.minY + 4

            let newFrame = NSRect(x: xPosition, y: yPosition, width: size.width, height: size.height)
            panel.setFrame(newFrame, display: true, animate: false)
        }
    }

    func setHoverState(_ hovering: Bool) {
        guard isVisible, !isRecording, !isProcessing else { return }

        isHovered = hovering

        guard let panel = panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        let baseWidth: CGFloat = 32
        let baseHeight: CGFloat = 8
        let hoverWidth: CGFloat = 36
        let hoverHeight: CGFloat = 10

        let width = hovering ? hoverWidth : baseWidth
        let height = hovering ? hoverHeight : baseHeight

        let xPosition = screenFrame.midX - (width / 2)
        let yPosition = screenFrame.minY + 4

        let newFrame = NSRect(x: xPosition, y: yPosition, width: width, height: height)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }
    }
    
    func expandForRecording() {
        isRecording = true
        isProcessing = false
        recordingStartTime = Date()
        recordingDuration = 0
        startDurationTimer()

        guard let panel = panel else {
            showExpanded()
            return
        }

        guard let screen = NSScreen.main else { return }
        let expandedSize = CGSize(width: 120, height: 22)
        let screenFrame = screen.visibleFrame

        let newX = screenFrame.midX - (expandedSize.width / 2)
        let newY = screenFrame.minY + 8

        let newFrame = NSRect(x: newX, y: newY, width: expandedSize.width, height: expandedSize.height)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }

        updateContentView(isCompact: false)
    }
    
    private func showExpanded() {
        guard let screen = NSScreen.main else { return }

        let expandedSize = CGSize(width: 120, height: 22)
        let screenFrame = screen.visibleFrame

        let xPosition = screenFrame.midX - (expandedSize.width / 2)
        let yPosition = screenFrame.minY + 8

        let contentRect = NSRect(x: xPosition, y: yPosition, width: expandedSize.width, height: expandedSize.height)
        let panel = createPanel(contentRect: contentRect)
        
        let contentView = PillIndicatorView(
            controller: self,
            isCompact: false
        )
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.layer?.backgroundColor = .clear
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
    }
    
    func stopRecording() {
        isRecording = false
        isProcessing = true
        stopDurationTimer()
    }
    
    func finishProcessing() {
        isProcessing = false

        guard let panel = panel else { return }
        guard let screen = NSScreen.main else { return }

        let compactSize = CGSize(width: 32, height: 8)
        let screenFrame = screen.visibleFrame

        let newX = screenFrame.midX - (compactSize.width / 2)
        let newY = screenFrame.minY + 4

        let newFrame = NSRect(x: newX, y: newY, width: compactSize.width, height: compactSize.height)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        } completionHandler: { [weak self] in
            self?.updateContentView(isCompact: true)
        }
    }

    
    func hide() {
        guard let panel = panel else { return }
        let localPanel = panel

        stopDurationTimer()
        stopScreenTracking()
        isVisible = false

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            localPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            localPanel.close()
            self?.panel = nil
            self?.hostingView = nil
        })
    }
    
    func updateAudioLevel(_ level: Float) {
        let smoothed = audioLevel * 0.3 + level * 0.7
        audioLevel = min(1.0, max(0.0, smoothed))
    }
    
    func handleStopButtonTapped() {
        onStopRecording?()
    }
    
    func handleCancelButtonTapped() {
        onCancelRecording?()
    }

    func handleCompactTapped() {
        onStartRecording?()
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
        panel.hasShadow = true
        
        return panel
    }
    
    private func updateContentView(isCompact: Bool) {
        guard let panel = panel else { return }
        
        let contentView = PillIndicatorView(
            controller: self,
            isCompact: isCompact
        )
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.layer?.backgroundColor = .clear
        
        panel.contentView = hostingView
        self.hostingView = hostingView
    }
    
    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}

struct PillIndicatorView: View {
    @ObservedObject var controller: PillFloatingIndicatorController
    let isCompact: Bool

    private var formattedDuration: String {
        let minutes = Int(controller.recordingDuration) / 60
        let seconds = Int(controller.recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        if isCompact {
            compactView
        } else {
            expandedView
        }
    }

    private var compactView: some View {
        Button {
            controller.handleCompactTapped()
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            controller.setHoverState(hovering)
        }
    }

    private var expandedView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )

            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    if controller.isRecording {
                        Button {
                            controller.handleStopButtonTapped()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 12, height: 12)

                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.white)
                                    .frame(width: 4, height: 4)
                            }
                        }
                        .buttonStyle(.plain)
                    } else if controller.isProcessing {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 12, height: 12)
                    }
                }
                .frame(width: 24)

                PillWaveformView(
                    audioLevel: controller.audioLevel,
                    isRecording: controller.isRecording
                )
                .frame(width: 44, height: 12)

                Button {
                    controller.handleCancelButtonTapped()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
        }
        .frame(width: 120, height: 22)
    }
}

struct PillWaveformView: View {
    let audioLevel: Float
    let isRecording: Bool

    private let barCount = 4
    private let barWidth: CGFloat = 2
    private let barSpacing: CGFloat = 2

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.9))
                        .frame(width: barWidth, height: barHeight(for: index, date: timeline.date))
                }
            }
        }
    }

    private func barHeight(for index: Int, date: Date) -> CGFloat {
        guard isRecording else { return 2 }

        let time = date.timeIntervalSinceReferenceDate
        let normalizedIndex = Double(index) / Double(barCount - 1)

        let wave1 = sin(time * 4 + normalizedIndex * .pi * 2) * 0.3
        let wave2 = sin(time * 6 + normalizedIndex * .pi * 1.5) * 0.2
        let wave3 = sin(time * 10 + normalizedIndex * .pi) * 0.1

        let combinedWave = (wave1 + wave2 + wave3 + 0.6) / 1.2
        let levelInfluence = Double(audioLevel) * 0.7 + 0.3

        let height = combinedWave * levelInfluence * 10
        return max(2, min(10, height))
    }
}

#Preview("Pill Compact") {
    let controller = PillFloatingIndicatorController()
    return PillIndicatorView(controller: controller, isCompact: true)
        .frame(width: 36, height: 10)
}

#Preview("Pill Expanded - Recording") {
    let controller = PillFloatingIndicatorController()
    controller.isRecording = true
    controller.audioLevel = 0.7
    return PillIndicatorView(controller: controller, isCompact: false)
        .frame(width: 120, height: 22)
}

#Preview("Pill Expanded - Processing") {
    let controller = PillFloatingIndicatorController()
    controller.isRecording = false
    controller.isProcessing = true
    return PillIndicatorView(controller: controller, isCompact: false)
        .frame(width: 120, height: 22)
}
