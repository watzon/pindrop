//
//  ModelManager.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import WhisperKit
import os.log

@MainActor
@Observable
final class ModelManager {
    
    struct WhisperModel: Identifiable, Equatable {
        let id: String
        let name: String
        let displayName: String
        let sizeInMB: Int
        
        init(name: String, displayName: String, sizeInMB: Int) {
            self.id = name
            self.name = name
            self.displayName = displayName
            self.sizeInMB = sizeInMB
        }
    }
    
    enum ModelError: Error, LocalizedError {
        case modelNotFound(String)
        case downloadFailed(String)
        case deleteFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .modelNotFound(let name):
                return "Model '\(name)' not found"
            case .downloadFailed(let message):
                return "Download failed: \(message)"
            case .deleteFailed(let message):
                return "Delete failed: \(message)"
            }
        }
    }
    
    let availableModels: [WhisperModel] = [
        WhisperModel(name: "openai_whisper-tiny", displayName: "Tiny", sizeInMB: 75),
        WhisperModel(name: "openai_whisper-tiny.en", displayName: "Tiny (English)", sizeInMB: 75),
        WhisperModel(name: "openai_whisper-base", displayName: "Base", sizeInMB: 145),
        WhisperModel(name: "openai_whisper-base.en", displayName: "Base (English)", sizeInMB: 145),
        WhisperModel(name: "openai_whisper-small", displayName: "Small", sizeInMB: 483),
        WhisperModel(name: "openai_whisper-small.en", displayName: "Small (English)", sizeInMB: 483),
        WhisperModel(name: "openai_whisper-large-v3", displayName: "Large v3", sizeInMB: 3100),
        WhisperModel(name: "openai_whisper-large-v3-turbo", displayName: "Large v3 Turbo", sizeInMB: 809)
    ]
    
    private(set) var downloadProgress: Double = 0.0
    private(set) var isDownloading: Bool = false
    private(set) var currentDownloadModel: String?
    private(set) var downloadedModelNames: Set<String> = []
    
    private let fileManager = FileManager.default
    
    private var modelsBaseURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
    }
    
    init() {
        Task {
            await refreshDownloadedModels()
        }
    }
    
    func refreshDownloadedModels() async {
        var downloaded: Set<String> = []
        
        let basePath = modelsBaseURL.path
        guard fileManager.fileExists(atPath: basePath) else {
            downloadedModelNames = []
            return
        }
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: basePath)
            for folder in contents {
                let folderPath = modelsBaseURL.appendingPathComponent(folder).path
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: folderPath, isDirectory: &isDirectory), isDirectory.boolValue {
                    downloaded.insert(folder)
                }
            }
        } catch {
            Log.model.error("Failed to list downloaded models: \(error)")
        }
        
        downloadedModelNames = downloaded
    }
    
    func getDownloadedModels() async -> [WhisperModel] {
        await refreshDownloadedModels()
        return availableModels.filter { downloadedModelNames.contains($0.name) }
    }
    
    func isModelDownloaded(_ modelName: String) -> Bool {
        downloadedModelNames.contains(modelName)
    }
    
    func downloadModel(named modelName: String) async throws {
        guard availableModels.contains(where: { $0.name == modelName }) else {
            throw ModelError.modelNotFound(modelName)
        }
        
        guard !isDownloading else {
            throw ModelError.downloadFailed("Another download is in progress")
        }
        
        isDownloading = true
        currentDownloadModel = modelName
        downloadProgress = 0.0
        
        defer {
            isDownloading = false
            currentDownloadModel = nil
        }
        
        do {
            Log.model.info("Downloading model: \(modelName)")
            _ = try await WhisperKit.download(
                variant: modelName,
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress.fractionCompleted * 0.8
                    }
                }
            )
            
            Log.model.info("Download complete, prewarming model...")
            downloadProgress = 0.85
            
            let config = WhisperKitConfig(
                model: modelName,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: false
            )
            _ = try await WhisperKit(config)
            
            Log.model.info("Model prewarmed successfully")
            downloadProgress = 1.0
            await refreshDownloadedModels()
        } catch {
            downloadProgress = 0.0
            throw ModelError.downloadFailed(error.localizedDescription)
        }
    }
    
    func deleteModel(named modelName: String) async throws {
        let modelPath = modelsBaseURL.appendingPathComponent(modelName)
        
        guard fileManager.fileExists(atPath: modelPath.path) else {
            throw ModelError.modelNotFound(modelName)
        }
        
        do {
            try fileManager.removeItem(at: modelPath)
            await refreshDownloadedModels()
        } catch {
            throw ModelError.deleteFailed(error.localizedDescription)
        }
    }
}
