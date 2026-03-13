//
//  SettingsWindow.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case hotkeys = "Hotkeys"
    case models = "Models"
    case ai = "AI Enhancement"
    case update = "Update"
    case about = "About"

    var id: String { rawValue }

    var systemIcon: String {
        switch self {
        case .general: return "gear"
        case .hotkeys: return "keyboard"
        case .models: return "cpu"
        case .ai: return "sparkles"
        case .update: return "arrow.triangle.2.circlepath"
        case .about: return "info.circle"
        }
    }
}

struct SettingsWindow: View {
    @ObservedObject var settings: SettingsStore
    @State private var selectedTab: SettingsTab
    
    var initialTab: SettingsTab = .general
    
    init(settings: SettingsStore, initialTab: SettingsTab = .general) {
        self.settings = settings
        self.initialTab = initialTab
        self._selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack {
            AppColors.windowBackground
                .ignoresSafeArea()

            HStack(spacing: AppTheme.Window.sidebarContentGap) {
                SettingsSidebar(
                    selectedTab: selectedTab,
                    onSelect: selectTab
                )
                .frame(width: AppTheme.Window.settingsSidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, AppTheme.Window.sidebarTopInset)

                detailPanel
            }
            .ignoresSafeArea()
        }
        .frame(
            minWidth: AppTheme.Window.settingsMinWidth,
            minHeight: AppTheme.Window.settingsMinHeight
        )
    }

    private func selectTab(_ tab: SettingsTab) {
        withAnimation(AppTheme.Animation.fast) {
            selectedTab = tab
        }
    }
    
    private var detailPanel: some View {
        let panelShape = UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: AppTheme.Window.panelCornerRadius / 2,
                bottomLeading: AppTheme.Window.panelCornerRadius / 2,
                bottomTrailing: 0,
                topTrailing: 0
            ),
            style: .continuous
        )

        return detailContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                panelShape
                    .fill(AppColors.contentBackground)
            )
            .clipShape(panelShape)
            .hairlineBorder(panelShape, style: AppColors.border.opacity(0.8))
            .layoutPriority(1)
            .zIndex(1)
    }

    @ViewBuilder
    private var detailContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                headerView(for: selectedTab)
                    .padding(.horizontal, AppTheme.Spacing.xxl)
                    .padding(.top, AppTheme.Window.mainContentTopInset)
                    .padding(.bottom, AppTheme.Spacing.lg)
                
                Group {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsView(settings: settings)
                    case .hotkeys:
                        HotkeysSettingsView(settings: settings)
                    case .models:
                        ModelsSettingsView(settings: settings)
                    case .ai:
                        AIEnhancementSettingsView(settings: settings)
                    case .update:
                        UpdateSettingsView()
                    case .about:
                        AboutSettingsView()
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
    }
    
    private func headerView(for tab: SettingsTab) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(tab.rawValue)
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColors.textPrimary)
            
            Text(headerSubtitle(for: tab))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func headerSubtitle(for tab: SettingsTab) -> String {
        switch tab {
        case .general: return "Output preferences and interface options"
        case .hotkeys: return "Configure keyboard shortcuts"
        case .models: return "Manage Whisper transcription models"
        case .ai: return "Configure AI-powered text enhancement"
        case .update: return "Check for application updates"
        case .about: return "App information and acknowledgments"
        }
    }

}

private struct SettingsSidebar: View {
    let selectedTab: SettingsTab
    let onSelect: (SettingsTab) -> Void

    @State private var hoveredTab: SettingsTab?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Settings")
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, AppTheme.Spacing.lg)
            .padding(.trailing, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.lg)

            VStack(spacing: AppTheme.Spacing.xs) {
                ForEach(SettingsTab.allCases) { tab in
                    settingsTabItem(tab)
                }
            }
            .padding(.leading, AppTheme.Spacing.md)
            .padding(.trailing, AppTheme.Spacing.xs)

            Spacer()
        }
    }

    private func settingsTabItem(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        let isHovered = hoveredTab == tab

        return Button {
            onSelect(tab)
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: tab.systemIcon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)

                Text(tab.rawValue)
                    .font(AppTypography.body)

                Spacer()
            }
            .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
            .sidebarItemStyle(isSelected: isSelected, isHovered: isHovered)
        }
        .buttonStyle(.plain)
        // Keep hover state local so the active settings pane is not rebuilt on every mouse move.
        .onHover { hovering in
            hoveredTab = hovering ? tab : nil
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
