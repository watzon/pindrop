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
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .general: return "gear"
        case .hotkeys: return "keyboard"
        case .models: return "cpu"
        case .ai: return "sparkles"
        }
    }
}

struct SettingsWindow: View {
    @StateObject private var settings = SettingsStore()
    @State private var selectedTab: SettingsTab = .general
    
    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 500)
    }
    
    private var sidebar: some View {
        List(SettingsTab.allCases, selection: $selectedTab) { tab in
            Label(tab.rawValue, systemImage: tab.icon)
                .tag(tab)
        }
        .listStyle(.sidebar)
    }
    
    @ViewBuilder
    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerView(for: selectedTab)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                
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
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func headerView(for tab: SettingsTab) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tab.rawValue)
                .font(.system(size: 24, weight: .bold, design: .rounded))
            
            Text(headerSubtitle(for: tab))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func headerSubtitle(for tab: SettingsTab) -> String {
        switch tab {
        case .general: return "Output preferences and interface options"
        case .hotkeys: return "Configure keyboard shortcuts"
        case .models: return "Manage Whisper transcription models"
        case .ai: return "Configure AI-powered text enhancement"
        }
    }
}

#Preview {
    SettingsWindow()
}
