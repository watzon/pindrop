//
//  ModelsSettingsView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

private let modelListItemInset: CGFloat = 6

struct ModelsSettingsView: View {
    @ObservedObject var settings: SettingsStore
    let modelManager: ModelManager
    @Environment(\.locale) private var locale
    @State private var downloadingModel: String?
    @State private var switchingToModel: String?
    @State private var activeModelName: String?
    @State private var errorMessage: String?
    @State private var selectedFilter: ModelFilter = .recommended
    @State private var searchText = ""
    @State private var visibleModels: [ModelManager.WhisperModel] = []
    @State private var searchTask: Task<Void, Never>?

    enum ModelFilter: String, CaseIterable {
        case recommended
        case local
        case cloud
        case comingSoon
        case all

        func localizedName(locale: Locale) -> String {
            switch self {
            case .recommended: return localized("Recommended", locale: locale)
            case .local: return localized("Local", locale: locale)
            case .cloud: return localized("Cloud", locale: locale)
            case .comingSoon: return localized("Coming Soon", locale: locale)
            case .all: return localized("All", locale: locale)
            }
        }
        
        func matches(_ model: ModelManager.WhisperModel) -> Bool {
            switch self {
            case .recommended:
                return ModelManager.recommendedModelNameSet.contains(model.name)
            case .all:
                return true
            case .local:
                return model.provider.isLocal && model.availability == .available
            case .cloud:
                return !model.provider.isLocal && model.availability == .available
            case .comingSoon:
                return model.availability == .comingSoon
            }
        }
    }
    
    private var filteredModels: [ModelManager.WhisperModel] {
        switch effectiveFilter {
        case .recommended:
            return recommendedModels
        case .all, .local, .cloud, .comingSoon:
            return modelManager.availableModels.filter { effectiveFilter.matches($0) }
        }
    }

    private var recommendedModels: [ModelManager.WhisperModel] {
        modelManager.recommendedModels(for: settings.selectedAppLanguage)
    }

    private var recommendedModelNameSet: Set<String> {
        Set(recommendedModels.map(\.name))
    }

    private var effectiveFilter: ModelFilter {
        trimmedSearchText.isEmpty ? selectedFilter : .all
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        MainContentPageLayout(scrollContent: true, headerBottomPadding: AppTheme.Spacing.lg) {
            header
        } content: {
            VStack(spacing: 20) {
                currentModelCard
                filterBar
                modelSearchField
                availableModelsCard
                featureModelsCard

                if let errorMessage {
                    errorBanner(message: errorMessage)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            await modelManager.refreshDownloadedModels()
            await modelManager.refreshDownloadedFeatureModels()
            updateVisibleModels(immediately: true)
        }
        .onAppear {
            if activeModelName == nil {
                activeModelName = settings.selectedModel
            }
            NotificationCenter.default.post(name: .requestActiveModel, object: nil)
            updateVisibleModels(immediately: true)
        }
        .onChange(of: selectedFilter) { _, _ in
            updateVisibleModels(immediately: trimmedSearchText.isEmpty)
        }
        .onChange(of: searchText) { _, _ in
            updateVisibleModels(immediately: trimmedSearchText.isEmpty)
        }
        .onChange(of: settings.selectedLanguage) { _, _ in
            updateVisibleModels(immediately: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .modelActiveChanged)) { notification in
            if let modelName = notification.userInfo?["modelName"] as? String {
                activeModelName = modelName
                switchingToModel = nil
            }
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(localized("Models", locale: locale))
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColors.textPrimary)

            Text(localized("Manage local speech models, feature models, and the default engine Pindrop uses for transcription.", locale: locale))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
    
    private var currentModelCard: some View {
        SettingsCard(title: localized("Default Model", locale: locale), icon: "checkmark.circle") {
            if let currentModel = modelManager.availableModels.first(where: { $0.name == settings.selectedModel }) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(currentModel.displayName)
                                .font(.headline)

                            HStack(spacing: 16) {
                                MetadataBadge(
                                    presentation: currentModel.languageBadgePresentation(for: settings.selectedAppLanguage)
                                )

                                if currentModel.sizeInMB > 0 {
                                    MetadataBadge(icon: "internaldrive", text: currentModel.formattedSize)
                                }

                                RatingIndicator(label: localized("Speed", locale: locale), rating: currentModel.speedRating)
                                RatingIndicator(label: localized("Accuracy", locale: locale), rating: currentModel.accuracyRating)
                            }
                        }

                        Spacer()

                        if modelManager.isModelDownloaded(currentModel.name) {
                            HStack(spacing: 4) {
                                IconView(icon: .circleCheck, size: 14)
                                Text(localized("Ready", locale: locale))
                            }
                            .font(.caption)
                            .foregroundStyle(.green)
                        }
                    }

                }
            } else {
                Text(localized("No model selected", locale: locale))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(ModelFilter.allCases, id: \.self) { filter in
                FilterButton(
                    title: filter.localizedName(locale: locale),
                    isSelected: effectiveFilter == filter,
                    action: { selectedFilter = filter }
                )
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }
    
    private var availableModelsCard: some View {
        SettingsCard(title: localized("Available Models", locale: locale), icon: "square.stack.3d.up") {
            LazyVStack(spacing: 0) {
                if visibleModels.isEmpty {
                    emptyModelsState
                        .padding(14)
                } else {
                    ForEach(Array(visibleModels.enumerated()), id: \.element.id) { index, model in
                        ModelSettingsRow(
                            model: model,
                            selectedLanguage: settings.selectedAppLanguage,
                            isDefault: settings.selectedModel == model.name,
                            isActive: activeModelName == model.name,
                            isRecommended: recommendedModelNameSet.contains(model.name),
                            isDownloaded: modelManager.isModelDownloaded(model.name),
                            isDownloading: downloadingModel == model.name,
                            isSwitching: switchingToModel == model.name,
                            downloadProgress: modelManager.downloadProgress,
                            downloadSnapshot: downloadingModel == model.name ? modelManager.downloadSnapshot : nil,
                            onSwitch: { switchModel(model) },
                            onSetDefault: { settings.selectedModel = model.name },
                            onDownload: { downloadModel(model) },
                            onDelete: { deleteModel(model) }
                        )
                        .padding(.horizontal, modelListItemInset)

                        if index < visibleModels.count - 1 {
                            Divider()
                                .padding(.horizontal, modelListItemInset)
                        }
                    }
                }
            }
        }
    }

    private var modelSearchField: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textTertiary)

            TextField(localized("Search models", locale: locale), text: $searchText)
                .textFieldStyle(.plain)
                .font(AppTypography.body)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, 10)
        .frame(maxWidth: 360, alignment: .leading)
        .background(AppColors.surfaceBackground, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md))
        .hairlineBorder(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md),
            style: AppColors.border.opacity(0.8)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyModelsState: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)

            Text(trimmedSearchText.isEmpty
                ? localized("No models available", locale: locale)
                : localized("No models match \"%@\"", locale: locale).replacingOccurrences(of: "%@", with: trimmedSearchText))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var featureModelsCard: some View {
        SettingsCard(title: localized("Feature Models", locale: locale), icon: "puzzlepiece.extension") {
            VStack(spacing: 0) {
                ForEach(Array(FeatureModelType.allCases.enumerated()), id: \.element.id) { index, featureType in
                    FeatureModelRow(
                        featureType: featureType,
                        isDownloaded: modelManager.isFeatureModelDownloaded(featureType),
                        isEnabled: settings.isFeatureEnabled(featureType),
                        aiEnhancementEnabled: settings.aiEnhancementEnabled,
                        isDownloading: modelManager.currentDownloadingFeature == featureType,
                        downloadProgress: modelManager.featureDownloadProgress,
                        onToggle: { enabled in toggleFeature(featureType, enabled: enabled) },
                        onDownload: { downloadFeatureModel(featureType) }
                    )
                    .padding(.horizontal, modelListItemInset)
                    
                    if index < FeatureModelType.allCases.count - 1 {
                        Divider()
                            .padding(.horizontal, modelListItemInset)
                    }
                }
            }
        }
    }
    
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
                try await modelManager.downloadFeatureModel(type)
                settings.setFeatureEnabled(type, enabled: true)
            } catch {
                errorMessage = "Failed to download \(type.displayName): \(error.localizedDescription)"
            }
        }
    }
    
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 12) {
            IconView(icon: .warning, size: 16)
                .foregroundStyle(.orange)

            Text(message)
                .font(.caption)

            Spacer()

            Button(localized("Dismiss", locale: locale)) {
                errorMessage = nil
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private func switchModel(_ model: ModelManager.WhisperModel) {
        guard modelManager.isModelDownloaded(model.name) else { return }
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

    private func updateVisibleModels(immediately: Bool = false) {
        searchTask?.cancel()

        let models = filteredModels
        let query = trimmedSearchText

        searchTask = Task {
            if !immediately && !query.isEmpty {
                try? await Task.sleep(for: .milliseconds(120))
            }

            let filtered = await Task.detached(priority: .userInitiated) {
                filterModels(models, matching: query)
            }.value

            guard !Task.isCancelled else { return }
            visibleModels = filtered
        }
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    isSelected
                        ? AppColors.accent.opacity(0.15)
                        : Color.secondary.opacity(0.1),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}

struct MetadataBadge: View {
    let icon: String
    let text: String
    let tone: ModelManager.LanguageSupport.BadgeTone

    init(icon: String, text: String, tone: ModelManager.LanguageSupport.BadgeTone = .normal) {
        self.icon = icon
        self.text = text
        self.tone = tone
    }

    init(presentation: ModelManager.LanguageSupport.BadgePresentation) {
        self.icon = presentation.iconName
        self.text = presentation.text
        self.tone = presentation.tone
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption.weight(tone == .caution ? .semibold : .regular))
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, tone == .caution ? 8 : 0)
        .padding(.vertical, tone == .caution ? 4 : 0)
        .background(backgroundView)
    }

    private var foregroundColor: Color {
        switch tone {
        case .normal:
            return .secondary
        case .caution:
            return AppColors.warning
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch tone {
        case .normal:
            Color.clear
        case .caution:
            Capsule()
                .fill(AppColors.warningBackground)
        }
    }
}

struct RatingIndicator: View {
    let label: String
    let rating: Double
    
    private var filledDots: Int {
        Int((rating / 10.0) * 5.0).clamped(to: 0...5)
    }
    
    private var ratingColor: Color {
        switch rating {
        case 8.5...: return .green
        case 7.0..<8.5: return .yellow
        case 5.0..<7.0: return .orange
        default: return .red
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(index < filledDots ? ratingColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            
            Text(String(format: "%.1f", rating))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct ModelSettingsRow: View {
    @Environment(\.locale) private var locale

    let model: ModelManager.WhisperModel
    let selectedLanguage: AppLanguage
    let isDefault: Bool
    let isActive: Bool
    let isRecommended: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let isSwitching: Bool
    let downloadProgress: Double
    let downloadSnapshot: ModelManager.DownloadSnapshot?
    let onSwitch: () -> Void
    let onSetDefault: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    
    private var isComingSoon: Bool {
        model.availability == .comingSoon
    }
    
    private var isAvailable: Bool {
        model.availability == .available
    }

    private var showsHoverAffordance: Bool {
        isAvailable && !isComingSoon && !isSwitching
    }

    private var isRowInteractive: Bool {
        isDownloaded && !isComingSoon && !isSwitching && !isActive
    }

    private var downloadPhaseCaption: String? {
        guard let downloadSnapshot else { return nil }

        switch downloadSnapshot.phase {
        case .listing:
            return localized("Please wait...", locale: locale)
        case .downloading(let completedFiles, let totalFiles):
            guard let completedFiles, let totalFiles else { return nil }
            return "\(completedFiles) / \(totalFiles)"
        case .compiling, .preparing:
            return localized("Preparing Model...", locale: locale)
        case .idle, .completed:
            return nil
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            selectionIndicator
            
            VStack(alignment: .leading, spacing: 8) {
                headerRow
                metadataRow
                
                if !model.description.isEmpty {
                    Text(model.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            actionButton
        }
        .padding(14)
        .background(
            Rectangle()
                .fill(backgroundStyle)
        )
        .opacity(isComingSoon ? 0.7 : 1.0)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onTapGesture {
            if isRowInteractive {
                onSwitch()
            }
        }
        .onHover { hovering in
            isHovered = hovering && showsHoverAffordance
        }
    }
    
    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .stroke(selectionRingColor, lineWidth: 2)
                .frame(width: 20, height: 20)

            if isActive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 12, height: 12)
            } else if isHovered {
                Circle()
                    .fill(selectionDotColor)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.top, 2)
    }

    private var selectionRingColor: Color {
        if isActive {
            return .green
        }

        if isHovered {
            return AppColors.accent.opacity(0.7)
        }

        return Color.secondary.opacity(0.3)
    }

    private var selectionDotColor: Color {
        if isHovered {
            return AppColors.accent.opacity(0.32)
        }

        return Color.secondary.opacity(0.14)
    }
    
    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(model.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)

            if isActive {
                Text(localized("Active", locale: locale))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green, in: Capsule())
                    .foregroundStyle(.white)
            }

            if isDefault {
                Text(localized("Default", locale: locale))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColors.accent.opacity(isActive ? 0.2 : 1.0), in: Capsule())
                    .foregroundStyle(isActive ? AppColors.accent : .white)
            }

            if isRecommended {
                Text(localized("Recommended", locale: locale))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColors.accent.opacity(0.15), in: Capsule())
                    .foregroundStyle(AppColors.accent)
            }

            if isComingSoon {
                Text(localized("Coming Soon", locale: locale))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.2), in: Capsule())
                    .foregroundStyle(.purple)
            }

            if !model.provider.isLocal && isAvailable {
                Text(localized("Cloud", locale: locale))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.2), in: Capsule())
                    .foregroundStyle(.blue)
            }
        }
    }
    
    private var metadataRow: some View {
        HStack(spacing: 12) {
            MetadataBadge(
                icon: model.provider.iconName,
                text: model.provider.rawValue
            )

            MetadataBadge(presentation: model.languageBadgePresentation(for: selectedLanguage))

            if model.sizeInMB > 0 {
                MetadataBadge(icon: "internaldrive", text: model.formattedSize)
            } else if !model.provider.isLocal {
                MetadataBadge(icon: "cloud", text: localized("Cloud Model", locale: locale))
            }

            RatingIndicator(label: localized("Speed", locale: locale), rating: model.speedRating)
            RatingIndicator(label: localized("Accuracy", locale: locale), rating: model.accuracyRating)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if isComingSoon {
            Text(localized("Coming Soon", locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        } else if isDownloading {
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: downloadProgress)
                    .frame(width: 80)
                Text("\(Int(downloadProgress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let downloadPhaseCaption {
                    Text(downloadPhaseCaption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else if isSwitching {
            ProgressView()
                .controlSize(.small)
                .padding(.trailing, 8)
        } else if isDownloaded {
            HStack(spacing: 8) {
                if isActive {
                    HStack(spacing: 4) {
                        IconView(icon: .circleCheck, size: 14)
                        Text(localized("Active", locale: locale))
                    }
                    .font(.caption)
                    .foregroundStyle(.green)
                }

                Menu {
                    if !isDefault {
                        Button(localized("Set as Default", locale: locale), action: onSetDefault)
                    }
                    if !isActive {
                         Button(localized("Switch to Model", locale: locale), action: onSwitch)
                    }
                    Divider()
                    Button(localized("Delete Model", locale: locale), role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1), in: Circle())
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
        } else {
            Button(action: onDownload) {
                HStack(spacing: 4) {
                    IconView(icon: .download, size: 12)
                    Text(localized("Download", locale: locale))
                }
                .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
    
    private var backgroundStyle: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(Color.green.opacity(0.08))
        }
        if isHovered {
            return AnyShapeStyle(AppColors.accent.opacity(0.07))
        }
        if isDefault {
            return AnyShapeStyle(AppColors.accent.opacity(0.05))
        }
        return AnyShapeStyle(Color.clear)
    }
}

struct FeatureModelRow: View {
    @Environment(\.locale) private var locale

    let featureType: FeatureModelType
    let isDownloaded: Bool
    let isEnabled: Bool
    let aiEnhancementEnabled: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let onToggle: (Bool) -> Void
    let onDownload: () -> Void

    private var showsStreamingAIWarning: Bool {
        featureType == .streaming && aiEnhancementEnabled
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: featureType.iconName)
                .font(.system(size: 20))
                .foregroundStyle(isEnabled ? .green : .secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(featureType.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if isDownloaded && isEnabled {
                        Text(localized("Active", locale: locale))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green, in: Capsule())
                            .foregroundStyle(.white)
                    } else if isDownloaded {
                        Text(localized("Downloaded", locale: locale))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(featureType.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if showsStreamingAIWarning {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(localized("Streaming transcription is disabled while AI Enhancement is enabled.", locale: locale))
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                MetadataBadge(icon: "internaldrive", text: featureType.formattedSize)
            }

            Spacer()

            if isDownloading {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: downloadProgress)
                        .frame(width: 80)
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if isDownloaded {
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { onToggle($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            } else {
                Button(action: onDownload) {
                    HStack(spacing: 4) {
                        IconView(icon: .download, size: 12)
                        Text(localized("Download", locale: locale))
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension ModelManager.WhisperModel {
    func matchesSearch(_ query: String) -> Bool {
        let localizedQuery = query.localizedLowercase
        return displayName.localizedLowercase.contains(localizedQuery)
            || name.localizedLowercase.contains(localizedQuery)
            || description.localizedLowercase.contains(localizedQuery)
            || provider.rawValue.localizedLowercase.contains(localizedQuery)
            || language.rawValue.localizedLowercase.contains(localizedQuery)
    }
}

private func filterModels(
    _ models: [ModelManager.WhisperModel],
    matching query: String
) -> [ModelManager.WhisperModel] {
    guard !query.isEmpty else { return models }
    return models.filter { $0.matchesSearch(query) }
}

#Preview {
    ModelsSettingsView(settings: SettingsStore(), modelManager: ModelManager())
        .padding()
        .frame(width: 600)
}
