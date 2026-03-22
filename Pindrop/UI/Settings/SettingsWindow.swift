//
//  SettingsWindow.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case theme = "Theme"
    case hotkeys = "Hotkeys"
    case ai = "AI Enhancement"
    case update = "Update"
    case about = "About"

    var id: String { rawValue }

    var systemIcon: String {
        switch self {
        case .general: return "gear"
        case .theme: return "paintbrush"
        case .hotkeys: return "keyboard"
        case .ai: return "sparkles"
        case .update: return "arrow.triangle.2.circlepath"
        case .about: return "info.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "Output, audio, interface, and everyday behavior"
        case .theme:
            return "Light, dark, and curated palette presets"
        case .hotkeys:
            return "Configure keyboard shortcuts for recording and note capture"
        case .ai:
            return "Providers, prompts, and vibe mode controls"
        case .update:
            return "Automatic updates and manual update checks"
        case .about:
            return "App info, acknowledgments, support, and logs"
        }
    }

    private var searchKeywords: [String] {
        switch self {
        case .general:
            return [
                "output", "clipboard", "direct insert", "space", "microphone", "audio",
                "input", "floating indicator", "dictionary", "launch at login", "dock",
                "mute", "pause media", "reset", "language", "locale", "transcription language",
                "interface language"
            ]
        case .theme:
            return [
                "appearance", "theme", "light", "dark", "system", "preset", "palette"
            ]
        case .hotkeys:
            return [
                "shortcut", "toggle recording", "push to talk", "copy last transcript",
                "note capture", "keyboard"
            ]
        case .ai:
            return [
                "provider", "api key", "endpoint", "prompt", "preset", "vibe mode",
                "clipboard context", "ui context", "model", "enhancement"
            ]
        case .update:
            return ["updates", "automatic updates", "check now", "version"]
        case .about:
            return ["support", "logs", "github", "license", "system info", "version"]
        }
    }

    func matches(_ searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        let searchableText = ([rawValue, subtitle] + searchKeywords)
            .joined(separator: " ")
            .lowercased()
        return searchableText.contains(query)
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
        .themeRefresh()
    }
}

struct SettingsContainerView: View {
    @ObservedObject var settings: SettingsStore
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
        SettingsTab.allCases.filter { $0.matches(searchText) }
    }

    var body: some View {
        MainContentPageLayout(scrollContent: true, headerBottomPadding: AppTheme.Spacing.lg) {
            fixedHeader
        } content: {
            scrollableContent
        }
        .onChange(of: initialTab) { _, newValue in
            selectedTab = newValue
        }
        .onChange(of: searchText) { _, _ in
            guard let firstVisibleTab = filteredTabs.first else { return }
            if !filteredTabs.contains(selectedTab) {
                selectedTab = firstVisibleTab
            }
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
                tabsBar

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text(selectedTab.rawValue)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(selectedTab.subtitle)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Divider()
                    .background(AppColors.divider)

                Group {
                    switch selectedTab {
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
                Text("Settings")
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Search settings or jump between sections without leaving the main workspace.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }

            HStack(alignment: .center, spacing: AppTheme.Spacing.lg) {
                searchField

                if !searchText.isEmpty {
                    Text("\(filteredTabs.count) match\(filteredTabs.count == 1 ? "" : "es")")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
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

            TextField("Search settings", text: $searchText)
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
                Text("No settings found")
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Try searching for terms like hotkeys, microphone, updates, or vibe mode.")
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
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: tab.systemIcon)
                    .font(.system(size: 13, weight: .semibold))

                Text(tab.rawValue)
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

private extension SettingsTab {
    var accessibilityIdentifier: String {
        let slug = rawValue
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return "settings.tab.\(slug)"
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
