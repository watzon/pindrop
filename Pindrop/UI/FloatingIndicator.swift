//
//  FloatingIndicator.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI
import AppKit
import Combine

/// Floating indicator window that displays recording status
@MainActor
final class FloatingIndicatorController: ObservableObject {
    
    // MARK: - Properties
    
    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingIndicatorView>?
    
    // MARK: - State
    
    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    
    // MARK: - Initialization
    
    init() {
    }
    
    // MARK: - Public Methods
    
    func show() {
        guard panel == nil else { return }
        
        // Create the SwiftUI view
        let contentView = FloatingIndicatorView(controller: self)
        
        // Wrap in hosting view
        let hostingView = NSHostingView(rootView: contentView)
        self.hostingView = hostingView
        
        // Load saved position or use default
        let savedPosition = loadSavedPosition()
        
        // Create panel
        let panel = NSPanel(
            contentRect: NSRect(x: savedPosition.x, y: savedPosition.y, width: 200, height: 80),
            styleMask: [.nonactivatingPanel, .titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        
        // Configure panel
        panel.contentView = hostingView
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.title = "Recording"
        panel.titlebarAppearsTransparent = true
        panel.styleMask.insert(.fullSizeContentView)
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        
        // Save position when moved
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.savePosition()
            }
        }
        
        self.panel = panel
        panel.orderFrontRegardless()
    }
    
    func hide() {
        panel?.close()
        panel = nil
        hostingView = nil
    }
    
    func updateRecordingState(isRecording: Bool, duration: TimeInterval = 0) {
        self.isRecording = isRecording
        self.recordingDuration = duration
    }
    
    func updateAudioLevel(_ level: Float) {
        self.audioLevel = level
    }
    
    // MARK: - Position Persistence
    
    private func loadSavedPosition() -> NSPoint {
        let x = UserDefaults.standard.double(forKey: "floatingIndicatorX")
        let y = UserDefaults.standard.double(forKey: "floatingIndicatorY")
        
        // Use default position if no saved position
        if x == 0 && y == 0 {
            // Position in top-right corner of main screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                return NSPoint(
                    x: screenFrame.maxX - 220,
                    y: screenFrame.maxY - 100
                )
            }
        }
        
        return NSPoint(x: x, y: y)
    }
    
    private func savePosition() {
        guard let panel = panel else { return }
        let origin = panel.frame.origin
        UserDefaults.standard.set(origin.x, forKey: "floatingIndicatorX")
        UserDefaults.standard.set(origin.y, forKey: "floatingIndicatorY")
    }
}

// MARK: - SwiftUI View

struct FloatingIndicatorView: View {
    
    @ObservedObject var controller: FloatingIndicatorController
    
    var body: some View {
        VStack(spacing: 8) {
            // Recording status
            HStack(spacing: 8) {
                Circle()
                    .fill(controller.isRecording ? Color.red : Color.gray)
                    .frame(width: 12, height: 12)
                    .opacity(controller.isRecording ? 1.0 : 0.5)
                
                Text(controller.isRecording ? "Recording" : "Idle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            // Duration timer
            HStack {
                Image(systemName: "timer")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Text(formatDuration(controller.recordingDuration))
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            // Waveform visualization
            WaveformView(audioLevel: controller.audioLevel, isRecording: controller.isRecording)
                .frame(height: 24)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .padding(8)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Waveform Visualization

struct WaveformView: View {
    
    let audioLevel: Float
    let isRecording: Bool
    
    private let barCount = 20
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: index))
                        .frame(width: barWidth(geometry: geometry))
                        .frame(height: barHeight(for: index, geometry: geometry))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func barWidth(geometry: GeometryProxy) -> CGFloat {
        let totalSpacing = CGFloat(barCount - 1) * 2
        return (geometry.size.width - totalSpacing) / CGFloat(barCount)
    }
    
    private func barHeight(for index: Int, geometry: GeometryProxy) -> CGFloat {
        guard isRecording else {
            return 2 // Minimal height when not recording
        }
        
        // Create wave pattern based on audio level
        let normalizedIndex = CGFloat(index) / CGFloat(barCount)
        let wave = sin(normalizedIndex * .pi * 2 + CGFloat(audioLevel) * 10)
        let levelMultiplier = CGFloat(audioLevel) * 0.8 + 0.2 // Min 20% height
        let height = (abs(wave) * levelMultiplier * geometry.size.height)
        
        return max(2, height)
    }
    
    private func barColor(for index: Int) -> Color {
        guard isRecording else {
            return Color.gray.opacity(0.3)
        }
        
        // Gradient from blue to green based on position
        let normalizedIndex = Double(index) / Double(barCount)
        return Color(
            red: 0.2 + normalizedIndex * 0.3,
            green: 0.5 + normalizedIndex * 0.3,
            blue: 0.8 - normalizedIndex * 0.3
        )
    }
}

// MARK: - Preview

#Preview {
    let controller = FloatingIndicatorController()
    controller.isRecording = true
    controller.recordingDuration = 125.5
    controller.audioLevel = 0.6
    
    return FloatingIndicatorView(controller: controller)
        .frame(width: 200, height: 80)
}
