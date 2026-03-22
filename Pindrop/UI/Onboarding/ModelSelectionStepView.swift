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

    @Environment(\.locale) private var locale

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
                            isRecommended: ModelManager.recommendedModelNameSet.contains(model.name),
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
            Text(localized("Choose a Model", locale: locale))
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text(localized("Smaller models are faster but less accurate.\nStart with Base for the best balance.", locale: locale))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    private var continueButton: some View {
        Button(action: onContinue) {
            HStack {
                Text(modelManager.isModelDownloaded(selectedModelName)
                    ? localized("Continue", locale: locale)
                    : localized("Download & Continue", locale: locale))
                if !modelManager.isModelDownloaded(selectedModelName) {
                    IconView(icon: .download, size: 16)
                }
            }
            .font(.headline)
            .frame(maxWidth: 220)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 40)
    }
}

struct ModelCard: View {
    @Environment(\.locale) private var locale

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
                            Text(localized("Recommended", locale: locale))
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(AppColors.accent.opacity(0.2))
                                .foregroundStyle(AppColors.accent)
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
                            .fill(isSelected ? AppColors.accent.opacity(0.1) : Color.clear)
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? AppColors.accent : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? AppColors.accent : Color.secondary.opacity(0.3), lineWidth: 2)
                .frame(width: 22, height: 22)

            if isSelected {
                Circle()
                    .fill(AppColors.accent)
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
        case 0..<100: return localized("Very Fast", locale: locale)
        case 100..<300: return localized("Fast", locale: locale)
        case 300..<600: return localized("Medium", locale: locale)
        case 600..<1500: return localized("Slower", locale: locale)
        default: return localized("Slowest", locale: locale)
        }
    }

    private func accuracyLabel(for sizeMB: Int) -> String {
        switch sizeMB {
        case 0..<100: return localized("Good", locale: locale)
        case 100..<300: return localized("Better", locale: locale)
        case 300..<600: return localized("Great", locale: locale)
        case 600..<1500: return localized("Excellent", locale: locale)
        default: return localized("Best", locale: locale)
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
