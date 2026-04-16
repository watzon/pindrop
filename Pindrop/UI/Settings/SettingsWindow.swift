//
//  SettingsWindow.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftData
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case theme = "Theme"
    case hotkeys = "Hotkeys"
    case ai = "AI Enhancement"
    case participants = "Participants"
    case mcp = "MCP Server"
    case about = "About"

    var id: String { rawValue }

    func title(locale: Locale) -> String {
        switch self {
        case .general: return localized("General", locale: locale)
        case .theme: return localized("Theme", locale: locale)
        case .hotkeys: return localized("Hotkeys", locale: locale)
        case .ai: return localized("AI Enhancement", locale: locale)
        case .participants: return localized("Participants", locale: locale)
        case .mcp: return localized("MCP Server", locale: locale)
        case .about: return localized("About", locale: locale)
        }
    }

    var systemIcon: String {
        switch self {
        case .general: return "gear"
        case .theme: return "paintbrush"
        case .hotkeys: return "keyboard"
        case .ai: return "sparkles"
        case .participants: return "person.2"
        case .mcp: return "network"
        case .about: return "info.circle"
        }
    }

    var subtitle: String {
        subtitle(locale: .autoupdatingCurrent)
    }

    func subtitle(locale: Locale) -> String {
        switch self {
        case .general:
            return localized("Output, audio, interface, and everyday behavior", locale: locale)
        case .theme:
            return localized("Light, dark, and curated palette presets", locale: locale)
        case .hotkeys:
            return localized("Configure keyboard shortcuts for recording and note capture", locale: locale)
        case .ai:
            return localized("Providers, prompts, and vibe mode controls", locale: locale)
        case .participants:
            return localized("Learned speaker voices and participant profiles", locale: locale)
        case .mcp:
            return localized("Local HTTP server for AI agent integration", locale: locale)
        case .about:
            return localized("App info, updates, acknowledgments, support, and logs", locale: locale)
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
        case .participants:
            return [
                "speaker", "voice", "participant", "profile", "diarization",
                "rename", "learned", "identity", "recognition"
            ]
        case .mcp:
            return [
                "mcp", "agent", "server", "api", "http", "token", "port", "claude code",
                "cursor", "codex", "opencode", "integration", "automation"
            ]
        case .about:
            return [
                "support", "logs", "github", "license", "system info", "version",
                "updates", "automatic updates", "check now"
            ]
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
                .padding(.top, 32)
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
        SettingsTab.allCases.filter { $0.matches(searchText) }
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
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text(selectedTab.title(locale: locale))
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(selectedTab.subtitle(locale: locale))
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
                    case .participants:
                        ParticipantsSettingsView()
                    case .mcp:
                        MCPSettingsView(settings: settings)
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
        FlowLayout(spacing: AppTheme.Spacing.sm) {
            ForEach(filteredTabs) { tab in
                SettingsTabChip(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    action: { selectTab(tab) }
                )
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
        let slug = rawValue
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return "settings.tab.\(slug)"
    }
}

// MARK: - Participants Settings View

struct ParticipantsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale

    @State private var profiles: [ParticipantProfile] = []
    @State private var editingProfile: ParticipantProfile?
    @State private var editedName = ""
    @State private var showingDeleteAllConfirmation = false
    @State private var errorMessage: String?

    private var identityService: SpeakerIdentityService {
        SpeakerIdentityService(modelContext: modelContext)
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            profilesCard

            if !profiles.isEmpty {
                dangerZoneCard
            }
        }
        .task {
            loadProfiles()
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyStoreDidChange)) { _ in
            loadProfiles()
        }
        .alert(
            localized("Edit", locale: locale),
            isPresented: Binding(
                get: { editingProfile != nil },
                set: { if !$0 { editingProfile = nil } }
            )
        ) {
            TextField("", text: $editedName)
            Button(localized("Cancel", locale: locale), role: .cancel) {
                editingProfile = nil
            }
            Button(localized("Save", locale: locale)) {
                saveEditedProfile()
            }
        }
        .alert(
            localized("Error", locale: locale),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(localized("OK", locale: locale), role: .cancel) {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Profiles Card

    private var profilesCard: some View {
        SettingsCard(
            title: localized("Participants", locale: locale),
            icon: "person.2",
            detail: localized("Learned speaker voices and participant profiles", locale: locale)
        ) {
            if profiles.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                        profileRow(profile)

                        if index < profiles.count - 1 {
                            SettingsDivider()
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AppColors.textTertiary)

            Text(localized("No learned participants yet", locale: locale))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)

            Text(localized("Rename speakers in transcripts to teach Pindrop to recognize voices automatically.", locale: locale))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.lg)
    }

    private func profileRow(_ profile: ParticipantProfile) -> some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)

                if profile.evidenceCount == 0 {
                    Label(
                        localized("Not enough voice data yet", locale: locale),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                } else {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Label(
                            String(format: localized("%d samples", locale: locale), profile.evidenceCount),
                            systemImage: "waveform"
                        )
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)

                        Text("·")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)

                        Text(formattedDuration(profile.totalEvidenceDuration))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: AppTheme.Spacing.xs) {
                Button {
                    editedName = profile.displayName
                    editingProfile = profile
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.borderless)
                .help(localized("Edit", locale: locale))

                Button(role: .destructive) {
                    deleteProfile(profile)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.borderless)
                .help(localized("Delete", locale: locale))
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    // MARK: - Danger Zone

    private var dangerZoneCard: some View {
        SettingsCard(
            title: localized("Reset", locale: locale),
            icon: "arrow.counterclockwise",
            detail: localized("Remove all learned participant data", locale: locale)
        ) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("Delete all participants", locale: locale))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(localized("This removes all learned voice profiles and training data. This cannot be undone.", locale: locale))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button(role: .destructive) {
                    showingDeleteAllConfirmation = true
                } label: {
                    Text(localized("Delete", locale: locale))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .confirmationDialog(
                localized("Delete all participants", locale: locale),
                isPresented: $showingDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button(localized("Delete", locale: locale), role: .destructive) {
                    deleteAllProfiles()
                }
                Button(localized("Cancel", locale: locale), role: .cancel) {}
            } message: {
                Text(localized("This removes all learned voice profiles and training data. This cannot be undone.", locale: locale))
            }
        }
    }

    // MARK: - Actions

    private func loadProfiles() {
        do {
            profiles = try identityService.fetchAllProfiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveEditedProfile() {
        guard let profile = editingProfile else { return }
        do {
            try identityService.renameProfile(profile, to: editedName)
            loadProfiles()
        } catch {
            errorMessage = error.localizedDescription
        }
        editingProfile = nil
    }

    private func deleteProfile(_ profile: ParticipantProfile) {
        do {
            try identityService.deleteProfile(profile)
            loadProfiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAllProfiles() {
        do {
            try identityService.deleteAllProfiles()
            loadProfiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Formatting

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        } else if seconds < 3600 {
            let minutes = Int(seconds) / 60
            let secs = Int(seconds) % 60
            return "\(minutes)m \(secs)s"
        } else {
            let hours = Int(seconds) / 3600
            let minutes = (Int(seconds) % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
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
