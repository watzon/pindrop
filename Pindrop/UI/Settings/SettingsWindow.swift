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
    case dictionary = "Dictionary"
    case update = "Update"
    case about = "About"

    var id: String { rawValue }

    var systemIcon: String {
        switch self {
        case .general: return "gear"
        case .hotkeys: return "keyboard"
        case .models: return "cpu"
        case .ai: return "sparkles"
        case .dictionary: return "text.book.closed"
        case .update: return "arrow.triangle.2.circlepath"
        case .about: return "info.circle"
        }
    }
}

struct SettingsWindow: View {
    @ObservedObject var settings: SettingsStore
    @State private var selectedTab: SettingsTab
    @State private var hoveredTab: SettingsTab? = nil
    
    var initialTab: SettingsTab = .general
    
    init(settings: SettingsStore, initialTab: SettingsTab = .general) {
        self.settings = settings
        self.initialTab = initialTab
        self._selectedTab = State(initialValue: initialTab)
    }
    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 250)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: AppTheme.Window.settingsMinWidth, minHeight: AppTheme.Window.settingsMinHeight)
        .background(AppColors.windowBackground)
    }
    
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Settings")
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.sm)
            
            VStack(spacing: AppTheme.Spacing.xs) {
                ForEach(SettingsTab.allCases) { tab in
                    settingsTabItem(tab)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            
            Spacer()
        }
        .background(AppColors.sidebarBackground)
    }
    
    private func settingsTabItem(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        let isHovered = hoveredTab == tab
        
        return Button {
            withAnimation(AppTheme.Animation.fast) {
                selectedTab = tab
            }
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
        .onHover { hovering in
            hoveredTab = hovering ? tab : nil
        }
    }
    
    @ViewBuilder
    private var detailContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                headerView(for: selectedTab)
                    .padding(.horizontal, AppTheme.Spacing.xxl)
                    .padding(.top, AppTheme.Spacing.xxl)
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
                    case .dictionary:
                        DictionarySettingsView()
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
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl)
                .fill(AppColors.contentBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl))
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
        case .dictionary: return "Manage word replacements and vocabulary"
        case .update: return "Check for application updates"
        case .about: return "App information and acknowledgments"
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
