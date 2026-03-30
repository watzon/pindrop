//
//  NativeTranscriptionAdapters.swift
//  Pindrop
//
//  Created on 2026-03-28.
//

import AVFoundation
import Foundation

@MainActor
final class WhisperKitTranscriptionAdapter: TranscriptionEnginePort {
    private let engine: WhisperKitEngine

    init() {
        self.engine = WhisperKitEngine()
    }

    init(engine: WhisperKitEngine) {
        self.engine = engine
    }

    var state: TranscriptionEngineState { engine.state }

    func loadModel(path: String) async throws {
        try await engine.loadModel(path: path)
    }

    func loadModel(name: String, downloadBase: URL?) async throws {
        try await engine.loadModel(name: name, downloadBase: downloadBase)
    }

    func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String {
        try await engine.transcribe(audioData: audioData, options: options)
    }

    func unloadModel() async {
        await engine.unloadModel()
    }
}

@MainActor
final class ParakeetTranscriptionAdapter: TranscriptionEnginePort {
    private let engine: ParakeetEngine

    init() {
        self.engine = ParakeetEngine()
    }

    init(engine: ParakeetEngine) {
        self.engine = engine
    }

    var state: TranscriptionEngineState { engine.state }

    func loadModel(path: String) async throws {
        try await engine.loadModel(path: path)
    }

    func loadModel(name: String, downloadBase: URL?) async throws {
        try await engine.loadModel(name: name, downloadBase: downloadBase)
    }

    func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String {
        try await engine.transcribe(audioData: audioData, options: options)
    }

    func unloadModel() async {
        await engine.unloadModel()
    }
}

@MainActor
final class ParakeetStreamingAdapter: StreamingTranscriptionEnginePort {
    private let engine: ParakeetStreamingEngine

    init() {
        self.engine = ParakeetStreamingEngine()
    }

    init(engine: ParakeetStreamingEngine) {
        self.engine = engine
    }

    var state: StreamingTranscriptionState { engine.state }

    func loadModel(name: String) async throws {
        try await engine.loadModel(name: name)
    }

    func unloadModel() async {
        await engine.unloadModel()
    }

    func startStreaming() async throws {
        try await engine.startStreaming()
    }

    func stopStreaming() async throws -> String {
        try await engine.stopStreaming()
    }

    func pauseStreaming() async {
        await engine.pauseStreaming()
    }

    func resumeStreaming() async throws {
        try await engine.resumeStreaming()
    }

    func processAudioChunk(_ samples: [Float]) async throws {
        try await engine.processAudioChunk(samples)
    }

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {
        try await engine.processAudioBuffer(buffer)
    }

    func setTranscriptionCallback(_ callback: @escaping StreamingTranscriptionCallback) {
        engine.setTranscriptionCallback(callback)
    }

    func setEndOfUtteranceCallback(_ callback: @escaping EndOfUtteranceCallback) {
        engine.setEndOfUtteranceCallback(callback)
    }

    func reset() async {
        await engine.reset()
    }
}

@MainActor
final class MacOSModelCatalogAdapter: ModelCatalogProviding {
    private let modelManager: ModelManager

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    var availableModels: [ModelManager.WhisperModel] {
        modelManager.availableModels
    }

    var recommendedModels: [ModelManager.WhisperModel] {
        modelManager.recommendedModels
    }

    func recommendedModels(for language: AppLanguage) -> [ModelManager.WhisperModel] {
        modelManager.recommendedModels(for: language)
    }

    func isModelDownloaded(_ modelName: String) -> Bool {
        modelManager.isModelDownloaded(modelName)
    }
}

@MainActor
final class MacOSSettingsSnapshotAdapter: SettingsSnapshotProvider {
    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func transcriptionSettingsSnapshot() -> TranscriptionSettingsSnapshot {
        TranscriptionSettingsSnapshot(
            selectedLanguage: settingsStore.selectedAppLanguage,
            selectedModelName: settingsStore.selectedModel,
            aiEnhancementEnabled: settingsStore.aiEnhancementEnabled,
            streamingFeatureEnabled: settingsStore.streamingFeatureEnabled,
            diarizationFeatureEnabled: settingsStore.diarizationFeatureEnabled
        )
    }
}

import PindropSharedTranscription

@MainActor
final class KMPTranscriptionRuntimeBridge {
    private let modelManager: ModelManager
    private let backendRegistry: MacOSRuntimeBackendRegistry
    private let runtime: LocalTranscriptionRuntime

    init(
        modelManager: ModelManager,
        engineFactory: @escaping @MainActor (ModelManager.ModelProvider) throws -> any TranscriptionEngine
    ) {
        self.modelManager = modelManager
        self.backendRegistry = MacOSRuntimeBackendRegistry(engineFactory: engineFactory)
        let installedIndex = MacOSInstalledModelIndexAdapter(modelManager: modelManager)
        let installer = MacOSModelInstallerAdapter(modelManager: modelManager)
        self.runtime = LocalTranscriptionRuntime(
            platform: .macos,
            installedModelIndex: installedIndex,
            modelInstaller: installer,
            backendRegistry: backendRegistry,
            observer: nil
        )
    }

    func refreshInstalledModelNames() async -> Set<String> {
        do {
            let records = try await refreshInstalledModels()
            return Set(records.map(\.modelId.value))
        } catch {
            Log.model.error("KMP runtime refresh failed: \(error.localizedDescription)")
            return []
        }
    }

    func refreshInstalledModels() async throws -> [InstalledModelRecord] {
        try await withCheckedThrowingContinuation { continuation in
            runtime.refreshInstalledModels { records, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: records ?? [])
                }
            }
        }
    }

    func installModel(
        named modelName: String,
        onProgress: ((Double) -> Void)? = nil
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            runtime.installModel(modelId: TranscriptionModelId(value: modelName)) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    onProgress?(1.0)
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func loadModel(
        named modelName: String,
        provider: ModelManager.ModelProvider
    ) async throws -> (any TranscriptionEnginePort) {
        let backendProvider = effectiveRuntimeProvider(for: provider)
        _ = try await refreshInstalledModels()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            runtime.loadModel(modelId: TranscriptionModelId(value: modelName)) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
        try validateRuntimeLoadSucceeded(modelName: modelName)

        guard let engine = backendRegistry.engine(for: backendProvider) else {
            throw TranscriptionService.TranscriptionError.modelLoadFailed(
                "No runtime engine available for \(backendProvider.rawValue)"
            )
        }
        return engine
    }

    func loadModel(fromPath path: String) async throws -> (any TranscriptionEnginePort) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            runtime.loadModelFromPath(path: path, family: .whisper) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
        try validateRuntimePathLoadSucceeded(path: path)

        guard let engine = backendRegistry.engine(for: .whisperKit) else {
            throw TranscriptionService.TranscriptionError.modelLoadFailed(
                "No runtime engine available for WhisperKit"
            )
        }
        return engine
    }

    func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String {
        let request = TranscriptionRequest(
            audioData: KotlinByteArray.from(data: audioData),
            language: options.language.transcriptionLanguage,
            diarizationEnabled: false,
            customVocabularyWords: options.customVocabularyWords
        )

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<TranscriptionResult, Error>) in
            runtime.transcribe(request: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(
                        throwing: TranscriptionService.TranscriptionError.transcriptionFailed(
                            "Runtime returned no transcription result"
                        )
                    )
                }
            }
        }

        return result.text
    }

    func unloadModel() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            runtime.unloadModel { _ in
                continuation.resume(returning: ())
            }
        }
    }

    func engine(for provider: ModelManager.ModelProvider) -> (any TranscriptionEnginePort)? {
        backendRegistry.engine(for: effectiveRuntimeProvider(for: provider))
    }

    func effectiveRuntimeProvider(for provider: ModelManager.ModelProvider) -> ModelManager.ModelProvider {
        switch provider {
        case .whisperKit, .parakeet:
            provider
        case .openAI, .elevenLabs, .groq:
            .whisperKit
        }
    }

    func deleteModel(named modelName: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            runtime.deleteModel(modelId: TranscriptionModelId(value: modelName)) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func validateRuntimeLoadSucceeded(modelName: String) throws {
        if runtime.state == .ready, runtime.activeModel?.descriptor.id.value == modelName {
            return
        }

        throw TranscriptionService.TranscriptionError.modelLoadFailed(
            runtime.lastErrorMessage ??
                "Runtime failed to load model '\(modelName)' (\(runtime.lastErrorCode?.name ?? "unknown_error"))"
        )
    }

    private func validateRuntimePathLoadSucceeded(path: String) throws {
        if runtime.state == .ready {
            return
        }

        throw TranscriptionService.TranscriptionError.modelLoadFailed(
            runtime.lastErrorMessage ??
                "Runtime failed to load model at path '\(path)' (\(runtime.lastErrorCode?.name ?? "unknown_error"))"
        )
    }
}

private final class MacOSInstalledModelIndexAdapter: NSObject, InstalledModelIndexPort {
    private let modelManager: ModelManager
    private let fileManager = FileManager.default

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    func refreshInstalledModels(completionHandler: @escaping ([InstalledModelRecord]?, (any Error)?) -> Void) {
        let installRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Pindrop", isDirectory: true)
        let whisperRoot = installRoot
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
        let parakeetRoot = installRoot
            .appendingPathComponent("FluidInference", isDirectory: true)
            .appendingPathComponent("parakeet-coreml", isDirectory: true)

        let records = modelManager.availableModels.compactMap { model -> InstalledModelRecord? in
            switch model.provider {
            case .whisperKit:
                let modelPath = whisperRoot.appendingPathComponent(model.name, isDirectory: true)
                guard directoryExists(at: modelPath) else { return nil }
                return InstalledModelRecord(
                    modelId: TranscriptionModelId(value: model.name),
                    state: .installed,
                    storage: ModelStorageLayout(
                        installRootPath: whisperRoot.path,
                        modelPath: modelPath.path
                    ),
                    installedProvider: .whisperKit,
                    lastError: nil
                )
            case .parakeet:
                let folderName = model.name.hasSuffix("-coreml") ? model.name : "\(model.name)-coreml"
                let modelPath = parakeetRoot.appendingPathComponent(folderName, isDirectory: true)
                guard directoryExists(at: modelPath) else { return nil }
                return InstalledModelRecord(
                    modelId: TranscriptionModelId(value: model.name),
                    state: .installed,
                    storage: ModelStorageLayout(
                        installRootPath: parakeetRoot.path,
                        modelPath: modelPath.path
                    ),
                    installedProvider: .parakeetCoreml,
                    lastError: nil
                )
            case .openAI, .elevenLabs, .groq:
                return nil
            }
        }

        completionHandler(records, nil)
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

@MainActor
private final class MacOSModelInstallerAdapter: NSObject, @preconcurrency ModelInstallerPort {
    private let modelManager: ModelManager

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    func installModel(
        model: LocalModelDescriptor,
        onProgress: @escaping (ModelInstallProgress) -> Void,
        completionHandler: @escaping (InstalledModelRecord?, (any Error)?) -> Void
    ) {
        Task { @MainActor in
            do {
                try await modelManager.installModelArtifacts(named: model.id.value) { progress in
                    onProgress(
                        ModelInstallProgress(
                            modelId: model.id,
                            progress: progress,
                            state: progress >= 1.0 ? .installed : .installing,
                            message: nil
                        )
                    )
                }

                let records = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[InstalledModelRecord], Error>) in
                    MacOSInstalledModelIndexAdapter(modelManager: modelManager)
                        .refreshInstalledModels { records, error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: records ?? [])
                            }
                        }
                }
                completionHandler(records.first { $0.modelId.value == model.id.value }, nil)
            } catch {
                completionHandler(nil, error)
            }
        }
    }

    func deleteModel(model: LocalModelDescriptor, completionHandler: @escaping ((any Error)?) -> Void) {
        Task { @MainActor in
            do {
                try await modelManager.deleteModelArtifacts(named: model.id.value)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }
}

@MainActor
private final class MacOSRuntimeBackendRegistry: NSObject, @preconcurrency BackendRegistryPort {
    private let whisperBackend: RuntimeBackedLocalEngineAdapter
    private let parakeetBackend: RuntimeBackedLocalEngineAdapter

    init(
        engineFactory: @escaping @MainActor (ModelManager.ModelProvider) throws -> any TranscriptionEngine
    ) {
        self.whisperBackend = RuntimeBackedLocalEngineAdapter(
            backendId: .whisperKit,
            provider: .whisperKit,
            supportedFamilies: [.whisper],
            supportsPathLoading: true,
            engineFactory: engineFactory
        )
        self.parakeetBackend = RuntimeBackedLocalEngineAdapter(
            backendId: .parakeetApple,
            provider: .parakeet,
            supportedFamilies: [.parakeet],
            supportsPathLoading: false,
            engineFactory: engineFactory
        )
    }

    func preferredBackend(model: LocalModelDescriptor) -> LocalBackendId? {
        switch model.family {
        case .whisper:
            return .whisperKit
        case .parakeet:
            return .parakeetApple
        default:
            return nil
        }
    }

    func backend(id: LocalBackendId) -> LocalInferenceBackendPort? {
        switch id {
        case .whisperKit:
            whisperBackend
        case .parakeetApple:
            parakeetBackend
        default:
            nil
        }
    }

    func engine(for provider: ModelManager.ModelProvider) -> (any TranscriptionEnginePort)? {
        switch provider {
        case .whisperKit:
            whisperBackend.serviceEngine
        case .parakeet:
            parakeetBackend.serviceEngine
        case .openAI, .elevenLabs, .groq:
            nil
        }
    }
}

@MainActor
private final class RuntimeBackedLocalEngineAdapter: NSObject, @preconcurrency LocalInferenceBackendPort {
    let backendId: LocalBackendId
    let supportedFamilies: Set<LocalModelFamily>
    let supportsPathLoading: Bool

    private let provider: ModelManager.ModelProvider
    private let engineFactory: @MainActor (ModelManager.ModelProvider) throws -> any TranscriptionEngine
    private var engine: (any TranscriptionEnginePort)?
    fileprivate lazy var serviceEngine = RuntimeBackedTranscriptionEngineProxy(owner: self)

    init(
        backendId: LocalBackendId,
        provider: ModelManager.ModelProvider,
        supportedFamilies: Set<LocalModelFamily>,
        supportsPathLoading: Bool,
        engineFactory: @escaping @MainActor (ModelManager.ModelProvider) throws -> any TranscriptionEngine
    ) {
        self.backendId = backendId
        self.provider = provider
        self.supportedFamilies = supportedFamilies
        self.supportsPathLoading = supportsPathLoading
        self.engineFactory = engineFactory
    }

    fileprivate var state: TranscriptionEngineState {
        engine?.state ?? .unloaded
    }

    fileprivate func loadModel(path: String) async throws {
        try await resolvedEngine().loadModel(path: path)
    }

    fileprivate func loadModel(name: String, downloadBase: URL?) async throws {
        try await resolvedEngine().loadModel(name: name, downloadBase: downloadBase)
    }

    fileprivate func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String {
        try await resolvedEngine().transcribe(audioData: audioData, options: options)
    }

    fileprivate func unloadServiceEngine() async {
        await engine?.unloadModel()
        engine = nil
    }

    func loadModel(
        model: LocalModelDescriptor,
        installedRecord: InstalledModelRecord?,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        Task { @MainActor in
            do {
                switch provider {
                case .whisperKit:
                    if let modelPath = installedRecord?.storage.modelPath {
                        try await loadModel(path: modelPath)
                    } else {
                        let downloadBase = installedRecord.map {
                            URL(fileURLWithPath: $0.storage.installRootPath)
                                .deletingLastPathComponent()
                                .deletingLastPathComponent()
                                .deletingLastPathComponent()
                        }
                        try await loadModel(name: model.id.value, downloadBase: downloadBase)
                    }
                case .parakeet:
                    try await loadModel(name: model.id.value, downloadBase: nil)
                case .openAI, .elevenLabs, .groq:
                    throw TranscriptionService.TranscriptionError.modelLoadFailed(
                        "Provider \(provider.rawValue) not supported locally"
                    )
                }
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    func loadModelFromPath(path: String, completionHandler: @escaping ((any Error)?) -> Void) {
        Task { @MainActor in
            do {
                try await loadModel(path: path)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    func transcribe(
        request: TranscriptionRequest,
        completionHandler: @escaping (TranscriptionResult?, (any Error)?) -> Void
    ) {
        Task { @MainActor in
            do {
                let text = try await transcribe(
                    audioData: request.audioData.dataValue,
                    options: TranscriptionOptions(
                        language: request.language.appLanguage,
                        customVocabularyWords: request.customVocabularyWords
                    )
                )
                completionHandler(TranscriptionResult(text: text, diarizedSegments: []), nil)
            } catch {
                completionHandler(nil, error)
            }
        }
    }

    func unloadModel(completionHandler: @escaping ((any Error)?) -> Void) {
        Task { @MainActor in
            await unloadServiceEngine()
            completionHandler(nil)
        }
    }

    private func resolvedEngine() throws -> any TranscriptionEnginePort {
        if let engine {
            return engine
        }

        let created = try engineFactory(provider)
        engine = created
        return created
    }
}

@MainActor
private final class RuntimeBackedTranscriptionEngineProxy: TranscriptionEnginePort {
    private unowned let owner: RuntimeBackedLocalEngineAdapter

    init(owner: RuntimeBackedLocalEngineAdapter) {
        self.owner = owner
    }

    var state: TranscriptionEngineState {
        owner.state
    }

    func loadModel(path: String) async throws {
        try await owner.loadModel(path: path)
    }

    func loadModel(name: String, downloadBase: URL?) async throws {
        try await owner.loadModel(name: name, downloadBase: downloadBase)
    }

    func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String {
        try await owner.transcribe(audioData: audioData, options: options)
    }

    func unloadModel() async {
        await owner.unloadServiceEngine()
    }
}

private extension KotlinByteArray {
    static func from(data: Data) -> KotlinByteArray {
        let bytes = [UInt8](data)
        return KotlinByteArray(size: Int32(bytes.count)) { index in
            KotlinByte(char: Int8(truncatingIfNeeded: bytes[Int(index)]))
        }
    }

    var dataValue: Data {
        var bytes = [UInt8]()
        bytes.reserveCapacity(Int(size))
        for index in 0..<Int(size) {
            bytes.append(UInt8(bitPattern: get(index: Int32(index))))
        }
        return Data(bytes)
    }
}

private extension AppLanguage {
    var transcriptionLanguage: TranscriptionLanguage {
        switch self {
        case .automatic:
            .automatic
        case .english:
            .english
        case .simplifiedChinese:
            .simplifiedChinese
        case .spanish:
            .spanish
        case .french:
            .french
        case .german:
            .german
        case .turkish:
            .turkish
        case .japanese:
            .japanese
        case .portugueseBrazil:
            .portugueseBrazil
        case .italian:
            .italian
        case .dutch:
            .dutch
        case .korean:
            .korean
        }
    }
}

private extension TranscriptionLanguage {
    var appLanguage: AppLanguage {
        switch self {
        case .automatic:
            .automatic
        case .english:
            .english
        case .simplifiedChinese:
            .simplifiedChinese
        case .spanish:
            .spanish
        case .french:
            .french
        case .german:
            .german
        case .turkish:
            .turkish
        case .japanese:
            .japanese
        case .portugueseBrazil:
            .portugueseBrazil
        case .italian:
            .italian
        case .dutch:
            .dutch
        case .korean:
            .korean
        default:
            .automatic
        }
    }
}
