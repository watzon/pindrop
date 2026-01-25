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
        VStack(spacing: 0) {
            List(selection: $settings.selectedModel) {
                ForEach(modelManager.availableModels) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.displayName)
                                .font(.headline)
                            
                            Text("\(model.sizeInMB) MB")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if downloadingModel == model.name {
                            ProgressView(value: modelManager.downloadProgress)
                                .frame(width: 100)
                        } else if modelManager.isModelDownloaded(model.name) {
                            Button("Delete") {
                                deleteModel(model)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Button("Download") {
                                downloadModel(model)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(model.name)
                }
            }
            .listStyle(.inset)
            
            if let errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") {
                        self.errorMessage = nil
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .padding()
                .background(Color.red.opacity(0.1))
            }
        }
        .frame(width: 500, height: 400)
        .task {
            await modelManager.refreshDownloadedModels()
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

#Preview {
    ModelsSettingsView(settings: SettingsStore())
}
