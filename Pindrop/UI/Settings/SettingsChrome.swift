//
//  SettingsChrome.swift
//  Pindrop
//
//  Created on 2026-07-10.
//
//  Shared Scorched Earth settings chrome (spec §13).
//

import AppKit
import SwiftUI

// MARK: - Root shell (titlebar + tab strip + scrolling pane)

struct SettingsShellView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: SettingsWindowModel
    let launchAtLoginManager: LaunchAtLoginManager
    let updateService: UpdateService

    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        VStack(spacing: 0) {
            titlebar
            tabStrip
            ScrollView {
                SettingsPaneContent(
                    settings: settings,
                    tab: model.selectedTab,
                    launchAtLoginManager: launchAtLoginManager,
                    updateService: updateService
                )
                .padding(.top, SettingsLayoutMetrics.contentTopPadding)
                .padding(.horizontal, SettingsLayoutMetrics.contentSidePadding)
                .padding(.bottom, SettingsLayoutMetrics.contentBottomPadding)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppColors.windowBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themeRefresh()
    }

    private var titlebar: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: SettingsLayoutMetrics.titlebarTrafficLane)
            Spacer(minLength: 0)
            Text(model.selectedTab.title(locale: locale))
                .font(AppTypography.labelStrongSelected)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Color.clear
                .frame(width: SettingsLayoutMetrics.titlebarTrafficLane)
        }
        .padding(.top, SettingsLayoutMetrics.titlebarTopPadding)
        .padding(.horizontal, SettingsLayoutMetrics.titlebarSidePadding)
        .padding(.bottom, SettingsLayoutMetrics.titlebarBottomPadding)
        .background(AppColors.windowBackground)
    }

    private var tabStrip: some View {
        VStack(spacing: 0) {
            HStack(spacing: SettingsLayoutMetrics.tabGap) {
                ForEach(SettingsTab.allCases) { tab in
                    SettingsTabChip(
                        tab: tab,
                        isSelected: model.selectedTab == tab,
                        locale: locale
                    ) {
                        model.selectedTab = tab
                    }
                }
            }
            .padding(.top, SettingsLayoutMetrics.tabTopPadding)
            .padding(.bottom, SettingsLayoutMetrics.tabBottomPadding)
            .frame(maxWidth: .infinity)
            .onMoveCommand { direction in
                moveTabFocus(direction)
            }

            Rectangle()
                .fill(AppColors.border)
                .frame(height: 1)
        }
        .background(AppColors.windowBackground)
    }

    private func moveTabFocus(_ direction: MoveCommandDirection) {
        guard direction == .left || direction == .right,
              let currentIndex = SettingsTab.allCases.firstIndex(of: model.selectedTab)
        else { return }

        let visualStep: Int
        switch (direction, layoutDirection) {
        case (.right, .leftToRight), (.left, .rightToLeft): visualStep = 1
        default: visualStep = -1
        }
        let tabs = SettingsTab.allCases
        let nextIndex = min(max(currentIndex + visualStep, tabs.startIndex), tabs.index(before: tabs.endIndex))
        model.selectedTab = tabs[nextIndex]
    }
}

// MARK: - Tab chip

struct SettingsTabChip: View {
    let tab: SettingsTab
    let isSelected: Bool
    let locale: Locale
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: SettingsLayoutMetrics.tabColumnGap) {
                Image(systemName: tab.systemIcon)
                    .font(.system(size: SettingsLayoutMetrics.tabIconSize, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)
                Text(tab.title(locale: locale))
                    .font(
                        isSelected
                            ? AppTypography.badge
                            : AppTypography.captionMedium
                    )
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)
            }
            .padding(.vertical, SettingsLayoutMetrics.tabVerticalPadding)
            .padding(.horizontal, SettingsLayoutMetrics.tabHorizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: SettingsLayoutMetrics.tabRadius, style: .continuous)
                    .fill(isSelected ? AppColors.accentBackground : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: SettingsLayoutMetrics.tabRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardFocusRing(RoundedRectangle(cornerRadius: SettingsLayoutMetrics.tabRadius, style: .continuous))
        .accessibilityLabel(tab.title(locale: locale))
        .accessibilityIdentifier(tab.accessibilityIdentifier)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Group card

struct SettingsGroupCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .accessibilityElement(children: .contain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardRadius, style: .continuous)
                .fill(AppColors.contentBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardRadius, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }
}

// MARK: - Row

struct SettingsRow<Label: View, Control: View>: View {
    var showSeparator: Bool = true
    @ViewBuilder let label: Label
    @ViewBuilder let control: Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: SettingsLayoutMetrics.rowGap) {
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
                control
            }
            .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)
            .padding(.horizontal, SettingsLayoutMetrics.rowHorizontalPadding)

            if showSeparator {
                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 1)
                    .padding(.leading, SettingsLayoutMetrics.rowHorizontalPadding)
            }
        }
    }
}

struct SettingsRowLabel: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(AppTypography.labelStrong)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(AppTypography.captionLarge)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Toggle (36×21 accent/line)

struct SettingsToggle: View {
    @Binding var isOn: Bool
    let label: String

    @Environment(\.locale) private var locale

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn ? AppColors.accent : AppColors.border)
                    .frame(
                        width: SettingsLayoutMetrics.toggleWidth,
                        height: SettingsLayoutMetrics.toggleHeight
                    )
                Circle()
                    .fill(Color(nsColor: NSColor(pindropHex: "#FCFBF7") ?? .white))
                    .frame(
                        width: SettingsLayoutMetrics.toggleKnob,
                        height: SettingsLayoutMetrics.toggleKnob
                    )
                    .padding(SettingsLayoutMetrics.togglePadding)
            }
        }
        .buttonStyle(.plain)
        .appAnimation(.fast, value: isOn)
        .keyboardFocusRing(Capsule(style: .continuous))
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(
            isOn
                ? localized("On", locale: locale)
                : localized("Off", locale: locale)
        )
    }
}

// MARK: - Dropdown / small button (radius 7)

struct SettingsDropdownButton<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(AppTypography.label)
            .foregroundStyle(AppColors.textPrimary)
            .padding(.vertical, SettingsLayoutMetrics.dropdownVerticalPadding)
            .padding(.horizontal, SettingsLayoutMetrics.dropdownHorizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: SettingsLayoutMetrics.dropdownRadius, style: .continuous)
                    .fill(AppColors.windowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsLayoutMetrics.dropdownRadius, style: .continuous)
                    .strokeBorder(AppColors.border, lineWidth: 1)
            )
    }
}

struct SettingsMenuButton: View {
    let title: String
    var showsChevron: Bool = true

    var body: some View {
        SettingsDropdownButton {
            HStack(spacing: 8) {
                Text(title)
                    .lineLimit(1)
                if showsChevron {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
    }
}

// MARK: - Destructive footer link

struct SettingsDestructiveFooter: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.label)
                .foregroundStyle(AppColors.error)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Accent text link

struct SettingsAccentLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.label)
                .foregroundStyle(AppColors.accent)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Segmented chip row (System/Light/Dark, Orb/Pill)

struct SettingsSegmentedChips<T: Hashable & Identifiable>: View {
    let options: [T]
    @Binding var selection: T
    let title: (T) -> String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                FilterChip(
                    title: title(option),
                    isSelected: selection == option
                ) {
                    selection = option
                }
            }
        }
    }
}

// MARK: - Theme preset chip (accent dot + name)

struct SettingsThemePresetChip: View {
    @Environment(\.locale) private var locale

    let preset: PindropThemePreset
    let variant: PindropThemeVariant
    let isSelected: Bool
    let action: () -> Void

    private var accent: Color {
        let hex = preset.profile(for: variant).accentHex
        return Color(nsColor: NSColor(pindropHex: hex) ?? .controlAccentColor)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 10, height: 10)
                Text(preset.title)
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textPrimary)
                if preset.isLegacy {
                    Text(localized("Legacy", locale: locale))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? AppColors.accentBackground : AppColors.windowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppColors.accent.opacity(0.55) : AppColors.border,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .keyboardFocusRing(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("settings.theme.preset.\(preset.id)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Keyboard chip (mono)

struct SettingsKbdChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppTypography.monoSmall)
            .foregroundStyle(AppColors.textPrimary)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AppColors.windowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(AppColors.border, lineWidth: 1)
            )
    }
}

// MARK: - Pane stack helper

struct SettingsPaneStack<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: SettingsLayoutMetrics.groupGap) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// MARK: - Window model

@MainActor
final class SettingsWindowModel: ObservableObject {
    @Published var selectedTab: SettingsTab = .general

    func select(_ tab: SettingsTab) {
        selectedTab = tab
    }
}
