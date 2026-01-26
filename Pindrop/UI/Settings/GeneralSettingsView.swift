//
//  GeneralSettingsView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @State private var showingResetConfirmation = false
    
    var body: some View {
        VStack(spacing: 20) {
            outputSection
            interfaceSection
            resetSection
        }
    }
    
    private var outputSection: some View {
        SettingsCard(title: "Output", icon: "doc.on.clipboard") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(OutputOption.allCases) { option in
                    OutputOptionRow(
                        option: option,
                        isSelected: settings.outputMode == option.rawValue,
                        onSelect: { settings.outputMode = option.rawValue }
                    )
                }
            }
        }
    }
    
    private var interfaceSection: some View {
        SettingsCard(title: "Interface", icon: "macwindow") {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show in Dock")
                            .font(.body)
                        Text("Display Pindrop icon in the Dock when running")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $settings.showInDock)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                
                Divider()
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Floating indicator")
                            .font(.body)
                        Text("Shows recording status in a small overlay window")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $settings.floatingIndicatorEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
    }
    
    private var resetSection: some View {
        SettingsCard(title: "Reset", icon: "arrow.counterclockwise") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reset all settings")
                        .font(.body)
                    Text("Clears preferences and restarts onboarding")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Text("Reset")
                }
                .buttonStyle(.bordered)
            }
        }
        .alert("Reset All Settings?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                settings.resetAllSettings()
                NSApplication.shared.terminate(nil)
            }
        } message: {
            Text("This will clear all your settings, including API keys, hotkeys, and model preferences. The app will quit and show onboarding again on next launch.")
        }
    }
}

enum OutputOption: String, CaseIterable, Identifiable {
    case clipboard = "clipboard"
    case directInsert = "directInsert"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .clipboard: return "Clipboard"
        case .directInsert: return "Direct Insert"
        }
    }
    
    var description: String {
        switch self {
        case .clipboard: return "Copy text to clipboard after transcription"
        case .directInsert: return "Insert text directly into the active app"
        }
    }
    
    var icon: Icon {
        switch self {
        case .clipboard: return .clipboard
        case .directInsert: return .textCursor
        }
    }
}

struct OutputOptionRow: View {
    let option: OutputOption
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 12, height: 12)
                    }
                }
                
                IconView(icon: option.icon, size: 16)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(option.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    GeneralSettingsView(settings: SettingsStore())
        .padding()
        .frame(width: 500)
}
