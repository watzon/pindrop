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
    /// Stable identity for the physical display backing this screen (handles cases where AppKit
    /// may vend different `NSScreen` instances for the same monitor across queries).
    var pindrop_displayNumber: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Whether two screens refer to the same physical display.
    func pindrop_isSameDisplay(as other: NSScreen?) -> Bool {
        guard let other else { return false }
        let a = pindrop_displayNumber
        let b = other.pindrop_displayNumber
        if a != 0, b != 0 {
            return a == b
        }
        return self === other
    }

    /// Resolves the display that currently owns the cursor using global screen coordinates.
    ///
    /// Uses `frame` first (includes menu bar and dock margins outside `visibleFrame`). When multiple
    /// `NSScreen` frames overlap (mirroring, unusual layouts), prefers a screen whose `visibleFrame`
    /// contains the point, then the smallest `frame`. When the point falls in a seam/gap, picks the
    /// screen whose visible rect is closest so the indicator does not stick to `main` by accident.
    static func screenUnderMouse() -> NSScreen {
        let point = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return NSScreen.main!
        }

        let containing = screens.filter { $0.frame.contains(point) }
        if containing.count == 1 {
            return containing[0]
        }
        if containing.count > 1 {
            if let visibleMatch = containing.first(where: { $0.visibleFrame.contains(point) }) {
                return visibleMatch
            }
            return containing.min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })!
        }

        func distanceToRect(_ rect: CGRect) -> CGFloat {
            let dx: CGFloat
            if point.x < rect.minX { dx = rect.minX - point.x }
            else if point.x > rect.maxX { dx = point.x - rect.maxX }
            else { dx = 0 }
            let dy: CGFloat
            if point.y < rect.minY { dy = rect.minY - point.y }
            else if point.y > rect.maxY { dy = point.y - rect.maxY }
            else { dy = 0 }
            return hypot(dx, dy)
        }

        return screens.min(by: { distanceToRect($0.visibleFrame) < distanceToRect($1.visibleFrame) })
            ?? NSScreen.main
            ?? screens[0]
    }
}

extension Timer {
    /// Repeating timer on the main run loop in `.common` modes so it still fires during event tracking
    /// (window drag, resize, menus, scroll tracking) when `.default`-only timers are paused.
    @MainActor
    static func pindrop_scheduleRepeating(interval: TimeInterval, block: @escaping (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true, block: block)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

// MARK: - Shared indicator components

/// Animated three-dot processing indicator using the theme accent color.
/// Drop-in replacement for `ProgressView()` across all floating indicators.
struct IndicatorProcessingView: View {
    var dotCount: Int = 3
    var dotDiameter: CGFloat = 5
    var spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<dotCount, id: \.self) { index in
                _IndicatorProcessingDot(index: index, diameter: dotDiameter)
            }
        }
    }
}

private struct _IndicatorProcessingDot: View {
    let index: Int
    let diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.06, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = (t * 2.2 + Double(index) * 0.45).truncatingRemainder(dividingBy: 3.0)
            let isActive = phase < 1.0
            let staticOpacities = [1.0, 0.55, 0.25]
            Circle()
                .fill(
                    Color(nsColor: NSColor(pindropHex: "#4CA582") ?? .systemGreen)
                        .opacity(reduceMotion ? staticOpacities[index % staticOpacities.count] : (isActive ? 1 : 0.25))
                )
                .frame(width: diameter, height: diameter)
                .scaleEffect(reduceMotion ? 1 : (isActive ? 1.0 : 0.76))
                .animation(reduceMotion ? nil : AppTheme.Animation.fast, value: isActive)
        }
    }
}

/// Brief animated badge shown when a transcription/session completes.
/// Displays the completion kind's icon and title, then fades out automatically
/// when `state.recentCompletion` returns to nil.
struct IndicatorCompletionOverlay: View {
    let completion: FloatingIndicatorState.CompletionKind
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: completion.icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppColors.overlayTooltipAccent)
            Text(completion.title(locale: locale))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.overlayTextPrimary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(AppColors.overlaySurfaceStrong)
                .hairlineStroke(Capsule(), style: AppColors.overlayLine.opacity(0.7))
        )
        .shadow(color: AppColors.shadowColor.opacity(0.32), radius: 8, y: 4)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.88, anchor: .center)),
            removal: .opacity
        ))
    }
}

// MARK: - Live transcript (overlay streaming)

/// Shared live-transcript text area shown inside the floating indicators while overlay
/// streaming is active. Committed text renders in the primary overlay color; the
/// tentative tail is dimmed and italic. The view keeps a fixed height (`lineLimit`
/// lines) and auto-scrolls to the tail — panels never resize with text growth, only on
/// phase transitions.
struct LiveTranscriptView: View {
    @ObservedObject var transcript: LiveTranscriptState
    var fontSize: CGFloat = 11
    var lineLimit: Int = 3

    @Environment(\.locale) private var locale

    private var lineHeight: CGFloat { fontSize + 6 }

    /// Composed display string split back into committed/tentative runs so the two can
    /// be styled differently while joining exactly like the coordinator's display path.
    private var styledTranscript: AttributedString {
        let composed = transcript.displayText
        let committedCore = transcript.committedText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var committedRun = AttributedString()
        var tentativeRun = AttributedString()
        if !committedCore.isEmpty, composed.hasPrefix(committedCore) {
            committedRun = AttributedString(committedCore)
            tentativeRun = AttributedString(String(composed.dropFirst(committedCore.count)))
        } else {
            tentativeRun = AttributedString(composed)
        }

        committedRun.foregroundColor = AppColors.overlayTextPrimary
        committedRun.font = FontLoader.font(family: .newsreader, size: fontSize, weight: .regular)
        tentativeRun.foregroundColor = AppColors.overlayTextPrimary.opacity(0.55)
        tentativeRun.font = FontLoader.font(
            family: .newsreader,
            size: fontSize,
            weight: .regular,
            italic: true
        )
        return committedRun + tentativeRun
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if transcript.displayText.isEmpty {
                            Text(localized("Listening…", locale: locale))
                                .font(FontLoader.font(family: .newsreader, size: fontSize, weight: .regular))
                                .foregroundStyle(AppColors.overlayTextSecondary)
                        } else {
                            Text(styledTranscript)
                                .lineSpacing(max(0, lineHeight - fontSize))
                                .opacity(transcript.phase == .enhancing ? 0.7 : 1.0)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("transcript-tail")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: transcript.committedText) {
                    proxy.scrollTo("transcript-tail", anchor: .bottom)
                }
                .onChange(of: transcript.tentativeText) {
                    proxy.scrollTo("transcript-tail", anchor: .bottom)
                }
            }
            .frame(height: CGFloat(lineLimit) * lineHeight)

            if transcript.phase == .enhancing {
                HStack(spacing: 4) {
                    IndicatorProcessingView(dotCount: 3, dotDiameter: 3.5, spacing: 3)
                    Text(localized("Enhancing…", locale: locale))
                        .font(.system(size: fontSize - 2, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.overlayTextSecondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(AppColors.overlaySurfaceStrong)
                        .hairlineStroke(Capsule(), style: AppColors.overlayLine.opacity(0.7))
                )
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
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

    static let pill = FloatingIndicatorWaveformStyle(
        layout: .fixed(count: 9, heightScale: [0.34, 0.58, 0.82, 1.0, 0.66, 0.92, 0.74, 0.5, 0.34]),
        barWidth: 2.5,
        barSpacing: 2.5,
        minimumHeight: 4,
        maximumHeight: 12,
        idleHeight: 4,
        color: Color(nsColor: NSColor(pindropHex: "#4CA582") ?? .systemGreen),
        animationInterval: 0.05
    )

    static let recording = FloatingIndicatorWaveformStyle(
        layout: .dynamic(minimumCount: 24, edgeAttenuation: 0.35),
        barWidth: 3,
        barSpacing: 2.5,
        minimumHeight: 3,
        maximumHeight: 40,
        idleHeight: 3,
        color: AppColors.recording,
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
                        RoundedRectangle(cornerRadius: style.barWidth / 2)
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
                            RoundedRectangle(cornerRadius: style.barWidth / 2)
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
        let i = Double(index)

        // Per-bar pseudo-random seed for individual character
        let seed = sin(i * 12.9898 + 78.233) * 43758.5453
        let barRand = seed - seed.rounded(.down) // 0..1 fractional hash

        // Multiple wave frequencies with per-bar phase offsets for natural variation
        let phaseA = i * 0.85 + barRand * 3.0
        let phaseB = i * 1.7 + barRand * 1.5
        let phaseC = i * 0.42 + barRand * 5.0

        let waveA = sin(time * 7.2 + phaseA) * 0.40
        let waveB = sin(time * 4.5 + phaseB) * 0.30
        let waveC = sin(time * 11.3 + phaseC) * 0.20  // fast shimmer
        let waveD = sin(time * 2.1 + i * 0.3) * 0.10   // slow drift

        // Combined wave normalized to 0..1 range
        let raw = waveA + waveB + waveC + waveD  // range roughly -1..1
        let combinedWave = (raw + 1.0) / 2.0      // 0..1

        // Per-bar random baseline offset so bars aren't all the same height at rest
        let barOffset = 0.8 + barRand * 0.4  // 0.8..1.2

        // Audio level with stronger amplification
        let amplifiedLevel = min(1.0, max(0.0, CGFloat(audioLevel) * 8.0))
        let level = 0.08 + (amplifiedLevel * 0.92)

        // Height formula: wider range, audio level drives both base and wave amplitude
        let baseHeight: CGFloat = 3.0 * barOffset
        let waveHeight = CGFloat(combinedWave) * style.maximumHeight * 0.85 * barOffset
        var height = baseHeight + waveHeight * level

        if case .dynamic(_, let edgeAttenuation) = style.layout {
            let midpoint = Double(max(1, barCount - 1)) / 2
            let distance = abs(i - midpoint) / max(1, midpoint)
            height *= CGFloat(1 - (distance * edgeAttenuation))
        }

        if let heightScale, index < heightScale.count {
            height *= heightScale[index]
        }

        return max(style.minimumHeight, min(style.maximumHeight, height))
    }
}

enum FloatingIndicatorTimeFormatting {
    static func elapsed(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
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
    var preferredScreenProvider: (() -> NSScreen?)?
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
    enum CompletionKind: Equatable {
        case transcription
        case meeting
        case note
        case mediaTranscription

        func title(locale: Locale) -> String {
            switch self {
            case .transcription: return localized("Transcription saved", locale: locale)
            case .meeting: return localized("Meeting saved", locale: locale)
            case .note: return localized("Note saved", locale: locale)
            case .mediaTranscription: return localized("Media saved", locale: locale)
            }
        }

        var icon: String {
            switch self {
            case .transcription: return "waveform"
            case .meeting: return "person.2.fill"
            case .note: return "note.text"
            case .mediaTranscription: return "headphones"
            }
        }
    }

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    /// Deliberately not `@Published`: the only reader is the Orb's blob canvas,
    /// which polls at 40fps on its own timeline, so publishing bought nothing.
    /// This halves (not eliminates) the per-buffer invalidation traffic —
    /// `audioLevel` above updates at the same cadence and must stay `@Published`
    /// for the Pill indicator's waveform.
    var bandLevels = AudioBandLevels.zero
    @Published var isProcessing = false
    /// Selected input device mute/volume state from `InputMuteMonitor`.
    /// UI (orb/pill) can render a Muted state from this without observing CoreAudio directly.
    @Published var isInputMuted = false
    @Published var escapePrimed = false
    @Published var toggleRecordingHotkey = ""
    @Published var pushToTalkHotkey = ""
    @Published var recentCompletion: CompletionKind?

    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var escapePrimedResetTask: Task<Void, Never>?
    private var completionClearTask: Task<Void, Never>?

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

    func updateBandLevels(_ levels: AudioBandLevels) {
        func smooth(_ old: Float, _ new: Float) -> Float {
            min(1.0, max(0.0, old * 0.3 + new * 0.7))
        }
        bandLevels = AudioBandLevels(
            low: smooth(bandLevels.low, levels.low),
            mid: smooth(bandLevels.mid, levels.mid),
            high: smooth(bandLevels.high, levels.high)
        )
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

    /// Flash a completion badge in any hero/indicator that observes this
    /// state. The badge clears itself after `holdFor` seconds.
    func showCompletion(_ kind: CompletionKind, holdFor seconds: TimeInterval = 2.5) {
        completionClearTask?.cancel()
        recentCompletion = kind
        completionClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.recentCompletion = nil
            }
        }
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
