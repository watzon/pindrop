//
//  FloatingIndicator.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI
import AppKit
import Combine

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
final class FloatingIndicatorController: ObservableObject {
    
    private var panel: NotchPanel?
    private var hostingView: NSHostingView<NotchIndicatorView>?
    
    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    @Published var isProcessing: Bool = false
    @Published var escapePrimed: Bool = false
    
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var escapePrimedResetTask: Task<Void, Never>?
    
    var onStopRecording: (() -> Void)?
    
    init() {}
    
    func show() {
        guard panel == nil else {
            panel?.orderFrontRegardless()
            return
        }
        
        guard let screen = NSScreen.main else { return }
        
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
            controller: self,
            notchWidth: notchWidth,
            sideWidth: sideWidth,
            height: panelHeight
        )
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        self.hostingView = hostingView
        
        panel.contentView = hostingView
        self.panel = panel
        
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        
        let localPanel = panel
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NotchPanelMetrics.showHideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            localPanel.animator().alphaValue = 1
        }
    }
    
    func hide() {
        guard let panel = panel else { return }
        let localPanel = panel
        
        stopDurationTimer()
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NotchPanelMetrics.hideDuration
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
    
    func startRecording() {
        isRecording = true
        isProcessing = false
        recordingStartTime = Date()
        recordingDuration = 0
        startDurationTimer()
        show()
    }
    
    func stopRecording() {
        isRecording = false
        isProcessing = true
        stopDurationTimer()
    }
    
    func finishProcessing() {
        isProcessing = false
        hide()
    }
    
    func updateAudioLevel(_ level: Float) {
        let smoothed = audioLevel * 0.3 + level * 0.7
        audioLevel = min(1.0, max(0.0, smoothed))
    }
    
    func showEscapePrimed() {
        escapePrimedResetTask?.cancel()
        escapePrimed = true
        
        escapePrimedResetTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled {
                escapePrimed = false
            }
        }
    }
    
    func clearEscapePrimed() {
        escapePrimedResetTask?.cancel()
        escapePrimed = false
    }
    
    func handleStopButtonTapped() {
        onStopRecording?()
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

struct NotchIndicatorView: View {
    @ObservedObject var controller: FloatingIndicatorController
    let notchWidth: CGFloat
    let sideWidth: CGFloat
    let height: CGFloat
    
    private var formattedDuration: String {
        let minutes = Int(controller.recordingDuration) / 60
        let seconds = Int(controller.recordingDuration) % 60
        let tenths = Int((controller.recordingDuration.truncatingRemainder(dividingBy: 1)) * 10)
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
        .background(Color.black)
        .clipShape(NotchShape(cornerRadius: NotchPanelMetrics.cornerRadius))
    }
    
    private var leftSide: some View {
        HStack(spacing: 8) {
            if controller.isRecording {
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
            Color.black.opacity(0.55)

            if controller.isProcessing {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white.opacity(0.9))
            }
        }
        .frame(width: notchWidth, height: height)
    }

    private var rightSide: some View {
        NotchWaveformView(
            audioLevel: controller.audioLevel,
            isRecording: controller.isRecording
        )
        .frame(maxWidth: .infinity, maxHeight: 18, alignment: .leading)
        .padding(.leading, 10)
        .padding(.trailing, NotchPanelMetrics.sidePadding)
        .frame(width: sideWidth, height: height)
    }
    
    private var stopButton: some View {
        Button {
            controller.handleStopButtonTapped()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 18, height: 18)
                    .shadow(color: Color.red.opacity(0.28), radius: 4)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
            }
        }
        .buttonStyle(.plain)
        .overlay(pulsingRing)
    }
    
    private var pulsingRing: some View {
        Circle()
            .stroke(Color.red.opacity(0.5), lineWidth: 1.6)
            .frame(width: 18, height: 18)
            .scaleEffect(controller.isRecording ? 1.4 : 1)
            .opacity(controller.isRecording ? 0 : 0.2)
            .animation(
                controller.isRecording
                    ? .easeOut(duration: 1.1).repeatForever(autoreverses: false)
                    : .easeInOut(duration: 0.2),
                value: controller.isRecording
            )
    }
    
    private var processingIndicator: some View {
        ZStack {
            Circle()
                .fill(Color.orange)
                .frame(width: 20, height: 20)
            
            ProgressView()
                .scaleEffect(0.45)
                .tint(.white)
        }
    }
    
    private var timerDisplay: some View {
        HStack(spacing: 6) {
            Text(controller.isProcessing ? "..." : formattedDuration)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            
            if controller.escapePrimed {
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 6, height: 6)
                    .transition(.scale.combined(with: .opacity))
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.15), value: controller.escapePrimed)
    }
}

struct NotchWaveformView: View {
    let audioLevel: Float
    let isRecording: Bool
    
    private let barWidth: CGFloat = 2
    private let barSpacing: CGFloat = 1.6
    private let minimumBarCount = 14
    
    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 0.05)) { timeline in
                let barCount = max(
                    minimumBarCount,
                    Int((proxy.size.width + barSpacing) / (barWidth + barSpacing))
                )

                HStack(spacing: barSpacing) {
                    ForEach(0..<barCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(barColor)
                            .frame(
                                width: barWidth,
                                height: barHeight(for: index, barCount: barCount, date: timeline.date)
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }
    
    private var barColor: Color {
        Color(red: 0.4, green: 0.85, blue: 1.0)
    }
    
    private func barHeight(for index: Int, barCount: Int, date: Date) -> CGFloat {
        guard isRecording else { return 2 }
        
        let time = date.timeIntervalSinceReferenceDate
        let phase = Double(index) * 0.35
        
        let waveA = sin(time * 6.8 + phase) * 0.55
        let waveB = sin(time * 4.1 + phase * 1.7) * 0.35
        let combinedWave = (waveA + waveB + 1.9) / 2.8

        let amplifiedLevel = min(1.0, max(0.0, CGFloat(audioLevel) * 5.0))
        let level = 0.12 + (amplifiedLevel * 0.88)
        let baseHeight = (4 + combinedWave * 10) * level

        let midpoint = Double(max(1, barCount - 1)) / 2
        let distance = abs(Double(index) - midpoint) / max(1, midpoint)
        let edgeAttenuation = CGFloat(1 - (distance * 0.45))

        let height = baseHeight * edgeAttenuation
        return max(2, min(16, height))
    }
}

#Preview("Notch Indicator - Recording") {
    let controller = FloatingIndicatorController()
    controller.isRecording = true
    controller.recordingDuration = 5.3
    controller.audioLevel = 0.6
    
    return NotchIndicatorView(controller: controller, notchWidth: 185, sideWidth: 100, height: 38)
        .frame(width: 385, height: 38)
        .background(Color.gray.opacity(0.3))
}

#Preview("Notch Indicator - Processing") {
    let controller = FloatingIndicatorController()
    controller.isRecording = false
    controller.isProcessing = true
    controller.recordingDuration = 12.7
    controller.audioLevel = 0.0
    
    return NotchIndicatorView(controller: controller, notchWidth: 185, sideWidth: 100, height: 38)
        .frame(width: 385, height: 38)
        .background(Color.gray.opacity(0.3))
}
