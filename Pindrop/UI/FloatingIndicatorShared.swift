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

// MARK: - Pointer / screen activity (event-driven)

/// Subscribes to shared AppKit mouse-move and screen-parameter notifications for
/// floating indicators. Replaces 60 Hz hover polling: callbacks fire only on real pointer
/// activity or display reconfiguration, already on the main run loop (no
/// `Task { @MainActor }` hop from a timer tick).
@MainActor
final class FloatingIndicatorPointerMonitor {
    private var subscriptionID: UUID?
    private var isPointerActivityEnabled = true
    private let onPointerActivity: @MainActor () -> Void
    private let onScreenParametersChanged: @MainActor () -> Void

    init(
        onPointerActivity: @escaping @MainActor () -> Void,
        onScreenParametersChanged: @escaping @MainActor () -> Void = {}
    ) {
        self.onPointerActivity = onPointerActivity
        self.onScreenParametersChanged = onScreenParametersChanged
    }

    deinit {
        guard let subscriptionID else { return }
        Task { @MainActor in
            FloatingIndicatorPointerMonitorHub.shared.remove(subscriptionID)
        }
    }

    func start() {
        guard subscriptionID == nil else { return }
        subscriptionID = FloatingIndicatorPointerMonitorHub.shared.add(
            pointerActivityEnabled: isPointerActivityEnabled,
            onPointerActivity: onPointerActivity,
            onScreenParametersChanged: onScreenParametersChanged
        )
    }

    /// Keeps display-change delivery alive while suspending hover/mouse work for
    /// recording and processing sessions.
    func setPointerActivityEnabled(_ enabled: Bool) {
        guard isPointerActivityEnabled != enabled else { return }
        isPointerActivityEnabled = enabled
        guard let subscriptionID else { return }
        FloatingIndicatorPointerMonitorHub.shared.setPointerActivityEnabled(enabled, for: subscriptionID)
    }

    func stop() {
        guard let subscriptionID else { return }
        FloatingIndicatorPointerMonitorHub.shared.remove(subscriptionID)
        self.subscriptionID = nil
    }
}

/// Process-wide owner for AppKit monitors. The focus tracker and the visible
/// presenter both consume pointer/display events, but AppKit only needs one local
/// monitor, one global monitor, and one screen observer regardless of subscriber count.
@MainActor
private final class FloatingIndicatorPointerMonitorHub {
    static let shared = FloatingIndicatorPointerMonitorHub()

    private struct Subscription {
        var pointerActivityEnabled: Bool
        let onPointerActivity: @MainActor () -> Void
        let onScreenParametersChanged: @MainActor () -> Void
    }

    private var subscriptions: [UUID: Subscription] = [:]
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var screenObserver: NSObjectProtocol?

    func add(
        pointerActivityEnabled: Bool,
        onPointerActivity: @escaping @MainActor () -> Void,
        onScreenParametersChanged: @escaping @MainActor () -> Void
    ) -> UUID {
        let id = UUID()
        subscriptions[id] = Subscription(
            pointerActivityEnabled: pointerActivityEnabled,
            onPointerActivity: onPointerActivity,
            onScreenParametersChanged: onScreenParametersChanged
        )
        reconcileMonitorOwnership()
        return id
    }

    func setPointerActivityEnabled(_ enabled: Bool, for id: UUID) {
        guard var subscription = subscriptions[id] else { return }
        subscription.pointerActivityEnabled = enabled
        subscriptions[id] = subscription
        reconcileMonitorOwnership()
    }

    func remove(_ id: UUID) {
        subscriptions[id] = nil
        reconcileMonitorOwnership()
    }

    private func reconcileMonitorOwnership() {
        let needsPointerMonitors = subscriptions.values.contains(where: \.pointerActivityEnabled)
        if needsPointerMonitors {
            installPointerMonitorsIfNeeded()
        } else {
            removePointerMonitors()
        }

        if subscriptions.isEmpty {
            removeScreenObserver()
        } else {
            installScreenObserverIfNeeded()
        }
    }

    private func installPointerMonitorsIfNeeded() {
        guard localMonitor == nil, globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged
        ]
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.notifyPointerActivity()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            handler(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }

    private func installScreenObserverIfNeeded() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.notifyScreenParametersChanged()
            }
        }
    }

    private func notifyPointerActivity() {
        for subscription in subscriptions.values where subscription.pointerActivityEnabled {
            subscription.onPointerActivity()
        }
    }

    private func notifyScreenParametersChanged() {
        for subscription in subscriptions.values {
            subscription.onScreenParametersChanged()
        }
    }

    private func removePointerMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func removeScreenObserver() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }
}

// MARK: - Shared indicator components

/// Animated three-dot processing indicator using the theme accent color.
/// Drop-in replacement for `ProgressView()` across all floating indicators.
///
/// Uses a single `TimelineView` for the whole collection so the three dots
/// share one animation cadence (and one Reduce Motion gate) instead of each
/// spawning an independent timeline.
struct IndicatorProcessingView: View {
    var dotCount: Int = 3
    var dotDiameter: CGFloat = 5
    var spacing: CGFloat = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.06, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: spacing) {
                ForEach(0..<dotCount, id: \.self) { index in
                    _IndicatorProcessingDot(
                        index: index,
                        diameter: dotDiameter,
                        time: t,
                        reduceMotion: reduceMotion
                    )
                }
            }
        }
    }
}

private struct _IndicatorProcessingDot: View {
    let index: Int
    let diameter: CGFloat
    let time: TimeInterval
    let reduceMotion: Bool

    var body: some View {
        let phase = (time * 2.2 + Double(index) * 0.45).truncatingRemainder(dividingBy: 3.0)
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


// MARK: - Live transcript (overlay streaming)

/// Shared live-transcript text area shown inside the floating indicators while overlay
/// streaming is active. Committed text renders in the primary overlay color; the
/// tentative tail is dimmed and italic. The view keeps a fixed height (`lineLimit`
/// lines) and auto-scrolls to the tail — panels never resize with text growth, only on
/// phase transitions.
///
/// Rendering is deliberately bounded to `LiveTranscriptState.displayTail` so body
/// evaluation stays proportional to the three-line viewport rather than the full
/// session buffer. Full `displayText` / committed values remain available for
/// accessibility and final output.
struct LiveTranscriptView: View {
    @ObservedObject var transcript: LiveTranscriptState
    var fontSize: CGFloat = 11
    var lineLimit: Int = 3

    @Environment(\.locale) private var locale
    @State private var announcedCommittedLength = 0

    private var lineHeight: CGFloat { fontSize + 6 }

    /// The transcript text follows the dictation locale's direction; the panel
    /// around it stays physical (screen-position driven), so direction is applied
    /// here rather than at the panel root.
    private var textLayoutDirection: LayoutDirection {
        let language = locale.language.languageCode?.identifier ?? "en"
        return Locale.characterDirection(forLanguage: language) == .rightToLeft
            ? .rightToLeft
            : .leftToRight
    }

    /// Style only the bounded viewport tail. Split against the full composed cache
    /// so committed/tentative runs keep their semantics even when older committed
    /// text has scrolled out of the three-line window.
    private var styledTranscriptTail: AttributedString {
        let composed = transcript.displayText
        let tail = transcript.displayTail
        guard !tail.isEmpty else { return AttributedString() }

        let committedCore = transcript.committedText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let committedLengthInComposed: Int
        if !committedCore.isEmpty, composed.hasPrefix(committedCore) {
            committedLengthInComposed = committedCore.count
        } else {
            committedLengthInComposed = 0
        }

        let tailStart = composed.count - tail.count
        let committedInTail: String
        let tentativeInTail: String
        if tailStart >= committedLengthInComposed {
            committedInTail = ""
            tentativeInTail = tail
        } else {
            let committedCharsInTail = min(tail.count, committedLengthInComposed - tailStart)
            let split = tail.index(tail.startIndex, offsetBy: committedCharsInTail)
            committedInTail = String(tail[..<split])
            tentativeInTail = String(tail[split...])
        }

        var committedRun = AttributedString(committedInTail)
        var tentativeRun = AttributedString(tentativeInTail)

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
                            Text(styledTranscriptTail)
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
        .environment(\.layoutDirection, textLayoutDirection)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("Live transcript", locale: locale))
        .accessibilityValue(
            transcript.displayText.isEmpty
                ? localized("Listening…", locale: locale)
                : transcript.displayText
        )
        // AppKit's announcement notification is the macOS live-region equivalent.
        // Announce only committed chunks; tentative token churn would overwhelm VoiceOver.
        .onChange(of: transcript.committedText) { _, committedText in
            announceCommittedTranscript(committedText)
        }
    }

    private func announceCommittedTranscript(_ text: String) {
        // committedText is cumulative — announce only the new suffix, or VoiceOver
        // re-reads the whole transcript on every commit.
        if text.count < announcedCommittedLength {
            announcedCommittedLength = 0
        }
        let delta = String(text.dropFirst(announcedCommittedLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        announcedCommittedLength = text.count
        guard !delta.isEmpty else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: delta,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
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

/// Waveform bars sample the latest meter level on the visual timeline only.
/// The parent indicator root is intentionally *not* invalidated at audio-callback
/// cadence; pass a level provider (or the non-`@Published` state sample) so only
/// this drawing subtree re-renders at `style.animationInterval`.
struct FloatingIndicatorWaveformView: View {
    /// Polled once per visual frame inside `TimelineView` — must not be a snapshot
    /// captured by a parent body that would require root invalidation to refresh.
    let audioLevel: () -> Float
    let isRecording: Bool
    let style: FloatingIndicatorWaveformStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch style.layout {
        case .fixed(let count, let heightScale):
            // Audio level remains reactive through per-tick polling. Reduce Motion only
            // freezes the decorative phase wobble driven by the timeline.
            TimelineView(.animation(minimumInterval: style.animationInterval, paused: reduceMotion)) { timeline in
                let level = audioLevel()
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
                                    audioLevel: level,
                                    heightScale: heightScale
                                )
                            )
                    }
                }
            }

        case .dynamic(let minimumCount, _):
            GeometryReader { proxy in
                TimelineView(.animation(minimumInterval: style.animationInterval, paused: reduceMotion)) { timeline in
                    let level = audioLevel()
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
                                    height: barHeight(
                                        for: index,
                                        barCount: barCount,
                                        date: timeline.date,
                                        audioLevel: level
                                    )
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func barHeight(
        for index: Int,
        barCount: Int,
        date: Date,
        audioLevel: Float,
        heightScale: [CGFloat]? = nil
    ) -> CGFloat {
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

/// Scrolling waveform that renders a short rolling history of *real* meter samples,
/// Voice-Memos style: the newest sample lands at the trailing edge and older samples
/// march left. Unlike `FloatingIndicatorWaveformView` (synthesized sine bars scaled
/// by the level), every bar here is an actual `audioLevel` sample, so the drawing
/// follows speech cadence — silence reads flat, plosives spike.
///
/// Sampling rides the visual timeline: one sample per `sampleInterval` tick, stored
/// in a reference-type ring buffer so appends never invalidate the view tree.
struct FloatingIndicatorScrollingWaveformView: View {
    /// Polled once per timeline tick — same contract as `FloatingIndicatorWaveformView`.
    let audioLevel: () -> Float
    let isRecording: Bool
    var color: Color = AppColors.overlayWaveform
    var barWidth: CGFloat = 2
    var barSpacing: CGFloat = 1.5
    var minimumBarHeight: CGFloat = 2
    /// One bar per sample: at 0.1s the visible window spans ~2.5s of audio and the
    /// scroll reads calm, in line with the other indicators' pacing.
    var sampleInterval: TimeInterval = 0.1
    /// Levels arrive pre-normalized for visualization (`AudioLevelNormalizer`
    /// upstream targets speech peaks ≈ 0.9). Its auto-gain also lifts room noise
    /// toward mid-scale during pauses, so a fixed cut can't separate silence from
    /// quiet speech — this is only the lower bound under the adaptive baseline
    /// (see `barThreshold`).
    var noiseFloor: Float = 0.1

    /// Margin above the rolling-minimum sample under which bars stay flat, so
    /// noise jitter around the baseline doesn't flicker.
    private static let baselineDeadband: Float = 0.04

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Deliberately a plain reference box, not observed state: the timeline already
    /// redraws at sample cadence, and appends must not trigger extra invalidation.
    private final class SampleHistory {
        var samples: [Float] = []
        var lastSampleAt: TimeInterval = 0

        func append(_ level: Float, at time: TimeInterval, capacity: Int) {
            lastSampleAt = time
            samples.append(level)
            let overflow = samples.count - capacity
            if overflow > 0 {
                samples.removeFirst(overflow)
            }
        }
    }

    @State private var history = SampleHistory()

    var body: some View {
        TimelineView(.animation(minimumInterval: sampleInterval, paused: !isRecording || reduceMotion)) { timeline in
            Canvas { context, size in
                let slotWidth = barWidth + barSpacing
                let capacity = max(1, Int((size.width + barSpacing) / slotWidth))

                if isRecording, !reduceMotion {
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    // Guard against extra invalidations (theme, state) double-sampling a tick.
                    if now - history.lastSampleAt >= sampleInterval * 0.5 {
                        history.append(audioLevel(), at: now, capacity: capacity)
                    }
                }

                let samples = history.samples
                let midY = size.height / 2

                // The quietest visible sample is the session's current noise
                // baseline (whatever the upstream auto-gain inflated it to);
                // bars measure prominence above it, so silence stays flat while
                // speech still fills the range. During speech the between-word
                // dips pull the baseline back down, keeping peaks tall.
                let baseline = (samples.min() ?? 0) + Self.baselineDeadband
                let threshold = max(noiseFloor, baseline)
                let visualRange = max(0.2, 1 - threshold)

                for slot in 0..<capacity {
                    // Rightmost slot holds the newest sample; leading slots without
                    // history yet render as the quiet baseline.
                    let sampleIndex = samples.count - (capacity - slot)
                    let level = sampleIndex >= 0 ? samples[sampleIndex] : 0
                    let gated = CGFloat(max(0, min(1, (level - threshold) / visualRange)))
                    // Mild perceptual lift so quiet speech still moves the bars.
                    let height = max(minimumBarHeight, pow(gated, 0.85) * size.height)
                    let x = size.width - CGFloat(capacity - slot) * slotWidth + barSpacing
                    let rect = CGRect(x: x, y: midY - height / 2, width: barWidth, height: height)
                    // Older bars fade toward the leading edge.
                    let fade = 0.3 + 0.7 * Double(slot + 1) / Double(capacity)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(color.opacity(fade))
                    )
                }
            }
        }
        .onChange(of: isRecording) { _, nowRecording in
            // Panels are reused across sessions; a new recording starts from a clean baseline.
            if nowRecording {
                history.samples.removeAll()
                history.lastSampleAt = 0
            }
        }
    }
}

enum FloatingIndicatorTimeFormatting {
    static func elapsed(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

enum FloatingIndicatorToastAnchorEdge: Equatable {
    case automatic
    case below
}

struct FloatingIndicatorToastAnchor: Equatable {
    let rect: CGRect
    let visibleFrame: CGRect
    let edge: FloatingIndicatorToastAnchorEdge
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
    var onToastAnchorChanged: (() -> Void)?
    var availableInputDevicesProvider: (() -> [(uid: String, displayName: String)])?
    var selectedInputDeviceUIDProvider: (() -> String)?
    var selectedLanguageProvider: (() -> AppLanguage)?
    /// Focused-element rect in top-left screen coordinates for caret bubble placement.
    var anchorProvider: (() -> CGRect?)?
    var preferredScreenProvider: (() -> NSScreen?)?
}

/// Pure lifecycle rules for floating-indicator panel presentation.
/// Controllers bump a generation on show/hide so a hide animation started
/// before a newer presentation cannot close or nil the active panel.
enum FloatingIndicatorPresentationLifecycle {
    /// `true` only when the hide that captured `hideGeneration` is still the
    /// latest presentation transition (no intervening show/start/hide).
    static func shouldApplyHideCompletion(
        hideGeneration: UInt,
        currentGeneration: UInt
    ) -> Bool {
        hideGeneration == currentGeneration
    }
}

@MainActor
protocol FloatingIndicatorPresenting: AnyObject {
    var type: FloatingIndicatorType { get }
    var state: FloatingIndicatorState { get }

    func toastAnchor() -> FloatingIndicatorToastAnchor?
    func configure(actions: FloatingIndicatorActions)
    func showIdleIndicator()
    func showForCurrentState()
    func hide()
    func startRecording()
    func transitionToProcessing()
    func finishProcessing()
}

extension FloatingIndicatorPresenting {
    func toastAnchor() -> FloatingIndicatorToastAnchor? {
        nil
    }
}

@MainActor
final class FloatingIndicatorState: ObservableObject {

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    /// Latest smoothed meter sample. Deliberately not `@Published`: audio callbacks
    /// arrive far faster than visual cadence, and publishing forced every indicator
    /// root (pill shell, orb chrome, timers) to rebuild on each buffer. Waveform and
    /// blob drawing subtrees poll this value from their own timelines instead.
    private(set) var audioLevel: Float = 0.0
    /// Deliberately not `@Published`: the only reader is the Orb's blob/shader
    /// canvas, which polls at its own timeline cadence.
    private(set) var bandLevels = AudioBandLevels.zero
    @Published var isProcessing = false
    /// Selected input device mute/volume state from `InputMuteMonitor`.
    /// UI (orb/pill) can render a Muted state from this without observing CoreAudio directly.
    @Published var isInputMuted = false
    @Published var toggleRecordingHotkey = ""
    @Published var pushToTalkHotkey = ""

    private var recordingStartTime: Date?
    private var durationTimer: Timer?

    /// Minimum absolute delta before a meter sample replaces the stored level.
    /// Below this, the visual change is lost in bar/blob quantization.
    private static let meterEpsilon: Float = 0.005

    func startRecording() {
        isRecording = true
        isProcessing = false
        recordingStartTime = Date()
        recordingDuration = 0
        startDurationTimer()
        announce(localized("Recording started", locale: AppLocale.currentSelection().locale))
    }

    func transitionToProcessing() {
        isRecording = false
        isProcessing = true
        stopDurationTimer()
        announce(localized("Recording stopped. Processing transcription.", locale: AppLocale.currentSelection().locale))
    }

    func finishSession() {
        let wasRecording = isRecording
        let wasProcessing = isProcessing
        isRecording = false
        isProcessing = false
        recordingDuration = 0
        audioLevel = 0
        bandLevels = .zero
        stopDurationTimer()
        if wasRecording {
            announce(localized("Recording stopped", locale: AppLocale.currentSelection().locale))
        } else if wasProcessing {
            announce(localized("Transcription complete", locale: AppLocale.currentSelection().locale))
        }
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    func updateAudioLevel(_ level: Float) {
        let smoothed = min(1.0, max(0.0, audioLevel * 0.3 + level * 0.7))
        // Keep the latest sample only when it moves the needle; silent no-ops and
        // sub-threshold jitter never touch storage.
        if abs(smoothed - audioLevel) < Self.meterEpsilon {
            return
        }
        audioLevel = smoothed
    }

    func updateBandLevels(_ levels: AudioBandLevels) {
        func smooth(_ old: Float, _ new: Float) -> Float {
            min(1.0, max(0.0, old * 0.3 + new * 0.7))
        }
        let next = AudioBandLevels(
            low: smooth(bandLevels.low, levels.low),
            mid: smooth(bandLevels.mid, levels.mid),
            high: smooth(bandLevels.high, levels.high)
        )
        if abs(next.low - bandLevels.low) < Self.meterEpsilon,
           abs(next.mid - bandLevels.mid) < Self.meterEpsilon,
           abs(next.high - bandLevels.high) < Self.meterEpsilon {
            return
        }
        bandLevels = next
    }

    func updateHotkeys(toggleHotkey: String, pushToTalkHotkey: String) {
        self.toggleRecordingHotkey = normalize(hotkey: toggleHotkey)
        self.pushToTalkHotkey = normalize(hotkey: pushToTalkHotkey)
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
