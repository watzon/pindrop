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

    private var modelChoices: [ModelManager.WhisperModel] {
        modelManager.availableModels
            .filter { $0.availability == .available }
            .sorted { lhs, rhs in
                if lhs.name == selectedModelName { return true }
                if rhs.name == selectedModelName { return false }
                let lhsRecommended = ModelManager.recommendedModelNameSet.contains(lhs.name)
                let rhsRecommended = ModelManager.recommendedModelNameSet.contains(rhs.name)
                if lhsRecommended != rhsRecommended { return lhsRecommended }
                return lhs.sizeInMB < rhs.sizeInMB
            }
            .prefix(2)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(localized("Choose a Model", locale: locale))
                .font(OnboardingType.stepHeading)
                .tracking(-0.42)
                .foregroundStyle(AppColors.textPrimary)

            Text(localized("Smaller models are faster but less accurate.\nStart with Base for the best balance.", locale: locale))
                .font(OnboardingType.stepSubtitle)
                .lineSpacing(3)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            HStack(spacing: 12) {
                ForEach(modelChoices) { model in
                    ModelCard(
                        model: model,
                        isSelected: selectedModelName == model.name,
                        isDownloaded: modelManager.isModelDownloaded(model.name),
                        isRecommended: ModelManager.recommendedModelNameSet.contains(model.name),
                        onSelect: { selectedModelName = model.name }
                    )
                }
            }
            .frame(width: 560)
            .padding(.top, 28)

            OnboardingPrimaryButton(
                title: modelManager.isModelDownloaded(selectedModelName)
                    ? localized("Continue", locale: locale)
                    : localized("Download & Continue", locale: locale),
                icon: modelManager.isModelDownloaded(selectedModelName) ? nil : .download,
                action: onContinue
            )
            .padding(.top, 28)
        }
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    IconView(icon: .waveform, size: 15)
                        .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)

                    Text(model.displayName)
                        .font(OnboardingType.primaryButton)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()
                    selectionIndicator
                }

                Text(modelDescription)
                    .font(AppTypography.captionLarge)
                    .lineSpacing(2)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected && isRecommended {
                    Text(localized("Recommended", locale: locale).uppercased(with: locale))
                        .font(AppTypography.badge)
                        .foregroundStyle(AppColors.accent)
                } else {
                    Spacer(minLength: 14)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(AppColors.contentBackground, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? AppColors.accent : AppColors.border, lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var modelDescription: String {
        let speed = speedLabel(for: model.sizeInMB)
        let accuracy = accuracyLabel(for: model.sizeInMB)
        return "\(formatSize(model.sizeInMB)) · \(speed) · \(accuracy)"
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .fill(isSelected ? AppColors.accent : .clear)
                .frame(width: 15, height: 15)
                .overlay {
                    Circle().strokeBorder(isSelected ? AppColors.accent : AppColors.border, lineWidth: 1.5)
                }
            if isSelected {
                IconView(icon: .check, size: 9)
                    .foregroundStyle(AppColors.contentBackground)
            }
        }
    }

    private func formatSize(_ mb: Int) -> String {
        mb >= 1000 ? String(format: "%.1f GB", Double(mb) / 1000.0) : "\(mb) MB"
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
        .frame(width: 760, height: 500)
        .background(AppColors.windowBackground)
    }
}

final class PreviewModelManagerSelection: ModelManager {
    override init() {}
}
#endif
