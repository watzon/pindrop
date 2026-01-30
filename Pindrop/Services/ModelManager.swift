//
//  ModelManager.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import WhisperKit
import FluidAudio
import os.log

@MainActor
@Observable
class ModelManager {
    
    enum ModelProvider: String, CaseIterable {
        case whisperKit = "WhisperKit"
        case parakeet = "Parakeet"
        case openAI = "OpenAI"
        case elevenLabs = "ElevenLabs"
        case groq = "Groq"
        
        var isLocal: Bool {
            switch self {
            case .whisperKit, .parakeet: return true
            case .openAI, .elevenLabs, .groq: return false
            }
        }
        
        var iconName: String {
            switch self {
            case .whisperKit: return "waveform"
            case .parakeet: return "bird"
            case .openAI: return "sparkles"
            case .elevenLabs: return "waveform.circle"
            case .groq: return "bolt"
            }
        }
    }
    
    enum ModelLanguage: String {
        case english = "English-only"
        case multilingual = "Multilingual"
    }
    
    enum ModelAvailability: Equatable {
        case available
        case comingSoon
        case requiresSetup
    }
    
    struct WhisperModel: Identifiable, Equatable {
        let id: String
        let name: String
        let displayName: String
        let sizeInMB: Int
        let description: String
        let speedRating: Double
        let accuracyRating: Double
        let language: ModelLanguage
        let provider: ModelProvider
        let availability: ModelAvailability
        
        init(
            name: String,
            displayName: String,
            sizeInMB: Int,
            description: String = "",
            speedRating: Double = 5.0,
            accuracyRating: Double = 5.0,
            language: ModelLanguage = .multilingual,
            provider: ModelProvider = .whisperKit,
            availability: ModelAvailability = .available
        ) {
            self.id = name
            self.name = name
            self.displayName = displayName
            self.sizeInMB = sizeInMB
            self.description = description
            self.speedRating = speedRating
            self.accuracyRating = accuracyRating
            self.language = language
            self.provider = provider
            self.availability = availability
        }
        
        var formattedSize: String {
            if sizeInMB >= 1000 {
                return String(format: "%.1f GB", Double(sizeInMB) / 1000.0)
            } else {
                return "\(sizeInMB) MB"
            }
        }
    }
    
    enum ModelError: Error, LocalizedError {
        case modelNotFound(String)
        case downloadFailed(String)
        case deleteFailed(String)
        case downloadNotImplemented(String)
        
        var errorDescription: String? {
            switch self {
            case .modelNotFound(let name):
                return "Model '\(name)' not found"
            case .downloadFailed(let message):
                return "Download failed: \(message)"
            case .deleteFailed(let message):
                return "Delete failed: \(message)"
            case .downloadNotImplemented(let provider):
                return "Download for \(provider) models is not yet implemented"
            }
        }
    }
    
    let availableModels: [WhisperModel] = [
        // WhisperKit Local Models
        WhisperModel(
            name: "openai_whisper-tiny",
            displayName: "Whisper Tiny",
            sizeInMB: 75,
            description: "Fastest model, ideal for quick dictation with acceptable accuracy",
            speedRating: 10.0,
            accuracyRating: 6.0,
            language: .multilingual
        ),
        WhisperModel(
            name: "openai_whisper-tiny.en",
            displayName: "Whisper Tiny (English)",
            sizeInMB: 75,
            description: "English-optimized tiny model with slightly better accuracy",
            speedRating: 10.0,
            accuracyRating: 6.5,
            language: .english
        ),
        WhisperModel(
            name: "openai_whisper-base",
            displayName: "Whisper Base",
            sizeInMB: 145,
            description: "Good balance between speed and accuracy for everyday use",
            speedRating: 9.0,
            accuracyRating: 7.0,
            language: .multilingual
        ),
        WhisperModel(
            name: "openai_whisper-base.en",
            displayName: "Whisper Base (English)",
            sizeInMB: 145,
            description: "English-optimized base model, recommended for most users",
            speedRating: 9.0,
            accuracyRating: 7.5,
            language: .english
        ),
        WhisperModel(
            name: "openai_whisper-small",
            displayName: "Whisper Small",
            sizeInMB: 483,
            description: "Higher accuracy for complex vocabulary and technical terms",
            speedRating: 7.5,
            accuracyRating: 8.0,
            language: .multilingual
        ),
        WhisperModel(
            name: "openai_whisper-small.en",
            displayName: "Whisper Small (English)",
            sizeInMB: 483,
            description: "English-optimized with excellent accuracy for professional use",
            speedRating: 7.5,
            accuracyRating: 8.5,
            language: .english
        ),
        WhisperModel(
            name: "openai_whisper-large-v3",
            displayName: "Whisper Large v3",
            sizeInMB: 3100,
            description: "Maximum accuracy for demanding transcription tasks",
            speedRating: 5.0,
            accuracyRating: 9.7,
            language: .multilingual
        ),
        WhisperModel(
            name: "openai_whisper-large-v3_turbo",
            displayName: "Whisper Large v3 Turbo",
            sizeInMB: 809,
            description: "Near large-model accuracy with significantly faster processing",
            speedRating: 7.5,
            accuracyRating: 9.5,
            language: .multilingual
        ),
        
        // Parakeet Models (via FluidInference CoreML ports)
        WhisperModel(
            name: "parakeet-tdt-0.6b-v2",
            displayName: "Parakeet TDT 0.6B V2",
            sizeInMB: 2580,
            description: "NVIDIA's state-of-the-art speech recognition model, English-only",
            speedRating: 8.5,
            accuracyRating: 9.8,
            language: .english,
            provider: .parakeet,
            availability: .available
        ),
        WhisperModel(
            name: "parakeet-tdt-0.6b-v3",
            displayName: "Parakeet TDT 0.6B V3",
            sizeInMB: 2670,
            description: "Latest Parakeet model with multilingual support",
            speedRating: 8.0,
            accuracyRating: 9.9,
            language: .multilingual,
            provider: .parakeet,
            availability: .available
        ),
        WhisperModel(
            name: "parakeet-tdt-1.1b",
            displayName: "Parakeet TDT 1.1B",
            sizeInMB: 4400,
            description: "Larger Parakeet model with exceptional accuracy",
            speedRating: 7.0,
            accuracyRating: 9.95,
            language: .english,
            provider: .parakeet,
            availability: .comingSoon
        ),
        
        // Coming Soon - Cloud Providers
        WhisperModel(
            name: "openai_whisper-1",
            displayName: "OpenAI Whisper API",
            sizeInMB: 0,
            description: "Cloud-based transcription via OpenAI's API",
            speedRating: 9.0,
            accuracyRating: 9.5,
            language: .multilingual,
            provider: .openAI,
            availability: .comingSoon
        ),
        WhisperModel(
            name: "groq_whisper-large-v3-turbo",
            displayName: "Whisper Large v3 Turbo (Groq)",
            sizeInMB: 0,
            description: "Lightning-fast cloud inference powered by Groq",
            speedRating: 10.0,
            accuracyRating: 9.5,
            language: .multilingual,
            provider: .groq,
            availability: .comingSoon
        ),
        WhisperModel(
            name: "elevenlabs_scribe",
            displayName: "ElevenLabs Scribe",
            sizeInMB: 0,
            description: "High-quality transcription with speaker diarization",
            speedRating: 8.0,
            accuracyRating: 9.3,
            language: .multilingual,
            provider: .elevenLabs,
            availability: .comingSoon
        )
    ]
    
    private(set) var downloadProgress: Double = 0.0
    private(set) var isDownloading: Bool = false
    private(set) var currentDownloadModel: String?
    private(set) var downloadedModelNames: Set<String> = []
    
    private let fileManager = FileManager.default
    
    private var modelsBaseURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Pindrop", isDirectory: true)
    }
    
    private var parakeetModelsURL: URL {
        modelsBaseURL.appendingPathComponent("FluidInference", isDirectory: true)
                     .appendingPathComponent("parakeet-coreml", isDirectory: true)
    }
    
    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    
    init() {
        guard !Self.isPreview else { return }
        Task {
            await refreshDownloadedModels()
        }
    }
    
    func refreshDownloadedModels() async {
        var downloaded: Set<String> = []
        
        let whisperKitPath = modelsBaseURL
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
        
        if fileManager.fileExists(atPath: whisperKitPath.path) {
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: whisperKitPath.path)
                for folder in contents {
                    if folder.hasPrefix(".") { continue }
                    
                    let folderPath = whisperKitPath.appendingPathComponent(folder).path
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: folderPath, isDirectory: &isDirectory), isDirectory.boolValue {
                        downloaded.insert(folder)
                    }
                }
            } catch {
                Log.model.error("Failed to list WhisperKit models: \(error)")
            }
        }
        
        if fileManager.fileExists(atPath: parakeetModelsURL.path) {
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: parakeetModelsURL.path)
                for folder in contents {
                    if folder.hasPrefix(".") { continue }
                    
                    let folderPath = parakeetModelsURL.appendingPathComponent(folder).path
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: folderPath, isDirectory: &isDirectory), isDirectory.boolValue {
                        // Strip "-coreml" suffix (7 chars) to match model IDs
                        let normalizedName = folder.hasSuffix("-coreml")
                            ? String(folder.dropLast(7))
                            : folder
                        downloaded.insert(normalizedName)
                    }
                }
            } catch {
                Log.model.error("Failed to list Parakeet models: \(error)")
            }
        }
        
        Log.model.debug("Found \(downloaded.count) downloaded models: \(downloaded)")
        downloadedModelNames = downloaded
    }
    
    func getDownloadedModels() async -> [WhisperModel] {
        await refreshDownloadedModels()
        return availableModels.filter { downloadedModelNames.contains($0.name) }
    }
    
    func isModelDownloaded(_ modelName: String) -> Bool {
        let result = downloadedModelNames.contains(modelName)
        Log.model.debug("isModelDownloaded(\(modelName)): \(result), downloadedModels: \(self.downloadedModelNames)")
        return result
    }
    
    func downloadModel(named modelName: String, onProgress: ((Double) -> Void)? = nil) async throws {
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
        }
        
        if model.provider == .parakeet {
            try await downloadParakeetModel(named: modelName, onProgress: onProgress)
        } else {
            try await downloadWhisperKitModel(named: modelName, onProgress: onProgress)
        }
    }
    
    private func downloadWhisperKitModel(named modelName: String, onProgress: ((Double) -> Void)? = nil) async throws {
        do {
            Log.model.info("Downloading WhisperKit model: \(modelName) to \(self.modelsBaseURL.path)")
            
            try fileManager.createDirectory(at: self.modelsBaseURL, withIntermediateDirectories: true)
            
            _ = try await WhisperKit.download(
                variant: modelName,
                downloadBase: self.modelsBaseURL,
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress.fractionCompleted * 0.8
                        onProgress?(self?.downloadProgress ?? 0)
                    }
                }
            )
            
            Log.model.info("Download complete, prewarming model...")
            downloadProgress = 0.85
            onProgress?(0.85)
            
            let config = WhisperKitConfig(
                model: modelName,
                downloadBase: self.modelsBaseURL,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: false
            )
            _ = try await WhisperKit(config)
            
            Log.model.info("Model prewarmed successfully")
            downloadProgress = 1.0
            onProgress?(1.0)
            await refreshDownloadedModels()
        } catch {
            downloadProgress = 0.0
            throw ModelError.downloadFailed(error.localizedDescription)
        }
    }
    
    private func downloadParakeetModel(named modelName: String, onProgress: ((Double) -> Void)? = nil) async throws {
        Log.model.info("Parakeet model download requested: \(modelName)")
        Log.model.info("Parakeet models path: \(self.parakeetModelsURL.path)")
        
        let version: AsrModelVersion
        if modelName.contains("v3") {
            version = .v3
        } else if modelName.contains("v2") {
            version = .v2
        } else {
            throw ModelError.downloadFailed("Unknown Parakeet model version: \(modelName)")
        }
        
        do {
            try fileManager.createDirectory(at: parakeetModelsURL, withIntermediateDirectories: true)
        } catch {
            throw ModelError.downloadFailed("Failed to create Parakeet models directory: \(error.localizedDescription)")
        }
        
        downloadProgress = 0.1
        onProgress?(0.1)
        Log.model.info("Starting Parakeet model download (version: \(version == .v3 ? "v3" : "v2"))")
        
        do {
            let targetDir = parakeetModelsURL.appendingPathComponent(
                version == .v3 ? "parakeet-tdt-0.6b-v3-coreml" : "parakeet-tdt-0.6b-v2-coreml",
                isDirectory: true
            )
            
            downloadProgress = 0.3
            onProgress?(0.3)
            
            _ = try await AsrModels.downloadAndLoad(to: targetDir, version: version)
            
            Log.model.info("Parakeet model download complete")
            downloadProgress = 0.9
            onProgress?(0.9)
            
            downloadProgress = 1.0
            onProgress?(1.0)
            
            await refreshDownloadedModels()
        } catch {
            downloadProgress = 0.0
            Log.model.error("Parakeet model download failed: \(error.localizedDescription)")
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
