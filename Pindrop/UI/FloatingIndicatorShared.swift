//
//  FloatingIndicatorShared.swift
//  Pindrop
//
//  Created on 2026-03-06.
//

import Foundation
import SwiftUI
import AppKit

extension NSScreen {
    static func screenUnderMouse() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main ?? NSScreen.screens.first!
    }
}

enum FloatingIndicatorWaveformBarLayout {
    case fixed(count: Int, heightScale: [CGFloat]? = nil)
    case dynamic(minimumCount: Int, edgeAttenuation: CGFloat)
}

struct FloatingIndicatorWaveformStyle {
    let layout: FloatingIndicatorWaveformBarLayout
    let barWidth: CGFloat
    let barSpacing: CGFloat
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat
    let idleHeight: CGFloat
    let color: Color
    let animationInterval: TimeInterval

    static let notch = FloatingIndicatorWaveformStyle(
        layout: .dynamic(minimumCount: 14, edgeAttenuation: 0.45),
        barWidth: 2,
        barSpacing: 1.6,
        minimumHeight: 2,
        maximumHeight: 16,
        idleHeight: 2,
        color: AppColors.overlayWaveform,
        animationInterval: 0.05
    )

    static let pill = FloatingIndicatorWaveformStyle(
        layout: .fixed(count: 5, heightScale: [0.55, 0.78, 1.0, 0.78, 0.55]),
        barWidth: 2,
        barSpacing: 2,
        minimumHeight: 3,
        maximumHeight: 14,
        idleHeight: 3,
        color: AppColors.overlayTextPrimary,
        animationInterval: 0.05
    )

    static let bubble = FloatingIndicatorWaveformStyle(
        layout: .fixed(count: 5, heightScale: [0.55, 0.78, 1.0, 0.78, 0.55]),
        barWidth: 3,
        barSpacing: 2,
        minimumHeight: 3,
        maximumHeight: 14,
        idleHeight: 3,
        color: AppColors.overlayWaveform,
        animationInterval: 0.05
    )
}

struct FloatingIndicatorWaveformView: View {
    let audioLevel: Float
    let isRecording: Bool
    let style: FloatingIndicatorWaveformStyle

    var body: some View {
        switch style.layout {
        case .fixed(let count, let heightScale):
            TimelineView(.animation(minimumInterval: style.animationInterval)) { timeline in
                HStack(spacing: style.barSpacing) {
                    ForEach(0..<count, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(style.color.opacity(isRecording ? 1 : 0.58))
                            .frame(
                                width: style.barWidth,
                                height: barHeight(
                                    for: index,
                                    barCount: count,
                                    date: timeline.date,
                                    heightScale: heightScale
                                )
                            )
                    }
                }
            }

        case .dynamic(let minimumCount, _):
            GeometryReader { proxy in
                TimelineView(.animation(minimumInterval: style.animationInterval)) { timeline in
                    let barCount = max(
                        minimumCount,
                        Int((proxy.size.width + style.barSpacing) / (style.barWidth + style.barSpacing))
                    )

                    HStack(spacing: style.barSpacing) {
                        ForEach(0..<barCount, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(style.color.opacity(isRecording ? 1 : 0.58))
                                .frame(
                                    width: style.barWidth,
                                    height: barHeight(for: index, barCount: barCount, date: timeline.date)
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func barHeight(for index: Int, barCount: Int, date: Date, heightScale: [CGFloat]? = nil) -> CGFloat {
        guard isRecording else { return style.idleHeight }

        let time = date.timeIntervalSinceReferenceDate
        let phase = Double(index) * 0.85

        let waveA = sin(time * 6.8 + phase) * 0.55
        let waveB = sin(time * 4.1 + phase * 1.7) * 0.35
        let combinedWave = (waveA + waveB + 1.9) / 2.8

        let amplifiedLevel = min(1.0, max(0.0, CGFloat(audioLevel) * 5.0))
        let level = 0.12 + (amplifiedLevel * 0.88)
        var height = (4 + combinedWave * 10) * level

        if case .dynamic(_, let edgeAttenuation) = style.layout {
            let midpoint = Double(max(1, barCount - 1)) / 2
            let distance = abs(Double(index) - midpoint) / max(1, midpoint)
            height *= CGFloat(1 - (distance * edgeAttenuation))
        }

        if let heightScale, index < heightScale.count {
            height *= heightScale[index]
        }

        return max(style.minimumHeight, min(style.maximumHeight, height))
    }
}

struct FloatingIndicatorActions {
    var onStartRecording: ((FloatingIndicatorType) -> Void)?
    var onStopRecording: ((FloatingIndicatorType) -> Void)?
    var onCancelRecording: (() -> Void)?
    var onHideForOneHour: (() -> Void)?
    var onReportIssue: (() -> Void)?
    var onGoToSettings: (() -> Void)?
    var onViewTranscriptHistory: (() -> Void)?
    var onPasteLastTranscript: (() async -> Void)?
    var onSelectInputDeviceUID: ((String) -> Void)?
    var onSelectLanguage: ((AppLanguage) -> Void)?
    var availableInputDevicesProvider: (() -> [(uid: String, displayName: String)])?
    var selectedInputDeviceUIDProvider: (() -> String)?
    var selectedLanguageProvider: (() -> AppLanguage)?
    var anchorProvider: (() -> CGRect?)?
}

@MainActor
protocol FloatingIndicatorPresenting: AnyObject {
    var type: FloatingIndicatorType { get }
    var state: FloatingIndicatorState { get }

    func configure(actions: FloatingIndicatorActions)
    func showIdleIndicator()
    func showForCurrentState()
    func hide()
    func startRecording()
    func transitionToProcessing()
    func finishProcessing()
}

@MainActor
final class FloatingIndicatorState: ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    @Published var isProcessing = false
    @Published var escapePrimed = false
    @Published var toggleRecordingHotkey = ""
    @Published var pushToTalkHotkey = ""

    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var escapePrimedResetTask: Task<Void, Never>?

    func startRecording() {
        isRecording = true
        isProcessing = false
        recordingStartTime = Date()
        recordingDuration = 0
        startDurationTimer()
    }

    func transitionToProcessing() {
        isRecording = false
        isProcessing = true
        stopDurationTimer()
    }

    func finishSession() {
        isRecording = false
        isProcessing = false
        recordingDuration = 0
        audioLevel = 0
        clearEscapePrimed()
        stopDurationTimer()
    }

    func updateAudioLevel(_ level: Float) {
        let smoothed = audioLevel * 0.3 + level * 0.7
        audioLevel = min(1.0, max(0.0, smoothed))
    }

    func updateHotkeys(toggleHotkey: String, pushToTalkHotkey: String) {
        self.toggleRecordingHotkey = normalize(hotkey: toggleHotkey)
        self.pushToTalkHotkey = normalize(hotkey: pushToTalkHotkey)
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

    private func normalize(hotkey: String) -> String {
        hotkey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startDurationTimer() {
        stopDurationTimer()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}
