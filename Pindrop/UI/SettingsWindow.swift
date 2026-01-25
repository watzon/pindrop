//
//  SettingsWindow.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct SettingsWindow: View {
    @StateObject private var settings = SettingsStore()
    
    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)
            
            HotkeysSettingsView(settings: settings)
                .tabItem {
                    Label("Hotkeys", systemImage: "keyboard")
                }
                .tag(1)
            
            ModelsSettingsView(settings: settings)
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }
                .tag(2)
            
            AIEnhancementSettingsView(settings: settings)
                .tabItem {
                    Label("AI Enhancement", systemImage: "sparkles")
                }
                .tag(3)
        }
        .frame(minWidth: 550, minHeight: 450)
        .padding()
    }
}

#Preview {
    SettingsWindow()
}
