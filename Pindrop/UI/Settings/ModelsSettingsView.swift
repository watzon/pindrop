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
            
            if let errorMessage {
                errorBanner(message: errorMessage)
            }
        }
        .task {
            await modelManager.refreshDownloadedModels()
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
                        isSelected: settings.selectedModel == model.name,
                        isDownloaded: modelManager.isModelDownloaded(model.name),
                        isDownloading: downloadingModel == model.name,
                        downloadProgress: modelManager.downloadProgress,
                        onSelect: { settings.selectedModel = model.name },
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
                        ? Color.accentColor.opacity(0.15)
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
    let isSelected: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let onSelect: () -> Void
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
    }
    
    private var selectionIndicator: some View {
        Button(action: onSelect) {
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
        }
        .buttonStyle(.plain)
        .disabled(!isDownloaded || isComingSoon)
        .padding(.top, 2)
    }
    
    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(model.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)
            
            if isSelected && isDownloaded {
                Text("Default")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
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
        } else if isDownloaded {
            HStack(spacing: 8) {
                if isSelected {
                    HStack(spacing: 4) {
                        IconView(icon: .circleCheck, size: 14)
                        Text("Default Model")
                    }
                    .font(.caption)
                    .foregroundStyle(.green)
                }
                
                Menu {
                    if !isSelected {
                        Button("Set as Default", action: onSelect)
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
        if isSelected && isDownloaded {
            return AnyShapeStyle(Color.accentColor.opacity(0.08))
        }
        return AnyShapeStyle(Color.clear)
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
