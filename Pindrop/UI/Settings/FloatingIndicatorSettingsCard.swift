//
//  FloatingIndicatorSettingsCard.swift
//  Pindrop
//
//  Created on 2026-03-06.
//

import SwiftUI

struct FloatingIndicatorSettingsCard: View {
    @ObservedObject var settings: SettingsStore

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
        SettingsCard(title: "Floating Indicator", icon: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show floating indicator")
                            .font(.body)
                        Text("Shows recording state in a lightweight overlay window.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $settings.floatingIndicatorEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Text("Choose which floating indicator style appears when the overlay is enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(isEnabled ? "Select this floating indicator style." : "Enable the floating indicator to choose a style.")
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
            .fill(isSelected ? AppColors.accent.opacity(0.12) : AppColors.elevatedSurface)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
            .strokeBorder(isSelected ? AppColors.accent.opacity(0.8) : AppColors.border.opacity(0.5), lineWidth: 1)
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
                            Color.black.opacity(0.04),
                            Color.black.opacity(0.08)
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
            }
        }
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6)
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
                .fill(Color.black.opacity(0.14))
                .frame(height: statusBarHeight)
                .frame(maxWidth: .infinity, alignment: .top)

            HStack(spacing: 0) {
                leftSegment
                centerSegment
                rightSegment
            }
            .frame(width: centerWidth + (sideWidth * 2), height: indicatorHeight)
            .background(Color.black.opacity(0.9))
            .clipShape(NotchShape(cornerRadius: 12))
            .shadow(color: Color.black.opacity(0.2), radius: 8, y: 4)
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
                .fill(Color.white.opacity(0.82))
                .frame(width: 18, height: 3)
        }
        .padding(.horizontal, 8)
        .frame(width: sideWidth, height: indicatorHeight)
    }

    private var centerSegment: some View {
        Rectangle()
            .fill(Color.black.opacity(0.9))
            .frame(width: centerWidth, height: indicatorHeight)
    }

    private var rightSegment: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array([5.0, 10.0, 7.0, 12.0, 6.0].enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(red: 0.4, green: 0.85, blue: 1.0))
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
                .fill(Color.black.opacity(0.84))
                .frame(width: 124, height: 30)
                .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)

            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))

                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                .frame(width: 18, height: 18)

                HStack(spacing: 2) {
                    ForEach(Array([4.0, 8.0, 12.0, 8.0, 5.0].enumerated()), id: \.offset) { _, height in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.86))
                            .frame(width: 3, height: height)
                    }
                }

                ZStack {
                    Circle()
                        .fill(Color(red: 0.94, green: 0.38, blue: 0.38))

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                }
                .frame(width: 18, height: 18)
                .shadow(color: Color.red.opacity(0.25), radius: 4)
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
                .fill(Color.black.opacity(0.84))
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.92))
                )

            Capsule()
                .fill(Color.black.opacity(0.84))
                .frame(width: 42, height: 28)
                .overlay {
                    HStack(spacing: 2) {
                        ForEach(Array([4.0, 8.0, 12.0, 8.0, 5.0].enumerated()), id: \.offset) { _, height in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color(red: 0.4, green: 0.85, blue: 1.0))
                                .frame(width: 3, height: height)
                        }
                    }
                }
                .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)

            Circle()
                .fill(Color(red: 0.94, green: 0.38, blue: 0.38))
                .frame(width: 18, height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                )
                .shadow(color: Color.red.opacity(0.22), radius: 4)
        }
        .padding(.top, 6)
    }
}

#Preview {
    FloatingIndicatorSettingsCard(settings: SettingsStore())
        .padding()
        .frame(width: 520)
}
