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
        if state.isRecording {
            self = .recording(duration: state.recordingDuration)
        } else if state.isProcessing {
            self = .processing
        } else {
            self = .ready
        }
    }
}

/// "Ready to dictate" / recording / processing footer card (spec §3).
struct StatusCard: View {
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
    }

    private var title: String {
        switch phase {
        case .ready: return "Ready to dictate"
        case .recording: return "Recording"
        case .processing: return "Processing"
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
