//
//  WaveformView.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import SwiftUI

/// Pure geometry helpers for the Scorched Earth waveform scrubber (spec §6).
enum WaveformGeometry {
    static let barWidth: CGFloat = 3.5
    static let barPitch: CGFloat = 15
    static let barCornerRadius: CGFloat = 1.75
    static let height: CGFloat = 32
    static let playheadWidth: CGFloat = 2

    /// How many bars fit in `width` at the design pitch.
    static func barCount(forWidth width: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        // First bar starts at 0; subsequent bars every `barPitch`.
        return max(1, Int(floor((width - barWidth) / barPitch)) + 1)
    }

    /// Sample / average `peaks` down (or up) to `count` display bars in 0…1.
    static func displayPeaks(from peaks: [Float], count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard !peaks.isEmpty else {
            return Array(repeating: 0.15, count: count)
        }
        if peaks.count == count { return peaks.map { min(1, max(0, $0)) } }

        var result = [Float](repeating: 0, count: count)
        if peaks.count > count {
            let bucket = Double(peaks.count) / Double(count)
            for i in 0..<count {
                let start = Int(Double(i) * bucket)
                let end = min(peaks.count, Int(Double(i + 1) * bucket))
                let slice = peaks[start..<max(start + 1, end)]
                let peak = slice.max() ?? 0
                result[i] = min(1, max(0, peak))
            }
        } else {
            for i in 0..<count {
                let source = Int(Double(i) * Double(peaks.count) / Double(count))
                result[i] = min(1, max(0, peaks[min(source, peaks.count - 1)]))
            }
        }
        return result
    }

    static func playheadX(progress: Double, width: CGFloat) -> CGFloat {
        let p = min(1, max(0, progress))
        return CGFloat(p) * max(width - playheadWidth, 0)
    }
}

/// Waveform scrubber: 3.5 pt bars / 15 pt pitch / 1.75 radius;
/// played = accent, unplayed = line; 2×32 ink playhead; tap/drag → seek (spec §6).
struct WaveformView: View {
    let peaks: [Float]
    /// 0…1 playback progress.
    var progress: Double
    var onSeek: ((Double) -> Void)?

    @Environment(\.locale) private var locale

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let count = WaveformGeometry.barCount(forWidth: width)
            let display = WaveformGeometry.displayPeaks(from: peaks, count: count)
            let playheadX = WaveformGeometry.playheadX(progress: progress, width: width)

            ZStack(alignment: .leading) {
                HStack(spacing: WaveformGeometry.barPitch - WaveformGeometry.barWidth) {
                    ForEach(Array(display.enumerated()), id: \.offset) { index, value in
                        let barProgress = count > 1 ? Double(index) / Double(count - 1) : 0
                        let played = barProgress <= progress
                        RoundedRectangle(cornerRadius: WaveformGeometry.barCornerRadius, style: .continuous)
                            .fill(played ? AppColors.accent : AppColors.border)
                            .frame(
                                width: WaveformGeometry.barWidth,
                                height: max(4, CGFloat(value) * WaveformGeometry.height)
                            )
                            .frame(height: WaveformGeometry.height, alignment: .center)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(AppColors.textPrimary)
                    .frame(width: WaveformGeometry.playheadWidth, height: WaveformGeometry.height)
                    .offset(x: playheadX)
            }
            .frame(height: WaveformGeometry.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let onSeek else { return }
                        let x = min(max(0, value.location.x), width)
                        onSeek(width > 0 ? Double(x / width) : 0)
                    }
            )
        }
        .frame(height: WaveformGeometry.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("Playback position", locale: locale))
        .accessibilityValue("\(Int(min(max(progress, 0), 1) * 100))%")
        .accessibilityAdjustableAction { direction in
            guard let onSeek else { return }
            let delta = direction == .increment ? 0.05 : -0.05
            onSeek(min(max(progress + delta, 0), 1))
        }
    }
}

#Preview("WaveformView") {
    WaveformView(
        peaks: (0..<48).map { i in Float(0.2 + 0.7 * abs(sin(Double(i) * 0.35))) },
        progress: 0.35,
        onSeek: { _ in }
    )
    .padding()
    .frame(width: 360)
    .background(AppColors.windowBackground)
    .themeRefresh()
}
