//
//  FloatingIndicator.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI
import AppKit
import Combine

extension NSScreen {
    var notchSize: CGSize? {
        guard let leftArea = auxiliaryTopLeftArea?.width,
              let rightArea = auxiliaryTopRightArea?.width else {
            return nil
        }
        let width = frame.width - leftArea - rightArea
        let height = safeAreaInsets.top
        return CGSize(width: width, height: height)
    }
    
    var hasNotch: Bool {
        safeAreaInsets.top > 0
    }
    
    var menuBarHeight: CGFloat {
        frame.maxY - visibleFrame.maxY
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
        
        let notchWidth = screen.notchSize?.width ?? 185
        let notchHeight = screen.hasNotch ? screen.safeAreaInsets.top : screen.menuBarHeight
        
        let sideWidth: CGFloat = 100
        let expandedWidth = notchWidth + (sideWidth * 2)
        let panelHeight = notchHeight
        
        let xPosition = screen.frame.origin.x + (screen.frame.width / 2) - (expandedWidth / 2)
        let yPosition = screen.frame.origin.y + screen.frame.height - panelHeight
        
        let contentRect = NSRect(x: xPosition, y: yPosition, width: expandedWidth, height: panelHeight)
        let panel = NotchPanel(contentRect: contentRect)
        
        let contentView = NotchIndicatorView(
            controller: self,
            notchWidth: notchWidth,
            sideWidth: sideWidth,
            height: panelHeight
        )
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.layer?.backgroundColor = .clear
        self.hostingView = hostingView
        
        panel.contentView = hostingView
        self.panel = panel
        
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }
    
    func hide() {
        guard let panel = panel else { return }
        
        stopDurationTimer()
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.close()
            self?.panel = nil
            self?.hostingView = nil
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
    
    private let cornerRadius: CGFloat = 14
    
    private var formattedDuration: String {
        let minutes = Int(controller.recordingDuration) / 60
        let seconds = Int(controller.recordingDuration) % 60
        let tenths = Int((controller.recordingDuration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            leftSide
            
            Color.black
                .frame(width: notchWidth)
            
            rightSide
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(NotchShape(cornerRadius: cornerRadius))
    }
    
    private var leftSide: some View {
        HStack(spacing: 8) {
            if controller.isRecording {
                stopButton
            } else {
                processingIndicator
            }
            
            NotchWaveformView(
                audioLevel: controller.audioLevel,
                isRecording: controller.isRecording
            )
            .frame(maxWidth: .infinity, maxHeight: 18)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(width: sideWidth, height: height)
    }
    
    private var rightSide: some View {
        HStack(spacing: 0) {
            timerDisplay
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(width: sideWidth, height: height)
    }
    
    private var stopButton: some View {
        Button {
            controller.handleStopButtonTapped()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 20, height: 20)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
            }
        }
        .buttonStyle(.plain)
        .overlay(pulsingRing)
    }
    
    private var pulsingRing: some View {
        Circle()
            .stroke(Color.red.opacity(0.6), lineWidth: 2)
            .frame(width: 20, height: 20)
            .scaleEffect(controller.isRecording ? 1.5 : 1)
            .opacity(controller.isRecording ? 0 : 0.6)
            .animation(
                controller.isRecording
                    ? .easeOut(duration: 1.2).repeatForever(autoreverses: false)
                    : .default,
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
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
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
    
    private let barCount = 5
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor)
                        .frame(width: 2, height: barHeight(for: index, date: timeline.date))
                }
            }
        }
    }
    
    private var barColor: Color {
        Color(red: 0.4, green: 0.85, blue: 1.0)
    }
    
    private func barHeight(for index: Int, date: Date) -> CGFloat {
        guard isRecording else { return 2 }
        
        let time = date.timeIntervalSinceReferenceDate
        let normalizedIndex = Double(index) / Double(barCount - 1)
        
        let wave1 = sin(time * 5 + normalizedIndex * .pi * 2) * 0.35
        let wave2 = sin(time * 7 + normalizedIndex * .pi * 1.5) * 0.25
        let wave3 = sin(time * 11 + normalizedIndex * .pi) * 0.15
        
        let combinedWave = (wave1 + wave2 + wave3 + 0.75) / 1.5
        let levelInfluence = Double(audioLevel) * 0.7 + 0.3
        
        let height = combinedWave * levelInfluence * 16
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
