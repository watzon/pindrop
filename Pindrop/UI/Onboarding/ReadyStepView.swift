//
//  ReadyStepView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct ReadyStepView: View {
    @ObservedObject var settings: SettingsStore
    var modelManager: ModelManager
    let selectedModelName: String
    let onComplete: () -> Void
    
    @State private var showConfetti = false
    
    private var selectedModel: ModelManager.WhisperModel? {
        modelManager.availableModels.first { $0.name == selectedModelName }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            successIcon
            
            VStack(spacing: 8) {
                Text("You're All Set!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Text("Pindrop is ready to use.\nClick the menu bar icon to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            summarySection
            
            Spacer()
            
            Button(action: onComplete) {
                HStack {
                    Text("Start Using Pindrop")
                    IconView(icon: .arrowRight, size: 16)
                }
                .font(.headline)
                .frame(maxWidth: 240)
                .padding(.vertical, 14)
            }
            .buttonStyle(.glassProminent)
            
            Spacer()
        }
        .padding(40)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.5).delay(0.2)) {
                showConfetti = true
            }
        }
    }
    
    private var successIcon: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.green, .green.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 100, height: 100)
            
            IconView(icon: .check, size: 48)
                .foregroundStyle(.white)
        }
        .glassEffect(.regular.tint(.green.opacity(0.2)), in: .circle)
        .scaleEffect(showConfetti ? 1.0 : 0.5)
        .opacity(showConfetti ? 1.0 : 0)
    }
    
    private var summarySection: some View {
        VStack(spacing: 12) {
            summaryRow(icon: .cpu, label: "Model", value: selectedModel?.displayName ?? "Base")
            summaryRow(icon: .keyboard, label: "Toggle", value: settings.toggleHotkey.isEmpty ? "Not set" : settings.toggleHotkey)
            summaryRow(icon: .sparkles, label: "AI Enhancement", value: settings.aiEnhancementEnabled ? "Enabled" : "Disabled")
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
    
    private func summaryRow(icon: Icon, label: String, value: String) -> some View {
        HStack {
            IconView(icon: icon, size: 16)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            
            Text(label)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#if DEBUG
struct ReadyStepView_Previews: PreviewProvider {
    static var previews: some View {
        ReadyStepView(
            settings: SettingsStore(),
            modelManager: PreviewModelManagerReady(),
            selectedModelName: "openai_whisper-base.en",
            onComplete: {}
        )
        .frame(width: 800, height: 600)
    }
}

final class PreviewModelManagerReady: ModelManager {
    override init() {
        // Skip async initialization to avoid launching WhisperKit in preview
    }
}
#endif
