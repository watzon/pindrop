//
//  HotkeySetupStepView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct HotkeySetupStepView: View {
    @ObservedObject var settings: SettingsStore
    let onContinue: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            headerSection
            
            VStack(spacing: 16) {
                hotkeyCard(
                    title: "Toggle Recording",
                    description: "Press once to start, again to stop",
                    hotkey: settings.toggleHotkey,
                    icon: .record
                )
                
                hotkeyCard(
                    title: "Push-to-Talk",
                    description: "Hold to record, release to transcribe",
                    hotkey: settings.pushToTalkHotkey,
                    icon: .hand
                )
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            infoSection
            
            actionButtons
        }
        .padding(.vertical, 24)
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            IconView(icon: .keyboard, size: 40)
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 8)
            
            Text("Keyboard Shortcuts")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            
            Text("Your hotkeys are ready to use.\nYou can customize them later in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }
    
    private func hotkeyCard(title: String, description: String, hotkey: String, icon: Icon) -> some View {
        HStack(spacing: 16) {
            IconView(icon: icon, size: 24)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(.accentColor.opacity(0.2)), in: .circle)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(hotkey.isEmpty ? "Not Set" : hotkey)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .rect(cornerRadius: 8))
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
    
    private var infoSection: some View {
        HStack(spacing: 12) {
            IconView(icon: .info, size: 16)
                .foregroundStyle(.secondary)
            
            Text("You can change these anytime from the menu bar → Settings → Hotkeys")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 40)
    }
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button("Skip for Now", action: onSkip)
                .buttonStyle(.glass)
            
            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: 180)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(.horizontal, 40)
    }
}

#if DEBUG
struct HotkeySetupStepView_Previews: PreviewProvider {
    static var previews: some View {
        HotkeySetupStepView(
            settings: SettingsStore(),
            onContinue: {},
            onSkip: {}
        )
        .frame(width: 800, height: 600)
    }
}
#endif
