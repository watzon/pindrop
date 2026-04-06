//
//  ModelManager.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import WhisperKit
import FluidAudio
#if canImport(PindropSharedTranscription)
import PindropSharedTranscription
#endif

@MainActor
@Observable
class ModelManager {
    nonisolated static let englishRecommendedModelNames = [
        "openai_whisper-base.en",
        "openai_whisper-small.en",
        "openai_whisper-medium",
        "openai_whisper-large-v3_turbo",
        "parakeet-tdt-0.6b-v2"
    ]

    nonisolated static let multilingualRecommendedModelNames = [
        "openai_whisper-base",
        "openai_whisper-small",
        "openai_whisper-medium",
        "openai_whisper-large-v3_turbo",
        "parakeet-tdt-0.6b-v3"
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
            TranscriptionPolicy.providerSupportsLocalModelLoading(self)
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
            TranscriptionPolicy.modelSupportsLanguage(self, language: language)
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

    enum DownloadPhase: Equatable, Sendable {
        case idle
        case listing
        case downloading(completedFiles: Int?, totalFiles: Int?)
        case compiling(modelName: String?)
        case preparing
        case completed
    }

    struct DownloadSnapshot: Equatable, Sendable {
        let modelName: String
        let progress: Double
        let phase: DownloadPhase
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
    
    let availableModels: [WhisperModel] = TranscriptionModelCatalog.availableModels

    func recommendedModels(for language: AppLanguage) -> [WhisperModel] {
        TranscriptionModelCatalog.recommendedModels(
            availableModels: availableModels,
            for: language
        )
    }

    var recommendedModels: [WhisperModel] {
        recommendedModels(for: .english)
    }
    
    private(set) var downloadProgress: Double = 0.0
    private(set) var downloadSnapshot: DownloadSnapshot?
    private(set) var isDownloading: Bool = false
    private(set) var currentDownloadModel: String?
    private(set) var downloadedModelNames: Set<String> = []
    
    private(set) var featureDownloadProgress: Double = 0.0
    private(set) var isDownloadingFeature: Bool = false
    private(set) var currentDownloadingFeature: FeatureModelType?
    private(set) var downloadedFeatureModels: Set<FeatureModelType> = []
    
    private let fileManager = FileManager.default
    #if canImport(PindropSharedTranscription)
    @ObservationIgnored
    private lazy var localRuntimeBridge = KMPTranscriptionRuntimeBridge(
        modelManager: self,
        engineFactory: TranscriptionService.defaultEngineFactory(provider:)
    )
    #endif
    
    /// Last decile (0...10) logged for WhisperKit file download progress to avoid log spam.
    private var whisperKitDownloadLastLoggedDecile: Int = -1
    
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

    static func parakeetDownloadSnapshot(
        modelName: String,
        progress: DownloadUtils.DownloadProgress
    ) -> DownloadSnapshot {
        let phase: DownloadPhase
        switch progress.phase {
        case .listing:
            phase = .listing
        case .downloading(let completedFiles, let totalFiles):
            phase = .downloading(completedFiles: completedFiles, totalFiles: totalFiles)
        case .compiling(let modelName):
            let normalizedModelName = modelName.isEmpty ? nil : modelName
            phase = .compiling(modelName: normalizedModelName)
        }

        return DownloadSnapshot(
            modelName: modelName,
            progress: progress.fractionCompleted,
            phase: phase
        )
    }

    static func whisperDownloadSnapshot(
        modelName: String,
        fileDownloadFraction: Double
    ) -> DownloadSnapshot {
        DownloadSnapshot(
            modelName: modelName,
            progress: fileDownloadFraction * 0.8,
            phase: .downloading(completedFiles: nil, totalFiles: nil)
        )
    }

    static func preparingDownloadSnapshot(
        modelName: String,
        progress: Double = 0.85
    ) -> DownloadSnapshot {
        DownloadSnapshot(
            modelName: modelName,
            progress: progress,
            phase: .preparing
        )
    }

    static func completedDownloadSnapshot(modelName: String) -> DownloadSnapshot {
        DownloadSnapshot(
            modelName: modelName,
            progress: 1.0,
            phase: .completed
        )
    }

    #if canImport(PindropSharedTranscription)
    static func runtimeInstallSnapshot(
        modelName: String,
        progress: ModelInstallProgress
    ) -> DownloadSnapshot {
        if progress.state == .installed {
            return completedDownloadSnapshot(modelName: modelName)
        }

        let phase = runtimeDownloadPhase(message: progress.message)
        return DownloadSnapshot(
            modelName: modelName,
            progress: progress.progress,
            phase: phase
        )
    }

    static func runtimeProgressMessage(for snapshot: DownloadSnapshot) -> String? {
        switch snapshot.phase {
        case .idle:
            return nil
        case .listing:
            return "__pindrop_phase__:listing"
        case .downloading(let completedFiles, let totalFiles):
            let completed = completedFiles.map(String.init) ?? ""
            let total = totalFiles.map(String.init) ?? ""
            return "__pindrop_phase__:downloading:\(completed):\(total)"
        case .compiling(let modelName):
            let normalizedModelName = modelName ?? ""
            return "__pindrop_phase__:compiling:\(normalizedModelName)"
        case .preparing:
            return "__pindrop_phase__:preparing"
        case .completed:
            return "__pindrop_phase__:completed"
        }
    }

    private static func runtimeDownloadPhase(message: String?) -> DownloadPhase {
        guard let message, message.hasPrefix("__pindrop_phase__:") else {
            return .downloading(completedFiles: nil, totalFiles: nil)
        }

        let components = message.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count >= 3 else {
            return .downloading(completedFiles: nil, totalFiles: nil)
        }

        switch components[2] {
        case "listing":
            return .listing
        case "downloading":
            let completedFiles = components.count > 3 ? Int(String(components[3])) : nil
            let totalFiles = components.count > 4 ? Int(String(components[4])) : nil
            return .downloading(completedFiles: completedFiles, totalFiles: totalFiles)
        case "compiling":
            let modelName = components.count > 3 ? String(components[3]) : ""
            return .compiling(modelName: modelName.isEmpty ? nil : modelName)
        case "preparing":
            return .preparing
        case "completed":
            return .completed
        default:
            return .downloading(completedFiles: nil, totalFiles: nil)
        }
    }
    #endif

    func updateDownloadSnapshot(
        _ snapshot: DownloadSnapshot,
        onProgress: ((DownloadSnapshot) -> Void)? = nil
    ) {
        let clampedSnapshot = DownloadSnapshot(
            modelName: snapshot.modelName,
            progress: max(0.0, min(snapshot.progress, 1.0)),
            phase: snapshot.phase
        )
        downloadSnapshot = clampedSnapshot
        downloadProgress = clampedSnapshot.progress
        onProgress?(clampedSnapshot)
    }

    func clearDownloadState(resetProgress: Bool) {
        downloadSnapshot = nil
        if resetProgress {
            downloadProgress = 0.0
        }
    }
    
    func refreshDownloadedModels() async {
        #if canImport(PindropSharedTranscription)
        let downloaded = await localRuntimeBridge.refreshInstalledModelNames()
        if downloaded != downloadedModelNames {
            Log.model.debug("Found \(downloaded.count) downloaded models via KMP runtime: \(downloaded)")
        }
        downloadedModelNames = downloaded
        #else
        await refreshDownloadedModelsFromDisk()
        #endif
    }

    private func refreshDownloadedModelsFromDisk() async {
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
    
    func downloadModel(named modelName: String, onProgress: ((DownloadSnapshot) -> Void)? = nil) async throws {
        guard let model = availableModels.first(where: { $0.name == modelName }) else {
            throw ModelError.modelNotFound(modelName)
        }
        
        guard !isDownloading else {
            Log.boot.error("downloadModel rejected: another download in progress current=\(currentDownloadModel ?? "nil")")
            throw ModelError.downloadFailed("Another download is in progress")
        }
        
        Log.boot.info("ModelManager.downloadModel begin name=\(modelName) provider=\(model.provider.rawValue)")
        let downloadWallClock = CFAbsoluteTimeGetCurrent()
        
        isDownloading = true
        currentDownloadModel = modelName
        clearDownloadState(resetProgress: true)
        
        defer {
            isDownloading = false
            currentDownloadModel = nil
        }

        #if canImport(PindropSharedTranscription)
        if model.provider.isLocal {
            try await localRuntimeBridge.installModel(named: modelName, onProgress: onProgress)
        } else {
            throw ModelError.downloadNotImplemented(model.provider.rawValue)
        }
        #else
        try await installModelArtifacts(named: modelName, onProgress: onProgress)
        #endif
        Log.boot.info("ModelManager.downloadModel finished OK name=\(modelName) wallClock=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - downloadWallClock))")
    }

    func installModelArtifacts(
        named modelName: String,
        onProgress: ((DownloadSnapshot) -> Void)? = nil
    ) async throws {
        guard let model = availableModels.first(where: { $0.name == modelName }) else {
            throw ModelError.modelNotFound(modelName)
        }

        if model.provider == .parakeet {
            try await downloadParakeetModel(named: modelName, onProgress: onProgress)
        } else if model.provider == .whisperKit {
            try await downloadWhisperKitModel(named: modelName, onProgress: onProgress)
        } else {
            throw ModelError.downloadNotImplemented(model.provider.rawValue)
        }
    }
    
    private func downloadWhisperKitModel(
        named modelName: String,
        onProgress: ((DownloadSnapshot) -> Void)? = nil
    ) async throws {
        whisperKitDownloadLastLoggedDecile = -1
        let pipelineStart = CFAbsoluteTimeGetCurrent()
        do {
            Log.model.info("Downloading WhisperKit model: \(modelName) to \(self.modelsBaseURL.path)")
            Log.boot.info(
                "WhisperKit pipeline begin variant=\(modelName) storageLeaf=Pindrop/models/argmaxinc/whisperkit-coreml (under Application Support) uiProgressNote=0-80pct is file download 85-100pct is prewarm"
            )
            
            let mkdirStart = CFAbsoluteTimeGetCurrent()
            try fileManager.createDirectory(at: self.modelsBaseURL, withIntermediateDirectories: true)
            Log.boot.info("WhisperKit storage directories ensured elapsed=\(String(format: "%.3fs", CFAbsoluteTimeGetCurrent() - mkdirStart))")
            
            let fileDownloadStart = CFAbsoluteTimeGetCurrent()
            Log.boot.info("WhisperKit.download starting")
            _ = try await WhisperKit.download(
                variant: modelName,
                downloadBase: self.modelsBaseURL,
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        guard let self else { return }
                        let fraction = progress.fractionCompleted
                        let decile = min(10, Int(fraction * 10.0001))
                        if decile > self.whisperKitDownloadLastLoggedDecile || fraction >= 1.0 {
                            self.whisperKitDownloadLastLoggedDecile = max(self.whisperKitDownloadLastLoggedDecile, decile)
                            Log.boot.info("WhisperKit.download progress fraction=\(String(format: "%.3f", fraction)) uiMapped=\(String(format: "%.3f", fraction * 0.8))")
                        }
                        self.updateDownloadSnapshot(
                            Self.whisperDownloadSnapshot(
                                modelName: modelName,
                                fileDownloadFraction: fraction
                            ),
                            onProgress: onProgress
                        )
                    }
                }
            )
            Log.boot.info("WhisperKit.download finished elapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - fileDownloadStart))")
            
            Log.model.info("Download complete, prewarming model...")
            updateDownloadSnapshot(
                Self.preparingDownloadSnapshot(modelName: modelName),
                onProgress: onProgress
            )
            Log.boot.info("Entering prewarm phase (WhisperKitConfig prewarm=true load=false) — UI shows ~85% \"Preparing Model\"")
            
            let prewarmStart = CFAbsoluteTimeGetCurrent()
            let config = WhisperKitConfig(
                model: modelName,
                downloadBase: self.modelsBaseURL,
                verbose: false,
                logLevel: .none,
                prewarm: true,
                load: false
            )
            _ = try await WhisperKit(config)
            Log.boot.info("WhisperKit prewarm (init) completed elapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - prewarmStart))")
            
            Log.model.info("Model prewarmed successfully")
            updateDownloadSnapshot(
                Self.completedDownloadSnapshot(modelName: modelName),
                onProgress: onProgress
            )
            await refreshDownloadedModels()
            Log.boot.info("WhisperKit pipeline success totalElapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - pipelineStart)) downloadedModelsCount=\(downloadedModelNames.count)")
        } catch {
            clearDownloadState(resetProgress: true)
            let nsError = error as NSError
            Log.boot.error(
                "WhisperKit pipeline failed after \(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - pipelineStart)) domain=\(nsError.domain) code=\(nsError.code) description=\(error.localizedDescription)"
            )
            throw ModelError.downloadFailed(error.localizedDescription)
        }
    }
    
    private func downloadParakeetModel(
        named modelName: String,
        onProgress: ((DownloadSnapshot) -> Void)? = nil
    ) async throws {
        let pipelineStart = CFAbsoluteTimeGetCurrent()
        Log.model.info("Parakeet model download requested: \(modelName)")
        Log.model.info("Parakeet models path: \(self.parakeetModelsURL.path)")
        Log.boot.info("Parakeet pipeline begin name=\(modelName)")
        
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
            Log.boot.info("Parakeet storage directory ready")
        } catch {
            Log.boot.error("Parakeet mkdir failed: \(error.localizedDescription)")
            throw ModelError.downloadFailed("Failed to create Parakeet models directory: \(error.localizedDescription)")
        }

        Log.model.info("Starting Parakeet model download (version: \(version == .v3 ? "v3" : "v2"))")
        Log.boot.info("Parakeet AsrModels.downloadAndLoad starting version=\(version == .v3 ? "v3" : "v2")")
        
        do {
            let targetDir = parakeetModelsURL.appendingPathComponent(
                version == .v3 ? "parakeet-tdt-0.6b-v3-coreml" : "parakeet-tdt-0.6b-v2-coreml",
                isDirectory: true
            )

            let fetchStart = CFAbsoluteTimeGetCurrent()
            _ = try await AsrModels.downloadAndLoad(
                to: targetDir,
                version: version,
                progressHandler: { [weak self] progress in
                    Task { @MainActor in
                        guard let self else { return }
                        self.updateDownloadSnapshot(
                            Self.parakeetDownloadSnapshot(modelName: modelName, progress: progress),
                            onProgress: onProgress
                        )
                    }
                }
            )
            Log.boot.info("Parakeet AsrModels.downloadAndLoad finished elapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - fetchStart))")
            
            Log.model.info("Parakeet model download complete")
            updateDownloadSnapshot(
                Self.completedDownloadSnapshot(modelName: modelName),
                onProgress: onProgress
            )
            
            await refreshDownloadedModels()
            Log.boot.info("Parakeet pipeline success totalElapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - pipelineStart))")
        } catch {
            clearDownloadState(resetProgress: true)
            let nsError = error as NSError
            Log.boot.error("Parakeet pipeline failed domain=\(nsError.domain) code=\(nsError.code) description=\(error.localizedDescription)")
            Log.model.error("Parakeet model download failed: \(error.localizedDescription)")
            throw ModelError.downloadFailed(error.localizedDescription)
        }
    }
    
    func deleteModel(named modelName: String) async throws {
        guard availableModels.contains(where: { $0.name == modelName }) else {
            throw ModelError.modelNotFound(modelName)
        }

        #if canImport(PindropSharedTranscription)
        try await localRuntimeBridge.deleteModel(named: modelName)
        await refreshDownloadedModels()
        return
        #else
        try await deleteModelArtifacts(named: modelName)
        await refreshDownloadedModels()
        #endif
    }

    func deleteModelArtifacts(named modelName: String) async throws {
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

extension ModelManager: ModelCatalogProviding {}
