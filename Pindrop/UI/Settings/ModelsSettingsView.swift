//
//  ModelsSettingsView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//
//  Models page (U7 scorched-earth restyle, spec §12) — main-window Models tab.
//

import SwiftUI

struct ModelsSettingsView: View {
    @ObservedObject var settings: SettingsStore
    let modelManager: ModelManager
    @Environment(\.locale) private var locale
    @State private var downloadingModel: String?
    @State private var switchingToModel: String?
    @State private var activeModelName: String?
    @State private var errorMessage: String?

    /// Speech-to-text models shown on the page: recommended for language + any downloaded + active.
    private var speechModels: [ModelManager.WhisperModel] {
        let recommended = modelManager.recommendedModels(for: settings.selectedAppLanguage)
        var seen = Set(recommended.map(\.name))
        var result = recommended

        for model in modelManager.availableModels where model.availability == .available {
            let isDownloaded = modelManager.isModelDownloaded(model.name)
            let isActive = (activeModelName ?? settings.selectedModel) == model.name
            let isSelected = settings.selectedModel == model.name
            if (isDownloaded || isActive || isSelected) && !seen.contains(model.name) {
                seen.insert(model.name)
                result.append(model)
            }
        }

        // Always surface the current default even if not recommended.
        if let selected = modelManager.availableModels.first(where: { $0.name == settings.selectedModel }),
           !seen.contains(selected.name) {
            result.insert(selected, at: 0)
        }

        return result
    }

    /// On-device helpers: existing feature models (no deferred text-corrector row).
    private var helperFeatures: [FeatureModelType] {
        Array(FeatureModelType.allCases)
    }

    private var diskTotalText: String {
        let speechInstalled = modelManager.availableModels.map {
            (isInstalled: modelManager.isModelDownloaded($0.name), sizeInMB: $0.sizeInMB)
        }
        let features = FeatureModelType.allCases.map {
            (isInstalled: modelManager.isFeatureModelDownloaded($0), sizeInMB: $0.sizeInMB)
        }
        return ModelsDiskTotal.formattedTotal(
            speechModels: speechInstalled,
            featureModels: features
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 40)
                .padding(.top, 40)
                .padding(.bottom, 18)
                .background(AppColors.contentBackground)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    speechToTextSection
                    helpersSection
                    privacyFootnote
                        .padding(.top, 20)
                        .padding(.horizontal, 20)

                    if let errorMessage {
                        errorBanner(message: errorMessage)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }

                    Color.clear.frame(height: 32)
                }
                .padding(.bottom, 24)
            }
            .background(AppColors.contentBackground)
        }
        .background(AppColors.contentBackground)
        .task {
            await modelManager.refreshDownloadedModels()
            await modelManager.refreshDownloadedFeatureModels()
        }
        .onAppear {
            if activeModelName == nil {
                activeModelName = settings.selectedModel
            }
            NotificationCenter.default.post(name: .requestActiveModel, object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .modelActiveChanged)) { notification in
            if let modelName = notification.userInfo?["modelName"] as? String {
                activeModelName = modelName
                switchingToModel = nil
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        PageHeader(
            title: localized("Models", locale: locale),
            meta: localized("Everything runs on this Mac", locale: locale)
        ) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(diskTotalText)
                    .font(FontLoader.font(family: .jetbrainsMono, size: 15, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                Text(localized("ON DISK", locale: locale))
                    .font(AppTypography.sectionHeader)
                    .tracking(0.6)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    // MARK: - SPEECH TO TEXT

    private var speechToTextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: localized("Speech to text", locale: locale),
                isFirst: true
            )
            .padding(.horizontal, 20)

            if speechModels.isEmpty {
                Text(localized("No models available", locale: locale))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            } else {
                ForEach(speechModels) { model in
                    modelRowCard(model)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private func modelRowCard(_ model: ModelManager.WhisperModel) -> some View {
        let isActive = (activeModelName ?? settings.selectedModel) == model.name
        let isDownloaded = modelManager.isModelDownloaded(model.name)
            || (!model.provider.isLocal && model.availability == .available)
            || model.provider == .appleSpeech
        let isDownloading = downloadingModel == model.name
        let isSwitching = switchingToModel == model.name
        let isComingSoon = model.availability == .comingSoon

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .font(FontLoader.font(family: .inter, size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    if isActive {
                        activeBadge
                    }
                }

                if !model.description.isEmpty {
                    Text(model.description)
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                if model.sizeInMB > 0 {
                    Text(model.formattedSize)
                        .font(AppTypography.monoTime)
                        .foregroundStyle(AppColors.textSecondary)
                }

                if isComingSoon {
                    Text(localized("Coming Soon", locale: locale))
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textTertiary)
                } else if isDownloading {
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView(value: modelManager.downloadProgress)
                            .frame(width: 88)
                        Text("\(Int(modelManager.downloadProgress * 100))%")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                } else if isSwitching {
                    ProgressView()
                        .controlSize(.small)
                } else if isDownloaded {
                    Text(localized("Installed", locale: locale))
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textTertiary)
                } else {
                    downloadButton { downloadModel(model) }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? AppColors.windowBackground : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isActive ? AppColors.accent : AppColors.border,
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isDownloaded && !isActive ? .isButton : [])
        .accessibilityAction {
            if isDownloaded && !isActive && !isComingSoon && !isSwitching {
                switchModel(model)
            }
        }
        .keyboardFocusRing(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onKeyPress(.return) {
            guard isDownloaded && !isActive && !isComingSoon && !isSwitching else {
                return .ignored
            }
            switchModel(model)
            return .handled
        }
        .onTapGesture {
            if isDownloaded && !isActive && !isComingSoon && !isSwitching {
                switchModel(model)
            }
        }
        .contextMenu {
            if isDownloaded && !isActive {
                Button(localized("Switch to Model", locale: locale)) {
                    switchModel(model)
                }
            }
            if isDownloaded && settings.selectedModel != model.name {
                Button(localized("Set as Default", locale: locale)) {
                    settings.selectedModel = model.name
                }
            }
            if isDownloaded && model.provider.isLocal && model.provider != .appleSpeech {
                Divider()
                Button(localized("Delete Model", locale: locale), role: .destructive) {
                    deleteModel(model)
                }
            }
        }
    }

    private var activeBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(AppColors.accent)
                .frame(width: 6, height: 6)
            Text(localized("Active", locale: locale))
                .font(AppTypography.badge)
                .foregroundStyle(AppColors.accent)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 9)
        .background(
            Capsule().fill(AppColors.accentBackground)
        )
    }

    private func downloadButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 11, weight: .medium))
                Text(localized("Download", locale: locale))
                    .font(AppTypography.label)
            }
            .foregroundStyle(AppColors.textPrimary)
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .keyboardFocusRing(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - ON-DEVICE HELPERS

    private var helpersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: localized("On-device helpers", locale: locale),
                isFirst: false
            )
            .padding(.horizontal, 20)

            // Speaker diarization is the design-featured helper; also show VAD.
            // Streaming stays available for existing users (no text-corrector row).
            ForEach(helperFeatures, id: \.id) { feature in
                featureRowCard(feature)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
        .padding(.top, 8)
    }

    private func featureRowCard(_ feature: FeatureModelType) -> some View {
        let isDownloaded = modelManager.isFeatureModelDownloaded(feature)
        let isEnabled = settings.isFeatureEnabled(feature)
        let isActive = isDownloaded && isEnabled
        let isDownloading = modelManager.currentDownloadingFeature == feature

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(feature.displayName)
                        .font(FontLoader.font(family: .inter, size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    if isActive {
                        activeBadge
                    }
                }

                Text(feature.description)
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text(feature.formattedSize)
                    .font(AppTypography.monoTime)
                    .foregroundStyle(AppColors.textSecondary)

                if isDownloading {
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView(value: modelManager.featureDownloadProgress)
                            .frame(width: 88)
                        Text("\(Int(modelManager.featureDownloadProgress * 100))%")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                } else if isDownloaded {
                    Toggle("", isOn: Binding(
                        get: { settings.isFeatureEnabled(feature) },
                        set: { enabled in toggleFeature(feature, enabled: enabled) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .accessibilityLabel(feature.displayName)
                } else {
                    downloadButton { downloadFeatureModel(feature) }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? AppColors.windowBackground : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isActive ? AppColors.accent : AppColors.border,
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .contain)
    }

    private var privacyFootnote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppColors.textTertiary)
            Text(localized("Models never leave this Mac. Audio is processed locally unless you choose a cloud provider in Settings → AI.", locale: locale))
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.warning)

            Text(message)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Button(localized("Dismiss", locale: locale)) {
                errorMessage = nil
            }
            .buttonStyle(.plain)
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppColors.warningBackground)
        )
    }

    // MARK: - Actions

    private func toggleFeature(_ type: FeatureModelType, enabled: Bool) {
        if enabled && !modelManager.isFeatureModelDownloaded(type) {
            downloadFeatureModel(type)
        } else {
            settings.setFeatureEnabled(type, enabled: enabled)
        }
    }

    private func downloadFeatureModel(_ type: FeatureModelType) {
        errorMessage = nil
        Task {
            do {
                try await modelManager.downloadFeatureModel(
                    type,
                    streamingChunkProfile: settings.streamingChunkProfile
                )
                // Offline diarization only becomes installable once complete assets pass
                // the readiness helper (required CoreML bundles + plda-parameters.json).
                if type == .diarization {
                    await modelManager.refreshDownloadedFeatureModels()
                    guard modelManager.isOfflineDiarizationReady() else {
                        errorMessage = "Speaker diarization model is incomplete. Try downloading again."
                        return
                    }
                }
                settings.setFeatureEnabled(type, enabled: true)
            } catch {
                errorMessage = "Failed to download \(type.displayName): \(error.localizedDescription)"
            }
        }
    }

    /// Switches the live session model only — does **not** persist default.
    /// Default is changed exclusively via the context-menu "Set as Default" action.
    private func switchModel(_ model: ModelManager.WhisperModel) {
        guard modelManager.isModelDownloaded(model.name) || model.provider == .appleSpeech || !model.provider.isLocal else { return }
        guard activeModelName != model.name else { return }

        switchingToModel = model.name
        errorMessage = nil

        NotificationCenter.default.post(
            name: .switchModel,
            object: nil,
            userInfo: ["modelName": model.name]
        )
    }

    private func downloadModel(_ model: ModelManager.WhisperModel) {
        downloadingModel = model.name
        errorMessage = nil

        Task {
            do {
                try await modelManager.downloadModel(named: model.name)
                downloadingModel = nil
            } catch {
                errorMessage = "Failed to download \(model.displayName): \(error.localizedDescription)"
                downloadingModel = nil
            }
        }
    }

    private func deleteModel(_ model: ModelManager.WhisperModel) {
        errorMessage = nil
        Task {
            do {
                try await modelManager.deleteModel(named: model.name)
            } catch {
                errorMessage = "Failed to delete \(model.displayName): \(error.localizedDescription)"
            }
        }
    }
}

#Preview("Models page") {
    ModelsSettingsView(settings: SettingsStore(), modelManager: ModelManager())
        .frame(width: 720, height: 640)
        .preferredColorScheme(.light)
}
