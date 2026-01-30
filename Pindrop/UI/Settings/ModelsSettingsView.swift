//
//  ModelsSettingsView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct ModelsSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @State private var modelManager = ModelManager()
    @State private var downloadingModel: String?
    @State private var switchingToModel: String?
    @State private var activeModelName: String?
    @State private var errorMessage: String?
    @State private var selectedFilter: ModelFilter = .all
    
    enum ModelFilter: String, CaseIterable {
        case all = "All"
        case local = "Local"
        case cloud = "Cloud"
        case comingSoon = "Coming Soon"
        
        func matches(_ model: ModelManager.WhisperModel) -> Bool {
            switch self {
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
        modelManager.availableModels.filter { selectedFilter.matches($0) }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            currentModelCard
            filterBar
            availableModelsCard
            featureModelsCard
            
            if let errorMessage {
                errorBanner(message: errorMessage)
            }
        }
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
    
    private var currentModelCard: some View {
        SettingsCard(title: "Default Model", icon: "checkmark.circle") {
            if let currentModel = modelManager.availableModels.first(where: { $0.name == settings.selectedModel }) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(currentModel.displayName)
                            .font(.headline)
                        
                        HStack(spacing: 16) {
                            MetadataBadge(
                                icon: currentModel.language == .english ? "textformat" : "globe",
                                text: currentModel.language.rawValue
                            )
                            
                            if currentModel.sizeInMB > 0 {
                                MetadataBadge(icon: "internaldrive", text: currentModel.formattedSize)
                            }
                            
                            RatingIndicator(label: "Speed", rating: currentModel.speedRating)
                            RatingIndicator(label: "Accuracy", rating: currentModel.accuracyRating)
                        }
                    }
                    
                    Spacer()
                    
                    if modelManager.isModelDownloaded(currentModel.name) {
                        HStack(spacing: 4) {
                            IconView(icon: .circleCheck, size: 14)
                            Text("Ready")
                        }
                        .font(.caption)
                        .foregroundStyle(.green)
                    }
                }
            } else {
                Text("No model selected")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(ModelFilter.allCases, id: \.self) { filter in
                FilterButton(
                    title: filter.rawValue,
                    isSelected: selectedFilter == filter,
                    action: { selectedFilter = filter }
                )
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }
    
    private var availableModelsCard: some View {
        SettingsCard(title: "Available Models", icon: "square.stack.3d.up") {
            VStack(spacing: 0) {
                ForEach(Array(filteredModels.enumerated()), id: \.element.id) { index, model in
                    ModelSettingsRow(
                        model: model,
                        isDefault: settings.selectedModel == model.name,
                        isActive: activeModelName == model.name,
                        isDownloaded: modelManager.isModelDownloaded(model.name),
                        isDownloading: downloadingModel == model.name,
                        isSwitching: switchingToModel == model.name,
                        downloadProgress: modelManager.downloadProgress,
                        onSwitch: { switchModel(model) },
                        onSetDefault: { settings.selectedModel = model.name },
                        onDownload: { downloadModel(model) },
                        onDelete: { deleteModel(model) }
                    )
                    
                    if index < filteredModels.count - 1 {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                }
            }
        }
    }
    
    private var featureModelsCard: some View {
        SettingsCard(title: "Feature Models", icon: "puzzlepiece.extension") {
            VStack(spacing: 0) {
                ForEach(Array(FeatureModelType.allCases.enumerated()), id: \.element.id) { index, featureType in
                    FeatureModelRow(
                        featureType: featureType,
                        isDownloaded: modelManager.isFeatureModelDownloaded(featureType),
                        isEnabled: settings.isFeatureEnabled(featureType),
                        isDownloading: modelManager.currentDownloadingFeature == featureType,
                        downloadProgress: modelManager.featureDownloadProgress,
                        onToggle: { enabled in toggleFeature(featureType, enabled: enabled) },
                        onDownload: { downloadFeatureModel(featureType) }
                    )
                    
                    if index < FeatureModelType.allCases.count - 1 {
                        Divider()
                            .padding(.horizontal, 12)
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
            
            Button("Dismiss") {
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
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
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
    let model: ModelManager.WhisperModel
    let isDefault: Bool
    let isActive: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let isSwitching: Bool
    let downloadProgress: Double
    let onSwitch: () -> Void
    let onSetDefault: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    
    private var isComingSoon: Bool {
        model.availability == .comingSoon
    }
    
    private var isAvailable: Bool {
        model.availability == .available
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
        .background(backgroundStyle)
        .opacity(isComingSoon ? 0.7 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            if isDownloaded && !isComingSoon && !isSwitching && !isActive {
                onSwitch()
            }
        }
    }
    
    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .stroke(isActive ? Color.green : Color.secondary.opacity(0.3), lineWidth: 2)
                .frame(width: 20, height: 20)
            
            if isActive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 12, height: 12)
            }
        }
        .padding(.top, 2)
    }
    
    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(model.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)
            
            if isActive {
                Text("Active")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green, in: Capsule())
                    .foregroundStyle(.white)
            }
            
            if isDefault {
                Text("Default")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColors.accent.opacity(isActive ? 0.2 : 1.0), in: Capsule())
                    .foregroundStyle(isActive ? AppColors.accent : .white)
            }
            
            if isComingSoon {
                Text("Coming Soon")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.2), in: Capsule())
                    .foregroundStyle(.purple)
            }
            
            if !model.provider.isLocal && isAvailable {
                Text("Cloud")
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

            MetadataBadge(
                icon: model.language == .english ? "textformat" : "globe",
                text: model.language.rawValue
            )

            if model.sizeInMB > 0 {
                MetadataBadge(icon: "internaldrive", text: model.formattedSize)
            } else if !model.provider.isLocal {
                MetadataBadge(icon: "cloud", text: "Cloud Model")
            }

            RatingIndicator(label: "Speed", rating: model.speedRating)
            RatingIndicator(label: "Accuracy", rating: model.accuracyRating)
        }
    }
    
    @ViewBuilder
    private var actionButton: some View {
        if isComingSoon {
            Text("Coming Soon")
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
                        Text("Active")
                    }
                    .font(.caption)
                    .foregroundStyle(.green)
                }
                
                Menu {
                    if !isDefault {
                        Button("Set as Default", action: onSetDefault)
                    }
                    if !isActive {
                         Button("Switch to Model", action: onSwitch)
                    }
                    Divider()
                    Button("Delete Model", role: .destructive, action: onDelete)
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
                    Text("Download")
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
        if isDefault {
            return AnyShapeStyle(AppColors.accent.opacity(0.05))
        }
        return AnyShapeStyle(Color.clear)
    }
}

struct FeatureModelRow: View {
    let featureType: FeatureModelType
    let isDownloaded: Bool
    let isEnabled: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let onToggle: (Bool) -> Void
    let onDownload: () -> Void
    
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
                        Text("Active")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green, in: Capsule())
                            .foregroundStyle(.white)
                    } else if isDownloaded {
                        Text("Downloaded")
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
                        Text("Download")
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

#Preview {
    ModelsSettingsView(settings: SettingsStore())
        .padding()
        .frame(width: 600)
}
