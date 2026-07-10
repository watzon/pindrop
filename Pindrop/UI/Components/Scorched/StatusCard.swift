//
//  StatusCard.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import SwiftUI

/// Sidebar status card phase driven by floating-indicator recording state.
enum StatusCardPhase: Equatable {
    case ready
    case recording(duration: TimeInterval)
    case processing

    @MainActor
    init(state: FloatingIndicatorState) {
        self.init(isRecording: state.isRecording, isProcessing: state.isProcessing, duration: state.recordingDuration)
    }

    /// Pure mapping for tests and callers without a live indicator state.
    init(isRecording: Bool, isProcessing: Bool, duration: TimeInterval = 0) {
        if isRecording {
            self = .recording(duration: duration)
        } else if isProcessing {
            self = .processing
        } else {
            self = .ready
        }
    }

    var isActive: Bool {
        switch self {
        case .ready: return false
        case .recording, .processing: return true
        }
    }
}

/// "Ready to dictate" / recording / processing footer card (spec §3).
struct StatusCard: View {
    @Environment(\.locale) private var locale

    let phase: StatusCardPhase
    var hotkeyHint: String = ""

    init(phase: StatusCardPhase, hotkeyHint: String = "") {
        self.phase = phase
        self.hotkeyHint = hotkeyHint
    }

    @MainActor
    init(state: FloatingIndicatorState, hotkeyHint: String = "") {
        self.phase = StatusCardPhase(state: state)
        self.hotkeyHint = hotkeyHint.isEmpty ? state.toggleRecordingHotkey : hotkeyHint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(statusColor)
                Text(title)
                    .font(AppTypography.labelSemibold)
                    .foregroundStyle(statusColor)
                Spacer(minLength: 0)
                if case .recording(let duration) = phase {
                    Text(Self.formatDuration(duration))
                        .font(AppTypography.monoSmall)
                        .foregroundStyle(statusColor)
                        .monospacedDigit()
                }
            }

            if !hotkeyHint.isEmpty, case .ready = phase {
                Text(hotkeyHint)
                    .font(AppTypography.monoSmall)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private var title: String {
        switch phase {
        case .ready: return localized("Ready to dictate", locale: locale)
        case .recording: return localized("Recording", locale: locale)
        case .processing: return localized("Processing", locale: locale)
        }
    }

    private var iconName: String {
        switch phase {
        case .ready: return "mic.fill"
        case .recording: return "record.circle"
        case .processing: return "ellipsis.circle"
        }
    }

    private var statusColor: Color {
        switch phase {
        case .ready, .processing: return AppColors.accent
        case .recording: return AppColors.recording
        }
    }

    private var backgroundColor: Color {
        switch phase {
        case .ready, .processing: return AppColors.accentBackground
        case .recording: return AppColors.errorBackground
        }
    }

    static func formatDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Collapsed sidebar status indicator (derived 64 pt rail — not in Paper file).
struct StatusCardDot: View {
    let phase: StatusCardPhase

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .opacity(phase.isActive ? (pulse ? 0.45 : 1.0) : 1.0)
            .animation(
                phase.isActive && !reduceMotion
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : nil,
                value: pulse
            )
            .onAppear { pulse = phase.isActive }
            .onChange(of: phase.isActive) { _, active in pulse = active }
            .accessibilityLabel(accessibilityTitle)
    }

    private var dotColor: Color {
        switch phase {
        case .ready, .processing: return AppColors.accent
        case .recording: return AppColors.recording
        }
    }

    private var accessibilityTitle: String {
        switch phase {
        case .ready: return "Ready"
        case .recording: return "Recording"
        case .processing: return "Processing"
        }
    }
}

#Preview("StatusCard") {
    VStack(spacing: 12) {
        StatusCard(phase: .ready, hotkeyHint: "⌥ Space anywhere")
        StatusCard(phase: .recording(duration: 42), hotkeyHint: "")
        StatusCard(phase: .processing, hotkeyHint: "")
    }
    .padding()
    .frame(width: 220)
    .background(AppColors.windowBackground)
    .themeRefresh()
}
