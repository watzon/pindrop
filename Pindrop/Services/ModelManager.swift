//
//  ModelManager.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation

@MainActor
@Observable
final class ModelManager {
    
    struct WhisperModel: Identifiable, Equatable {
        let id: String
        let name: String
        let displayName: String
        let sizeInMB: Int
        let huggingFaceRepo: String
        
        init(name: String, displayName: String, sizeInMB: Int, huggingFaceRepo: String = "argmaxinc/whisperkit-coreml") {
            self.id = name
            self.name = name
            self.displayName = displayName
            self.sizeInMB = sizeInMB
            self.huggingFaceRepo = huggingFaceRepo
        }
    }
    
    enum ModelError: Error, LocalizedError {
        case modelNotFound(String)
        case downloadFailed(String)
        case invalidModelPath
        case directoryCreationFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .modelNotFound(let name):
                return "Model '\(name)' not found in available models"
            case .downloadFailed(let message):
                return "Download failed: \(message)"
            case .invalidModelPath:
                return "Invalid model path"
            case .directoryCreationFailed(let message):
                return "Failed to create directory: \(message)"
            }
        }
    }
    
    let availableModels: [WhisperModel] = [
        WhisperModel(name: "tiny", displayName: "Tiny", sizeInMB: 75),
        WhisperModel(name: "tiny.en", displayName: "Tiny (English)", sizeInMB: 75),
        WhisperModel(name: "base", displayName: "Base", sizeInMB: 145),
        WhisperModel(name: "base.en", displayName: "Base (English)", sizeInMB: 145),
        WhisperModel(name: "small", displayName: "Small", sizeInMB: 483),
        WhisperModel(name: "small.en", displayName: "Small (English)", sizeInMB: 483),
        WhisperModel(name: "medium", displayName: "Medium", sizeInMB: 1500),
        WhisperModel(name: "medium.en", displayName: "Medium (English)", sizeInMB: 1500),
        WhisperModel(name: "large-v3", displayName: "Large v3", sizeInMB: 3100),
        WhisperModel(name: "turbo", displayName: "Turbo", sizeInMB: 809)
    ]
    
    private(set) var downloadProgress: Double = 0.0
    private(set) var isDownloading: Bool = false
    private(set) var currentDownloadModel: String?
    
    private let fileManager = FileManager.default
    
    var modelsDirectory: String {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let pindropDir = appSupport.appendingPathComponent("Pindrop/Models")
        return pindropDir.path
    }
    
    init() {
        createModelsDirectoryIfNeeded()
    }
    
    private func createModelsDirectoryIfNeeded() {
        let directory = modelsDirectory
        
        if !fileManager.fileExists(atPath: directory) {
            do {
                try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
            } catch {
                print("Failed to create models directory: \(error)")
            }
        }
    }
    
    func getDownloadedModels() async -> [WhisperModel] {
        var downloaded: [WhisperModel] = []
        for model in availableModels {
            if await isModelDownloaded(model.name) {
                downloaded.append(model)
            }
        }
        return downloaded
    }
    
    func isModelDownloaded(_ modelName: String) async -> Bool {
        guard let modelPath = await getModelPath(for: modelName) else {
            return false
        }
        
        return fileManager.fileExists(atPath: modelPath)
    }
    
    func getModelPath(for modelName: String) async -> String? {
        guard availableModels.contains(where: { $0.name == modelName }) else {
            return nil
        }
        
        let modelDir = "\(modelsDirectory)/\(modelName)"
        return modelDir
    }
    
    func downloadModel(named modelName: String) async throws {
        guard let model = availableModels.first(where: { $0.name == modelName }) else {
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
            downloadProgress = 0.0
        }
        
        do {
            let modelPath = "\(modelsDirectory)/\(modelName)"
            
            try fileManager.createDirectory(atPath: modelPath, withIntermediateDirectories: true)
            
            let huggingFaceURL = "https://huggingface.co/\(model.huggingFaceRepo)/resolve/main/\(modelName)"
            
            guard let url = URL(string: huggingFaceURL) else {
                throw ModelError.invalidModelPath
            }
            
            let (localURL, response) = try await URLSession.shared.download(from: url, delegate: DownloadDelegate(progressHandler: { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }))
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ModelError.downloadFailed("HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
            
            let destinationURL = URL(fileURLWithPath: modelPath)
            
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            try fileManager.moveItem(at: localURL, to: destinationURL)
            
            downloadProgress = 1.0
            
        } catch let error as ModelError {
            throw error
        } catch {
            throw ModelError.downloadFailed(error.localizedDescription)
        }
    }
    
    func deleteModel(named modelName: String) async throws {
        guard let modelPath = await getModelPath(for: modelName) else {
            throw ModelError.modelNotFound(modelName)
        }
        
        guard fileManager.fileExists(atPath: modelPath) else {
            throw ModelError.modelNotFound(modelName)
        }
        
        do {
            try fileManager.removeItem(atPath: modelPath)
        } catch {
            throw ModelError.downloadFailed("Failed to delete model: \(error.localizedDescription)")
        }
    }
}

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progressHandler: (Double) -> Void
    
    init(progressHandler: @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(progress)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    }
}
