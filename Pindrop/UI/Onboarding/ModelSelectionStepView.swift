//
//  ModelSelectionStepView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct ModelSelectionStepView: View {
    var modelManager: ModelManager
    @Binding var selectedModelName: String
    let onContinue: () -> Void
    
    private let recommendedModels = ["openai_whisper-tiny.en", "openai_whisper-base.en", "openai_whisper-small.en"]
    
    var body: some View {
        VStack(spacing: 24) {
            headerSection
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(modelManager.availableModels.filter { $0.availability == .available }) { model in
                        ModelCard(
                            model: model,
                            isSelected: selectedModelName == model.name,
                            isDownloaded: modelManager.isModelDownloaded(model.name),
                            isRecommended: model.name == "openai_whisper-base.en",
                            onSelect: { selectedModelName = model.name }
                        )
                    }
                }
                .padding(.horizontal, 40)
            }
            
            continueButton
        }
        .padding(.vertical, 24)
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Choose a Model")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            
            Text("Smaller models are faster but less accurate.\nStart with Base for the best balance.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }
    
    private var continueButton: some View {
        Button(action: onContinue) {
            HStack {
                Text(modelManager.isModelDownloaded(selectedModelName) ? "Continue" : "Download & Continue")
                if !modelManager.isModelDownloaded(selectedModelName) {
                    IconView(icon: .download, size: 16)
                }
            }
            .font(.headline)
            .frame(maxWidth: 220)
            .padding(.vertical, 12)
        }
        .buttonStyle(.glassProminent)
        .padding(.horizontal, 40)
    }
}

struct ModelCard: View {
    let model: ModelManager.WhisperModel
    let isSelected: Bool
    let isDownloaded: Bool
    let isRecommended: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                selectionIndicator
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .font(.headline)
                        
                        if isRecommended {
                            Text("Recommended")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.2))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(.capsule)
                        }
                        
                        if isDownloaded {
                            IconView(icon: .circleCheck, size: 14)
                                .foregroundStyle(.green)
                        }
                    }
                    
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            IconView(icon: .hardDrive, size: 12)
                            Text(formatSize(model.sizeInMB))
                        }
                        HStack(spacing: 4) {
                            IconView(icon: .zap, size: 12)
                            Text(speedLabel(for: model.sizeInMB))
                        }
                        HStack(spacing: 4) {
                            IconView(icon: .target, size: 12)
                            Text(accuracyLabel(for: model.sizeInMB))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
    
    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
                .frame(width: 22, height: 22)
            
            if isSelected {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 14, height: 14)
            }
        }
    }
    
    private func formatSize(_ mb: Int) -> String {
        if mb >= 1000 {
            return String(format: "%.1f GB", Double(mb) / 1000.0)
        }
        return "\(mb) MB"
    }
    
    private func speedLabel(for sizeMB: Int) -> String {
        switch sizeMB {
        case 0..<100: return "Very Fast"
        case 100..<300: return "Fast"
        case 300..<600: return "Medium"
        case 600..<1500: return "Slower"
        default: return "Slowest"
        }
    }
    
    private func accuracyLabel(for sizeMB: Int) -> String {
        switch sizeMB {
        case 0..<100: return "Good"
        case 100..<300: return "Better"
        case 300..<600: return "Great"
        case 600..<1500: return "Excellent"
        default: return "Best"
        }
    }
}

#if DEBUG
struct ModelSelectionStepView_Previews: PreviewProvider {
    @State private static var selectedModelName = "openai_whisper-base.en"
    
    static var previews: some View {
        ModelSelectionStepView(
            modelManager: PreviewModelManagerSelection(),
            selectedModelName: $selectedModelName,
            onContinue: {}
        )
        .frame(width: 800, height: 600)
    }
}

struct ModelCard_Previews: PreviewProvider {
    static var previews: some View {
        ModelCard(
            model: ModelManager.WhisperModel(
                name: "openai_whisper-base.en",
                displayName: "Base",
                sizeInMB: 145
            ),
            isSelected: true,
            isDownloaded: false,
            isRecommended: true,
            onSelect: {}
        )
        .padding()
        .frame(width: 400)
    }
}

final class PreviewModelManagerSelection: ModelManager {
    override init() {
        // Skip async initialization to avoid launching WhisperKit in preview
    }
}
#endif
