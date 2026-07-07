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
                Text(localized("Choose how Pindrop appears on screen while you dictate.", locale: locale))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(FloatingIndicatorType.allCases) { type in
                        FloatingIndicatorOptionCard(
                            type: type,
                            isSelected: selectedType.wrappedValue == type,
                            onSelect: { selectedType.wrappedValue = type }
                        )
                    }
                }
            }
        }
    }
}

private struct FloatingIndicatorOptionCard: View {
    @Environment(\.locale) private var locale
    let type: FloatingIndicatorType
    let isSelected: Bool
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
        .accessibilityHint(localized("Select this floating indicator style.", locale: locale))
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
            case .pill:
                PillIndicatorSelectionGlyph()
            case .orb:
                OrbIndicatorSelectionGlyph()
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

private struct OrbIndicatorSelectionGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(OrbPalette.surface)
                .shadow(color: AppColors.shadowColor.opacity(0.18), radius: 10, y: 5)
                .hairlineStroke(Circle(), style: OrbPalette.rimSoft)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.24), .clear],
                        center: .init(x: 0.32, y: 0.22),
                        startRadius: 0,
                        endRadius: 28
                    )
                )

            // Static hint of the band blobs inside the orb.
            glyphBlob(diameter: 22, color: OrbPalette.bandLow, offset: CGSize(width: -4, height: 3))
            glyphBlob(diameter: 18, color: OrbPalette.bandMid, offset: CGSize(width: 5, height: -3))
            glyphBlob(diameter: 13, color: OrbPalette.bandHigh, offset: CGSize(width: 1, height: 4))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.7), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 5
                    )
                )
                .frame(width: 10, height: 10)
                .blendMode(.plusLighter)
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private func glyphBlob(diameter: CGFloat, color: Color, offset: CGSize) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.85), color.opacity(0.05)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
            .offset(offset)
            .blur(radius: 1.2)
            .blendMode(.plusLighter)
    }
}

#Preview {
    FloatingIndicatorSettingsCard(settings: SettingsStore())
        .padding()
        .frame(width: 520)
}
