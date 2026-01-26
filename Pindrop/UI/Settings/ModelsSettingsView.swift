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
    
    var body: some View {
        VStack(spacing: 20) {
            currentModelCard
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
        SettingsCard(title: "Current Model", icon: "checkmark.circle") {
            if let currentModel = modelManager.availableModels.first(where: { $0.name == settings.selectedModel }) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentModel.displayName)
                            .font(.headline)
                        
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                IconView(icon: .hardDrive, size: 12)
                                Text("\(currentModel.sizeInMB) MB")
                            }
                            HStack(spacing: 4) {
                                IconView(icon: .zap, size: 12)
                                Text(speedLabel(for: currentModel.sizeInMB))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
    
    private var availableModelsCard: some View {
        SettingsCard(title: "Available Models", icon: "square.stack.3d.up") {
            VStack(spacing: 12) {
                ForEach(modelManager.availableModels) { model in
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
    
    private func speedLabel(for sizeMB: Int) -> String {
        switch sizeMB {
        case 0..<100: return "Very Fast"
        case 100..<300: return "Fast"
        case 300..<600: return "Medium"
        case 600..<1500: return "Slower"
        default: return "Slowest"
        }
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

struct ModelSettingsRow: View {
    let model: ModelManager.WhisperModel
    let isSelected: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
                            .frame(width: 18, height: 18)
                        
                        if isSelected {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 10, height: 10)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("\(model.sizeInMB) MB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isDownloaded)
            
            Spacer()
            
            if isDownloading {
                ProgressView(value: downloadProgress)
                    .frame(width: 80)
            } else if isDownloaded {
                HStack(spacing: 8) {
                    IconView(icon: .check, size: 12)
                        .foregroundStyle(.green)
                    
                    Button(role: .destructive, action: onDelete) {
                        Text("Delete")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
    }
}

#Preview {
    ModelsSettingsView(settings: SettingsStore())
        .padding()
        .frame(width: 500)
}
