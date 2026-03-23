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
    nonisolated static let englishRecommendedModelNames = [
        "openai_whisper-base.en",
        "openai_whisper-small.en",
        "openai_whisper-medium",
        "openai_whisper-large-v3_turbo"
    ]

    nonisolated static let multilingualRecommendedModelNames = [
        "openai_whisper-base",
        "openai_whisper-small",
        "openai_whisper-medium",
        "openai_whisper-large-v3_turbo"
    ]

    nonisolated static let recommendedModelNames = englishRecommendedModelNames
    nonisolated static let recommendedModelNameSet: Set<String> = Set(englishRecommendedModelNames)

    
    enum ModelProvider: String, CaseIterable, Sendable {
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
    
    enum ModelLanguage: String, Sendable {
        case english = "English-only"
        case multilingual = "Multilingual"
    }

    enum LanguageSupport: Sendable {
        case englishOnly
        case fullMultilingual
        case parakeetV3European

        enum BadgeTone: Sendable {
            case normal
            case caution
        }

        struct BadgePresentation: Sendable {
            let iconName: String
            let text: String
            let tone: BadgeTone
        }

        func supports(_ language: AppLanguage) -> Bool {
            guard language != .automatic else { return true }

            switch self {
            case .englishOnly:
                return language.isEnglish
            case .fullMultilingual:
                return true
            case .parakeetV3European:
                switch language {
                case .automatic, .english, .spanish, .french, .german, .portugueseBrazil, .italian, .dutch, .turkish:
                    return true
                case .simplifiedChinese, .japanese, .korean:
                    return false
                }
            }
        }

        var badgeText: String {
            switch self {
            case .englishOnly:
                return "English-only"
            case .fullMultilingual:
                return "Multilingual"
            case .parakeetV3European:
                return "European multilingual"
            }
        }

        var badgeIconName: String {
            switch self {
            case .englishOnly:
                return "textformat"
            case .fullMultilingual, .parakeetV3European:
                return "globe"
            }
        }

        func badgePresentation(for language: AppLanguage) -> BadgePresentation {
            BadgePresentation(
                iconName: badgeIconName,
                text: badgeText,
                tone: supports(language) ? .normal : .caution
            )
        }
    }
    
    enum ModelAvailability: Equatable, Sendable {
        case available
        case comingSoon
        case requiresSetup
    }
    
    struct WhisperModel: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let displayName: String
        let sizeInMB: Int
        let description: String
        let speedRating: Double
        let accuracyRating: Double
        let language: ModelLanguage
        let languageSupport: LanguageSupport
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
            languageSupport: LanguageSupport? = nil,
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
            self.languageSupport = languageSupport ?? (language == .english ? .englishOnly : .fullMultilingual)
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

        func supports(language: AppLanguage) -> Bool {
            languageSupport.supports(language)
        }

        func languageBadgePresentation(for language: AppLanguage) -> LanguageSupport.BadgePresentation {
            languageSupport.badgePresentation(for: language)
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
            name: "openai_whisper-small_216MB",
            displayName: "Whisper Small (Quantized)",
            sizeInMB: 216,
            description: "Quantized small model — half the size with similar accuracy",
            speedRating: 8.0,
            accuracyRating: 7.8,
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
            name: "openai_whisper-small.en_217MB",
            displayName: "Whisper Small (English, Quantized)",
            sizeInMB: 217,
            description: "Quantized English small model — compact and fast",
            speedRating: 8.0,
            accuracyRating: 8.3,
            language: .english
        ),
        WhisperModel(
            name: "openai_whisper-medium",
            displayName: "Whisper Medium",
            sizeInMB: 1530,
            description: "Excellent for multilingual and code-switching (e.g. Chinese/English mix)",
            speedRating: 6.5,
            accuracyRating: 8.8,
            language: .multilingual
        ),
        WhisperModel(
            name: "openai_whisper-medium.en",
            displayName: "Whisper Medium (English)",
            sizeInMB: 1530,
            description: "English-optimized medium model with high accuracy",
            speedRating: 6.5,
            accuracyRating: 9.0,
            language: .english
        ),
        WhisperModel(
            name: "openai_whisper-large-v2",
            displayName: "Whisper Large v2",
            sizeInMB: 3100,
            description: "Previous generation large model, still very capable",
            speedRating: 5.0,
            accuracyRating: 9.3,
            language: .multilingual
        ),
        WhisperModel(
            name: "openai_whisper-large-v2_949MB",
            displayName: "Whisper Large v2 (Quantized)",
            sizeInMB: 949,
            description: "Quantized large v2 — much smaller with minimal accuracy loss",
            speedRating: 6.0,
            accuracyRating: 9.1,
            language: .multilingual
        ),
        WhisperModel(
            name: "openai_whisper-large-v2_turbo",
            displayName: "Whisper Large v2 Turbo",
            sizeInMB: 3100,
            description: "Turbo-optimized large v2 for faster inference",
            speedRating: 6.5,
            accuracyRating: 9.3,
            language: .multilingual
        ),
        WhisperModel(
            name: "openai_whisper-large-v2_turbo_955MB",
            displayName: "Whisper Large v2 Turbo (Quantized)",
            sizeInMB: 955,
            description: "Quantized turbo large v2 — fast and compact",
            speedRating: 7.0,
            accuracyRating: 9.1,
            language: .multilingual
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
            name: "openai_whisper-large-v3_947MB",
            displayName: "Whisper Large v3 (Quantized)",
            sizeInMB: 947,
            description: "Quantized large v3 — great accuracy in a smaller package",
            speedRating: 6.0,
            accuracyRating: 9.5,
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
        WhisperModel(
            name: "openai_whisper-large-v3_turbo_954MB",
            displayName: "Whisper Large v3 Turbo (Quantized)",
            sizeInMB: 954,
            description: "Quantized turbo v3 — balanced speed and accuracy",
            speedRating: 7.5,
            accuracyRating: 9.3,
            language: .multilingual
        ),
        WhisperModel(
            name: "openai_whisper-large-v3-v20240930",
            displayName: "Whisper Large v3 (Sep 2024)",
            sizeInMB: 3100,
            description: "Updated large v3 with improved multilingual performance",
            speedRating: 5.0,
            accuracyRating: 9.8,
            language: .multilingual
        ),
        WhisperModel(
            name: "openai_whisper-large-v3-v20240930_547MB",
            displayName: "Whisper Large v3 Sep 2024 (Q 547MB)",
            sizeInMB: 547,
            description: "Heavily quantized — smallest large v3 variant",
            speedRating: 7.0,
            accuracyRating: 9.3,
            language: .multilingual
        ),
        WhisperModel(
            name: "openai_whisper-large-v3-v20240930_626MB",
            displayName: "Whisper Large v3 Sep 2024 (Q 626MB)",
            sizeInMB: 626,
            description: "Quantized Sep 2024 large v3 — compact with great accuracy",
            speedRating: 6.5,
            accuracyRating: 9.5,
            language: .multilingual
        ),
        WhisperModel(
            name: "openai_whisper-large-v3-v20240930_turbo",
            displayName: "Whisper Large v3 Sep 2024 Turbo",
            sizeInMB: 3100,
            description: "Latest turbo-optimized large v3 — best overall performance",
            speedRating: 6.5,
            accuracyRating: 9.8,
            language: .multilingual
        ),
        WhisperModel(
            name: "openai_whisper-large-v3-v20240930_turbo_632MB",
            displayName: "Whisper Large v3 Sep 2024 Turbo (Quantized)",
            sizeInMB: 632,
            description: "Quantized latest turbo — excellent accuracy in ~600MB",
            speedRating: 7.5,
            accuracyRating: 9.5,
            language: .multilingual
        ),
        
        // Distil-Whisper Models (distilled from large v3)
        WhisperModel(
            name: "distil-whisper_distil-large-v3",
            displayName: "Distil Large v3",
            sizeInMB: 1510,
            description: "Distilled large v3 — faster with minimal accuracy loss",
            speedRating: 7.5,
            accuracyRating: 9.3,
            language: .multilingual
        ),
        WhisperModel(
            name: "distil-whisper_distil-large-v3_594MB",
            displayName: "Distil Large v3 (Quantized)",
            sizeInMB: 594,
            description: "Quantized distilled model — great speed/accuracy tradeoff",
            speedRating: 8.0,
            accuracyRating: 9.0,
            language: .multilingual
        ),
        WhisperModel(
            name: "distil-whisper_distil-large-v3_turbo",
            displayName: "Distil Large v3 Turbo",
            sizeInMB: 1510,
            description: "Turbo-optimized distilled model for fastest large-class inference",
            speedRating: 8.0,
            accuracyRating: 9.3,
            language: .multilingual
        ),
        WhisperModel(
            name: "distil-whisper_distil-large-v3_turbo_600MB",
            displayName: "Distil Large v3 Turbo (Quantized)",
            sizeInMB: 600,
            description: "Quantized turbo distilled — fastest large-class model at ~600MB",
            speedRating: 8.5,
            accuracyRating: 9.0,
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
            languageSupport: .parakeetV3European,
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

    func recommendedModels(for language: AppLanguage) -> [WhisperModel] {
        let recommendedModelNames: [String]
        switch language {
        case .english:
            recommendedModelNames = Self.englishRecommendedModelNames
        case .automatic, .simplifiedChinese, .spanish, .french, .german, .turkish, .japanese, .portugueseBrazil, .italian, .dutch, .korean:
            recommendedModelNames = Self.multilingualRecommendedModelNames
        }

        let recommendationRanks = Dictionary(
            uniqueKeysWithValues: recommendedModelNames.enumerated().map { index, name in
                (name, index)
            }
        )

        return availableModels
            .filter { recommendedModelNames.contains($0.name) }
            .filter { $0.supports(language: language) }
            .sorted {
                recommendationRanks[$0.name, default: .max] < recommendationRanks[$1.name, default: .max]
            }
    }

    var recommendedModels: [WhisperModel] {
        recommendedModels(for: .english)
    }
    
    private(set) var downloadProgress: Double = 0.0
    private(set) var isDownloading: Bool = false
    private(set) var currentDownloadModel: String?
    private(set) var downloadedModelNames: Set<String> = []
    
    private(set) var featureDownloadProgress: Double = 0.0
    private(set) var isDownloadingFeature: Bool = false
    private(set) var currentDownloadingFeature: FeatureModelType?
    private(set) var downloadedFeatureModels: Set<FeatureModelType> = []
    
    private let fileManager = FileManager.default
    
    private var modelsBaseURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Pindrop", isDirectory: true)
    }

    private var whisperKitModelsURL: URL {
        modelsBaseURL
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
    }
    
    private var parakeetModelsURL: URL {
        modelsBaseURL.appendingPathComponent("FluidInference", isDirectory: true)
                     .appendingPathComponent("parakeet-coreml", isDirectory: true)
    }
    
    private var fluidAudioModelsURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    private func localModelPath(for model: WhisperModel) -> URL? {
        switch model.provider {
        case .whisperKit:
            return whisperKitModelsURL.appendingPathComponent(model.name, isDirectory: true)
        case .parakeet:
            let folderName = model.name.hasSuffix("-coreml") ? model.name : "\(model.name)-coreml"
            return parakeetModelsURL.appendingPathComponent(folderName, isDirectory: true)
        case .openAI, .elevenLabs, .groq:
            return nil
        }
    }
    
    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    
    init() {
        guard !Self.isPreview else { return }
    }
    
    func refreshDownloadedModels() async {
        var downloaded: Set<String> = []

        let whisperKitPath = whisperKitModelsURL

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
        
        if downloaded != downloadedModelNames {
            Log.model.debug("Found \(downloaded.count) downloaded models: \(downloaded)")
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
                logLevel: .none,
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
        guard let model = availableModels.first(where: { $0.name == modelName }) else {
            throw ModelError.modelNotFound(modelName)
        }

        guard let modelPath = localModelPath(for: model) else {
            throw ModelError.deleteFailed("Model \(modelName) is not stored locally")
        }

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
    
    // MARK: - Feature Models
    
    func isFeatureModelDownloaded(_ type: FeatureModelType) -> Bool {
        downloadedFeatureModels.contains(type)
    }
    
    func refreshDownloadedFeatureModels() async {
        var downloaded: Set<FeatureModelType> = []
        
        for type in FeatureModelType.allCases {
            let repoFolder = fluidAudioModelsURL.appendingPathComponent(type.repoFolderName)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: repoFolder.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                downloaded.insert(type)
            }
        }
        
        if downloaded != downloadedFeatureModels {
            Log.model.debug("Found \(downloaded.count) downloaded feature models: \(downloaded)")
        }
        downloadedFeatureModels = downloaded
    }
    
    func downloadFeatureModel(
        _ type: FeatureModelType,
        onProgress: ((Double) -> Void)? = nil
    ) async throws {
        guard !isDownloadingFeature else {
            throw ModelError.downloadFailed("Another feature download is in progress")
        }
        
        isDownloadingFeature = true
        currentDownloadingFeature = type
        featureDownloadProgress = 0.0
        
        defer {
            isDownloadingFeature = false
            currentDownloadingFeature = nil
        }
        
        Log.model.info("Downloading feature model: \(type.displayName)")
        
        do {
            switch type {
            case .vad:
                featureDownloadProgress = 0.1
                onProgress?(0.1)
                let _ = try await VadManager(config: .default)
                
            case .diarization:
                featureDownloadProgress = 0.1
                onProgress?(0.1)
                let _ = try await DiarizerModels.download()
                
            case .streaming:
                featureDownloadProgress = 0.1
                onProgress?(0.1)
                featureDownloadProgress = 0.3
                onProgress?(0.3)
                try await DownloadUtils.downloadRepo(
                    .parakeetEou160,
                    to: fluidAudioModelsURL
                )
            }
            
            featureDownloadProgress = 1.0
            onProgress?(1.0)
            
            Log.model.info("Feature model download complete: \(type.displayName)")
            await refreshDownloadedFeatureModels()
        } catch {
            featureDownloadProgress = 0.0
            Log.model.error("Feature model download failed: \(error.localizedDescription)")
            throw ModelError.downloadFailed(error.localizedDescription)
        }
    }
}
