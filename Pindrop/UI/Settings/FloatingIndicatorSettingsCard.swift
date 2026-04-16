//
//  FloatingIndicatorSettingsCard.swift
//  Pindrop
//
//  Created on 2026-03-06.
//

import SwiftUI

struct FloatingIndicatorSettingsCard: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.locale) private var locale

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var selectedType: Binding<FloatingIndicatorType> {
        Binding(
            get: { settings.selectedFloatingIndicatorType },
            set: { settings.selectedFloatingIndicatorType = $0 }
        )
    }

    var body: some View {
        SettingsCard(title: localized("Floating Indicator", locale: locale), icon: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localized("Show floating indicator", locale: locale))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(localized("Shows recording state in a lightweight overlay window.", locale: locale))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer()

                    Toggle("", isOn: $settings.floatingIndicatorEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Text(localized("Choose which floating indicator style appears when the overlay is enabled.", locale: locale))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(FloatingIndicatorType.allCases) { type in
                        FloatingIndicatorOptionCard(
                            type: type,
                            isSelected: selectedType.wrappedValue == type,
                            isEnabled: settings.floatingIndicatorEnabled,
                            onSelect: { selectedType.wrappedValue = type }
                        )
                    }
                }
                .disabled(!settings.floatingIndicatorEnabled)
                .opacity(settings.floatingIndicatorEnabled ? 1 : 0.56)
            }
        }
    }
}

private struct FloatingIndicatorOptionCard: View {
    @Environment(\.locale) private var locale
    let type: FloatingIndicatorType
    let isSelected: Bool
    let isEnabled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                FloatingIndicatorPreviewGlyph(type: type)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? AppColors.accent : AppColors.textTertiary)

                        Text(type.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppColors.textPrimary)
                    }

                    Text(type.description)
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .overlay(border)
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(type.displayName) floating indicator")
        .accessibilityValue(isSelected ? localized("Selected", locale: locale) : localized("Not selected", locale: locale))
        .accessibilityHint(isEnabled ? localized("Select this floating indicator style.", locale: locale) : localized("Enable the floating indicator to choose a style.", locale: locale))
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
            .fill(isSelected ? AppColors.accent.opacity(0.12) : AppColors.elevatedSurface)
    }

    private var border: some View {
        Color.clear
            .hairlineBorder(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md),
                style: isSelected ? AppColors.accent.opacity(0.8) : AppColors.border.opacity(0.5)
            )
    }
}

private struct FloatingIndicatorPreviewGlyph: View {
    let type: FloatingIndicatorType

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.accentBackground.opacity(0.65),
                            AppColors.elevatedSurface
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            switch type {
            case .notch:
                NotchIndicatorSelectionGlyph()
            case .pill:
                PillIndicatorSelectionGlyph()
            case .bubble:
                CaretBubbleIndicatorSelectionGlyph()
            case .dot:
                DotIndicatorSelectionGlyph()
            }
        }
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .hairlineBorder(
            RoundedRectangle(cornerRadius: 12, style: .continuous),
            style: AppColors.border.opacity(0.6)
        )
    }
}

private struct NotchIndicatorSelectionGlyph: View {
    private let centerWidth: CGFloat = 70
    private let sideWidth: CGFloat = 44
    private let indicatorHeight: CGFloat = 30
    private let statusBarHeight: CGFloat = 30

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(AppColors.overlaySurface.opacity(0.18))
                .frame(height: statusBarHeight)
                .frame(maxWidth: .infinity, alignment: .top)

            HStack(spacing: 0) {
                leftSegment
                centerSegment
                rightSegment
            }
            .frame(width: centerWidth + (sideWidth * 2), height: indicatorHeight)
            .background(AppColors.overlaySurfaceStrong)
            .clipShape(NotchShape(cornerRadius: 12))
            .shadow(color: AppColors.shadowColor.opacity(0.18), radius: 8, y: 4)
            .offset(y: 1)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var leftSegment: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AppColors.recording)
                .frame(width: 8, height: 8)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(AppColors.overlayTextPrimary.opacity(0.82))
                .frame(width: 18, height: 3)
        }
        .padding(.horizontal, 8)
        .frame(width: sideWidth, height: indicatorHeight)
    }

    private var centerSegment: some View {
        Rectangle()
            .fill(AppColors.overlaySurfaceStrong)
            .frame(width: centerWidth, height: indicatorHeight)
    }

    private var rightSegment: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array([5.0, 10.0, 7.0, 12.0, 6.0].enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: 1)
                    .fill(AppColors.overlayWaveform)
                    .frame(width: 3, height: height)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: sideWidth, height: indicatorHeight)
    }
}

private struct PillIndicatorSelectionGlyph: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(AppColors.overlaySurface)
                .frame(width: 124, height: 30)
                .shadow(color: AppColors.shadowColor.opacity(0.16), radius: 8, y: 4)

            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(AppColors.overlayTextPrimary.opacity(0.1))

                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(AppColors.overlayTextPrimary.opacity(0.9))
                }
                .frame(width: 18, height: 18)

                HStack(spacing: 2) {
                    ForEach(Array([4.0, 8.0, 12.0, 8.0, 5.0].enumerated()), id: \.offset) { _, height in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(AppColors.overlayTextPrimary.opacity(0.86))
                            .frame(width: 3, height: height)
                    }
                }

                ZStack {
                    Circle()
                        .fill(AppColors.overlayRecording)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(AppColors.overlayTextPrimary)
                        .frame(width: 6, height: 6)
                }
                .frame(width: 18, height: 18)
                .shadow(color: AppColors.overlayRecording.opacity(0.25), radius: 4)
            }
            .padding(.horizontal, 9)
            .offset(y: -6)
        }
        .padding(.bottom, 10)
    }
}

private struct CaretBubbleIndicatorSelectionGlyph: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AppColors.overlaySurface)
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(AppColors.overlayTextPrimary.opacity(0.92))
                )

            Capsule()
                .fill(AppColors.overlaySurface)
                .frame(width: 42, height: 28)
                .overlay {
                    HStack(spacing: 2) {
                        ForEach(Array([4.0, 8.0, 12.0, 8.0, 5.0].enumerated()), id: \.offset) { _, height in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(AppColors.overlayWaveform)
                                .frame(width: 3, height: height)
                        }
                    }
                }
                .shadow(color: AppColors.shadowColor.opacity(0.16), radius: 8, y: 4)

            Circle()
                .fill(AppColors.overlayRecording)
                .frame(width: 18, height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(AppColors.overlayTextPrimary)
                        .frame(width: 6, height: 6)
                )
                .shadow(color: AppColors.overlayRecording.opacity(0.22), radius: 4)
        }
        .padding(.top, 6)
    }
}

private struct DotIndicatorSelectionGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AppColors.overlaySurfaceStrong)
                .shadow(color: AppColors.shadowColor.opacity(0.18), radius: 10, y: 5)
                .hairlineStroke(Circle(), style: AppColors.overlayLine.opacity(0.6))

            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppColors.overlayTooltipAccent, AppColors.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 16, height: 16)
        }
        .frame(width: 40, height: 40)
    }
}

#Preview {
    FloatingIndicatorSettingsCard(settings: SettingsStore())
        .padding()
        .frame(width: 520)
}
