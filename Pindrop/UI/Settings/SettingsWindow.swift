//
//  SettingsWindow.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI
import PindropSharedNavigation

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case theme = "Theme"
    case hotkeys = "Hotkeys"
    case ai = "AI Enhancement"
    case update = "Update"
    case about = "About"

    var id: String { rawValue }

    func title(locale: Locale) -> String {
        localized(definition.titleKey, locale: locale)
    }

    var systemIcon: String {
        definition.systemIcon
    }

    var subtitle: String {
        subtitle(locale: .autoupdatingCurrent)
    }

    func subtitle(locale: Locale) -> String {
        localized(definition.subtitleKey, locale: locale)
    }

    func matches(_ searchText: String) -> Bool {
        SettingsTab.browseState(for: searchText, selectedTab: self, initialTab: self).filteredSections.contains(coreValue)
    }

    var coreValue: SettingsSection {
        switch self {
        case .general: .general
        case .theme: .theme
        case .hotkeys: .hotkeys
        case .ai: .ai
        case .update: .update
        case .about: .about
        }
    }

    init(coreValue: SettingsSection) {
        switch coreValue {
        case .general:
            self = .general
        case .theme:
            self = .theme
        case .hotkeys:
            self = .hotkeys
        case .ai:
            self = .ai
        case .update:
            self = .update
        default:
            self = .about
        }
    }

    fileprivate var definition: SettingsSectionDefinition {
        SettingsShell.shared.section(id: coreValue)
    }

    fileprivate static func browseState(
        for query: String,
        selectedTab: SettingsTab?,
        initialTab: SettingsTab
    ) -> SettingsBrowseState {
        SettingsShell.shared.browse(
            query: query,
            selectedSection: selectedTab?.coreValue,
            initialSection: initialTab.coreValue
        )
    }
}

struct SettingsWindow: View {
    @ObservedObject var settings: SettingsStore

    var initialTab: SettingsTab = .general

    var body: some View {
        ZStack {
            AppColors.windowBackground
                .ignoresSafeArea()

            SettingsContainerView(settings: settings, initialTab: initialTab)
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.top, AppTheme.Window.mainContentTopInset)
                .padding(.bottom, AppTheme.Spacing.xxl)
        }
        .frame(
            minWidth: AppTheme.Window.settingsMinWidth,
            minHeight: AppTheme.Window.settingsMinHeight
        )
        .environment(\.locale, settings.selectedAppLanguage.locale)
        .themeRefresh()
    }
}

struct SettingsContainerView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.locale) private var locale
    @State private var selectedTab: SettingsTab
    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool

    var initialTab: SettingsTab = .general

    init(settings: SettingsStore, initialTab: SettingsTab = .general) {
        self.settings = settings
        self.initialTab = initialTab
        self._selectedTab = State(initialValue: initialTab)
        self._searchText = State(
            initialValue: AppTestMode.isRunningUITests
                ? (AppTestMode.environment[AppTestMode.uiTestSettingsSearchTextKey] ?? "")
                : ""
        )
    }

    private var filteredTabs: [SettingsTab] {
        browseState.filteredSections.map(SettingsTab.init(coreValue:))
    }

    private var browseState: SettingsBrowseState {
        SettingsTab.browseState(for: searchText, selectedTab: selectedTab, initialTab: initialTab)
    }

    private var activeTab: SettingsTab {
        SettingsTab(coreValue: browseState.selectedSection)
    }

    var body: some View {
        MainContentPageLayout(
            scrollContent: true,
            headerBottomPadding: filteredTabs.isEmpty ? AppTheme.Spacing.lg : AppTheme.Spacing.xl
        ) {
            fixedHeader
        } content: {
            scrollableContent
        }
        .onChange(of: initialTab) { _, newValue in
            selectedTab = newValue
        }
        .onChange(of: searchText) { _, _ in
            selectedTab = activeTab
        }
        .onAppear {
            if AppTestMode.isRunningUITests {
                isSearchFieldFocused = true
            }
        }
    }

    private func selectTab(_ tab: SettingsTab) {
        withAnimation(AppTheme.Animation.fast) {
            selectedTab = tab
        }
    }

    @ViewBuilder
    private var scrollableContent: some View {
        if filteredTabs.isEmpty {
            emptySearchState
        } else {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text(activeTab.title(locale: locale))
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(activeTab.subtitle(locale: locale))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Divider()
                    .background(AppColors.divider)

                Group {
                    switch activeTab {
                    case .general:
                        GeneralSettingsView(settings: settings)
                    case .theme:
                        ThemeSettingsView(settings: settings)
                    case .hotkeys:
                        HotkeysSettingsView(settings: settings)
                    case .ai:
                        AIEnhancementSettingsView(settings: settings)
                    case .update:
                        UpdateSettingsView()
                    case .about:
                        AboutSettingsView()
                    }
                }
            }
        }
    }

    private var fixedHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(localized("Settings", locale: locale))
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text(localized("Search settings or jump between sections without leaving the main workspace.", locale: locale))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }

            HStack(alignment: .center, spacing: AppTheme.Spacing.lg) {
                searchField

                if !searchText.isEmpty {
                    Text(matchCountText)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }

            if !filteredTabs.isEmpty {
                tabsBar
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tabsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(filteredTabs) { tab in
                    SettingsTabChip(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        action: { selectTab(tab) }
                    )
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textTertiary)

            TextField(localized("Search settings", locale: locale), text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
                .accessibilityIdentifier("settings.search.field")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.search.clear")
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, 10)
        .frame(maxWidth: 360)
        .background(AppColors.surfaceBackground, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md))
        .hairlineBorder(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md),
            style: AppColors.border.opacity(0.8)
        )
    }

    private var emptySearchState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)

            VStack(spacing: AppTheme.Spacing.xs) {
                Text(localized("No settings found", locale: locale))
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textPrimary)

                Text(localized("Try searching for terms like hotkeys, microphone, updates, or vibe mode.", locale: locale))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.xxl)
        .accessibilityIdentifier("settings.search.emptyState")
    }
}

private struct SettingsTabChip: View {
    @Environment(\.locale) private var locale
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: tab.systemIcon)
                    .font(.system(size: 13, weight: .semibold))

                Text(tab.title(locale: locale))
                    .font(AppTypography.subheadline)
                    .lineLimit(1)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AppColors.surfaceBackground : AppColors.windowBackground.opacity(0.001))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? AppColors.border.opacity(0.9) : AppColors.border.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(tab.accessibilityIdentifier)
    }
}

private extension SettingsContainerView {
    var matchCountText: String {
        let format = filteredTabs.count == 1 ? localized("%d match", locale: locale) : localized("%d matches", locale: locale)
        return String(format: format, filteredTabs.count)
    }
}

private extension SettingsTab {
    var accessibilityIdentifier: String {
        definition.accessibilityIdentifier
    }
}

#Preview("Settings Window - Light") {
    SettingsWindow(settings: SettingsStore())
        .modelContainer(PreviewContainer.empty)
        .preferredColorScheme(.light)
}

#Preview("Settings Window - Dark") {
    SettingsWindow(settings: SettingsStore())
        .modelContainer(PreviewContainer.empty)
        .preferredColorScheme(.dark)
}
