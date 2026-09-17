//
//  ModelManager.swift
//  PindropSpeech
//
//  Created on 2026-01-25.
//

import Foundation
import WhisperKit
import FluidAudio
import PindropCore

@MainActor
@Observable
public final class ModelManager {
    /// Optional host telemetry peer for download lifecycle events.
    /// Download start/failure signals are dropped entirely when nil.
    @ObservationIgnored public private(set) var modelDownloadEventReporter: (any ModelDownloadEventReporting)?

    public nonisolated static let englishRecommendedModelNames = [
        "apple_speech_on_device",
        "openai_whisper-base.en",
        "openai_whisper-small.en",
        "openai_whisper-medium",
        "openai_whisper-large-v3_turbo",
        "parakeet-tdt-0.6b-v2"
    ]

    public nonisolated static let multilingualRecommendedModelNames = [
        "apple_speech_on_device",
        "openai_whisper-base",
        "openai_whisper-small",
        "openai_whisper-medium",
        "openai_whisper-large-v3_turbo",
        "parakeet-tdt-0.6b-v3"
    ]

    public nonisolated static let recommendedModelNames = englishRecommendedModelNames
    public nonisolated static let recommendedModelNameSet: Set<String> = Set(englishRecommendedModelNames)

    
    public enum ModelProvider: String, CaseIterable, Sendable {
        case whisperKit = "WhisperKit"
        case parakeet = "Parakeet"
        case senseVoice = "SenseVoice"
        case appleSpeech = "Apple Speech"
        case openAI = "OpenAI"
        case elevenLabs = "ElevenLabs"
        case groq = "Groq"

        public var isLocal: Bool {
            switch self {
            case .whisperKit, .parakeet, .senseVoice, .appleSpeech: return true
            case .openAI, .elevenLabs, .groq: return false
            }
        }

        public var iconName: String {
            switch self {
            case .whisperKit: return "waveform"
            case .parakeet: return "bird"
            case .senseVoice: return "globe.asia.australia"
            case .appleSpeech: return "apple.logo"
            case .openAI: return "sparkles"
            case .elevenLabs: return "waveform.circle"
            case .groq: return "bolt"
            }
        }

        public var credentialStorageKey: String {
            switch self {
            case .openAI: return "openai"
            case .elevenLabs: return "elevenlabs"
            case .groq: return "groq"
            case .whisperKit, .parakeet, .senseVoice, .appleSpeech:
                return rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
            }
        }
    }
    
    public enum ModelLanguage: String, Sendable {
        case english = "English-only"
        case multilingual = "Multilingual"
    }

    public enum LanguageSupport: Sendable {
        case englishOnly
        case fullMultilingual
        case parakeetV3European

        public enum BadgeTone: Sendable {
            case normal
            case caution
        }

        public struct BadgePresentation: Sendable {
            public let iconName: String
            public let text: String
            public let tone: BadgeTone

            public init(iconName: String, text: String, tone: BadgeTone) {
                self.iconName = iconName
                self.text = text
                self.tone = tone
            }
        }

        public func supports(_ language: AppLanguage) -> Bool {
            guard language != .automatic else { return true }

            switch self {
            case .englishOnly:
                return language.isEnglish
            case .fullMultilingual:
                return true
            case .parakeetV3European:
                switch language {
                case .automatic, .english, .russian, .ukrainian, .spanish, .french, .german, .portugueseBrazil, .italian, .dutch, .turkish, .polish:
                    return true
                case .simplifiedChinese, .japanese, .korean, .hindi, .malayalam:
                    return false
                }
            }
        }

        public var badgeText: String {
            switch self {
            case .englishOnly:
                return "English-only"
            case .fullMultilingual:
                return "Multilingual"
            case .parakeetV3European:
                return "European multilingual"
            }
        }

        public var badgeIconName: String {
            switch self {
            case .englishOnly:
                return "textformat"
            case .fullMultilingual, .parakeetV3European:
                return "globe"
            }
        }

        public func badgePresentation(for language: AppLanguage) -> BadgePresentation {
            BadgePresentation(
                iconName: badgeIconName,
                text: badgeText,
                tone: supports(language) ? .normal : .caution
            )
        }
    }
    
    public enum ModelAvailability: Equatable, Sendable {
        case available
        case comingSoon
        case requiresSetup
    }

    public enum DownloadPhase: Equatable, Sendable {
        case idle
        case listing
        case downloading(completedFiles: Int?, totalFiles: Int?)
        case compiling(modelName: String?)
        case preparing
        case completed
    }

    public struct DownloadSnapshot: Equatable, Sendable {
        public let modelName: String
        public let progress: Double
        public let phase: DownloadPhase

        public init(modelName: String, progress: Double, phase: DownloadPhase) {
            self.modelName = modelName
            self.progress = progress
            self.phase = phase
        }
    }
    
    public struct WhisperModel: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let displayName: String
        public let sizeInMB: Int
        public let description: String
        public let speedRating: Double?
        public let accuracyRating: Double?
        public let language: ModelLanguage
        public let languageSupport: LanguageSupport
        public let provider: ModelProvider
        public let availability: ModelAvailability
        
        public init(
            name: String,
            displayName: String,
            sizeInMB: Int,
            description: String = "",
            speedRating: Double? = 5.0,
            accuracyRating: Double? = 5.0,
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
        
        public var formattedSize: String {
            if sizeInMB >= 1000 {
                return String(format: "%.1f GB", Double(sizeInMB) / 1000.0)
            } else {
                return "\(sizeInMB) MB"
            }
        }

        public func supports(language: AppLanguage) -> Bool {
            languageSupport.supports(language)
        }

        public func languageBadgePresentation(for language: AppLanguage) -> LanguageSupport.BadgePresentation {
            languageSupport.badgePresentation(for: language)
        }
    }
    
    public enum ModelError: Error, LocalizedError {
        case modelNotFound(String)
        case downloadFailed(String)
        case deleteFailed(String)
        case downloadNotImplemented(String)
        public var errorDescription: String? {
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
    
    public let availableModels: [WhisperModel] = {
        var models: [WhisperModel] = [
        // Apple Speech (on-device, uses system models — no download required)
        WhisperModel(
            name: "apple_speech_on_device",
            displayName: "Apple Speech",
            sizeInMB: 0,
            description: "Apple's built-in on-device speech recognition. No download required — uses system models.",
            speedRating: 9.5,
            accuracyRating: 8.0,
            language: .multilingual,
            languageSupport: .fullMultilingual,
            provider: .appleSpeech,
            availability: .available
        ),

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

        // SenseVoice (FunASR via FluidAudio CoreML / ANE)
        WhisperModel(
            name: "sensevoice-small",
            displayName: "SenseVoice Small",
            sizeInMB: 230,
            description: "FunASR SenseVoice-Small — ultra-fast non-autoregressive multilingual ASR with built-in punctuation (CoreML / Apple Neural Engine)",
            speedRating: 9.8,
            accuracyRating: 8.8,
            language: .multilingual,
            languageSupport: .fullMultilingual,
            provider: .senseVoice,
            availability: .available
        ),
        
        // Cloud providers
        WhisperModel(
            name: "openai_gpt-4o-mini-transcribe",
            displayName: "OpenAI GPT-4o Mini Transcribe",
            sizeInMB: 0,
            description: "OpenAI's recommended model for fast, accurate cloud transcription",
            speedRating: 9.5,
            accuracyRating: 9.8,
            language: .multilingual,
            provider: .openAI,
            availability: .available
        ),
        WhisperModel(
            name: "openai_gpt-4o-transcribe",
            displayName: "OpenAI GPT-4o Transcribe",
            sizeInMB: 0,
            description: "High-quality cloud transcription through the OpenAI Audio API",
            speedRating: 9.0,
            accuracyRating: 9.6,
            language: .multilingual,
            provider: .openAI,
            availability: .available
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
        #if os(macOS)
        models.append(WhisperModel(
            name: ParakeetEngine.orukeetModelName,
            displayName: "Orukeet",
            sizeInMB: 467,
            speedRating: nil,
            accuracyRating: nil,
            language: .multilingual,
            languageSupport: .parakeetV3European,
            provider: .parakeet
        ))
        #endif
        return models
    }()

    public func recommendedModels(for language: AppLanguage) -> [WhisperModel] {
        let recommendedModelNames: [String]
        switch language {
        case .english:
            recommendedModelNames = Self.englishRecommendedModelNames
        case .automatic, .russian, .ukrainian, .simplifiedChinese, .spanish, .french, .german, .turkish, .japanese, .portugueseBrazil, .italian, .dutch, .korean, .hindi, .malayalam, .polish:
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

    public var recommendedModels: [WhisperModel] {
        recommendedModels(for: .english)
    }
    
    public private(set) var downloadProgress: Double = 0.0
    public private(set) var isDownloading: Bool = false
    public private(set) var currentDownloadModel: String?
    public private(set) var downloadSnapshot: DownloadSnapshot?
    public private(set) var downloadedModelNames: Set<String> = []
    
    public private(set) var featureDownloadProgress: Double = 0.0
    public private(set) var isDownloadingFeature: Bool = false
    public private(set) var currentDownloadingFeature: FeatureModelType?
    public private(set) var downloadedFeatureModels: Set<FeatureModelType> = []
    
    private let fileManager = FileManager.default
    private let storageLocations: ModelStorageLocations

    /// Vendor download hooks used only where static third-party APIs prevent observation.
    /// Defaults preserve production WhisperKit/FluidAudio behavior and never expose vendor types.
    struct DownloadOperations: Sendable {
        var downloadWhisperKit: @Sendable (
            _ variant: String,
            _ downloadBase: URL,
            _ onProgress: @escaping @Sendable (Double) -> Void
        ) async throws -> Void
        var prewarmWhisperKit: @Sendable (_ modelName: String, _ downloadBase: URL) async throws -> Void
        var downloadAndLoadParakeet: @Sendable (
            _ repositoryDirectory: URL,
            _ versionLabel: String,
            _ onProgress: @escaping @Sendable (DownloadUtils.DownloadProgress) -> Void
        ) async throws -> Void
        var downloadSenseVoiceRepo: @Sendable (
            _ fluidAudioModelsRoot: URL,
            _ variant: String,
            _ onProgress: @escaping @Sendable (DownloadUtils.DownloadProgress) -> Void
        ) async throws -> Void
        var loadSenseVoiceModels: @Sendable (_ repositoryDirectory: URL, _ variant: String) throws -> Void
        var downloadOfflineDiarization: @Sendable (
            _ fluidAudioModelsRoot: URL,
            _ onProgress: @escaping @Sendable (DownloadUtils.DownloadProgress) -> Void
        ) async throws -> Void
        var downloadLiveDiarization: @Sendable (
            _ fluidAudioModelsRoot: URL,
            _ bundleFileName: String,
            _ onProgress: @escaping @Sendable (DownloadUtils.DownloadProgress) -> Void
        ) async throws -> Void
        var downloadStreamingRepo: @Sendable (
            _ fluidAudioModelsRoot: URL,
            _ repoFolderName: String
        ) async throws -> Void

        #if os(macOS)
        var prepareOrukeet: @Sendable (URL, @escaping @Sendable (Double) -> Void) async throws -> Void = { directory, progress in
            _ = try await OrukeetModelStore.prepare(at: directory, progress: progress)
        }
        #endif

        static func production() -> DownloadOperations {
            DownloadOperations(
                downloadWhisperKit: { variant, downloadBase, onProgress in
                    _ = try await WhisperKit.download(
                        variant: variant,
                        downloadBase: downloadBase,
                        progressCallback: { progress in
                            onProgress(progress.fractionCompleted)
                        }
                    )
                },
                prewarmWhisperKit: { modelName, downloadBase in
                    let config = WhisperKitConfig(
                        model: modelName,
                        downloadBase: downloadBase,
                        verbose: false,
                        logLevel: .none,
                        prewarm: true,
                        load: false
                    )
                    _ = try await WhisperKit(config)
                },
                downloadAndLoadParakeet: { repositoryDirectory, versionLabel, onProgress in
                    let version: AsrModelVersion = versionLabel == "v3" ? .v3 : .v2
                    _ = try await AsrModels.downloadAndLoad(
                        to: repositoryDirectory,
                        version: version,
                        progressHandler: { progress in
                            onProgress(progress)
                        }
                    )
                },
                downloadSenseVoiceRepo: { fluidAudioModelsRoot, variant, onProgress in
                    try await DownloadUtils.downloadRepo(
                        .senseVoiceSmall,
                        to: fluidAudioModelsRoot,
                        variant: variant,
                        progressHandler: { progress in
                            onProgress(progress)
                        }
                    )
                },
                loadSenseVoiceModels: { repositoryDirectory, variant in
                    let precision = SenseVoiceEncoderPrecision(rawValue: variant) ?? .int8
                    _ = try SenseVoiceModels.load(from: repositoryDirectory, precision: precision)
                },
                downloadOfflineDiarization: { fluidAudioModelsRoot, onProgress in
                    _ = try await OfflineDiarizerModels.load(
                        from: fluidAudioModelsRoot,
                        progressHandler: { progress in
                            onProgress(progress)
                        }
                    )
                },
                downloadLiveDiarization: { fluidAudioModelsRoot, bundleFileName, onProgress in
                    // Fetch only, never load. `SortformerModels.load` ignores the
                    // MLModelConfiguration it is handed and forces computeUnits .all,
                    // which is the GPU-contention shape that already caused a shipped
                    // bug. The live engine loads this bundle later with
                    // .cpuAndNeuralEngine.
                    try await DownloadUtils.downloadRepo(
                        .sortformer,
                        to: fluidAudioModelsRoot,
                        variant: bundleFileName,
                        progressHandler: { progress in
                            onProgress(progress)
                        }
                    )
                },
                downloadStreamingRepo: { fluidAudioModelsRoot, repoFolderName in
                    let repo: Repo
                    if repoFolderName.contains("560") {
                        repo = .nemotronStreaming560
                    } else {
                        repo = .nemotronStreaming1120
                    }
                    try await DownloadUtils.downloadRepo(repo, to: fluidAudioModelsRoot)
                }
            )
        }
    }

    private let downloadOperations: DownloadOperations

    /// Last decile (0...10) logged for WhisperKit file download progress to avoid log spam.
    private var whisperKitDownloadLastLoggedDecile: Int = -1

    /// WhisperKit downloadBase root (host-injected Application Support/Pindrop or sandbox equivalent).
    private var modelsBaseURL: URL {
        storageLocations.pindropApplicationSupportRoot
    }

    private var whisperKitModelsURL: URL {
        modelsBaseURL
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
    }

    /// Injected FluidAudio models root (host Application Support/FluidAudio/Models or sandbox equivalent).
    private var fluidAudioModelsURL: URL {
        storageLocations.fluidAudioModelsRoot
    }

    /// Exact Parakeet repo directory for a model version under the injected FluidAudio root.
    private func parakeetRepoDirectory(for version: AsrModelVersion) -> URL {
        ParakeetEngine.modelDirectory(
            for: version,
            fluidAudioModelsRoot: fluidAudioModelsURL
        )
    }

    private func parakeetVersion(forModelName modelName: String) throws -> AsrModelVersion {
        if modelName.contains("v3") {
            return .v3
        }
        if modelName.contains("v2") {
            return .v2
        }
        throw ModelError.downloadFailed("Unknown Parakeet model version: \(modelName)")
    }

    /// Shared FluidAudio cache folder for SenseVoice-Small CoreML artifacts.
    private var senseVoiceModelsURL: URL {
        fluidAudioModelsURL.appendingPathComponent(
            Repo.senseVoiceSmall.folderName,
            isDirectory: true
        )
    }

    private func localModelPath(for model: WhisperModel) -> URL? {
        switch model.provider {
        case .whisperKit:
            return whisperKitModelsURL.appendingPathComponent(model.name, isDirectory: true)
        case .parakeet:
            return ParakeetEngine.modelDirectory(forName: model.name, fluidAudioModelsRoot: fluidAudioModelsURL)
        case .senseVoice:
            // Only advertise a local path when the catalog int8 set is complete.
            guard SenseVoiceModels.modelsExist(
                at: senseVoiceModelsURL,
                precision: SenseVoiceEngine.catalogPrecision
            ) else {
                return nil
            }
            return senseVoiceModelsURL
        case .appleSpeech:
            // Apple Speech uses system models; no local path to manage.
            return nil
        case .openAI, .elevenLabs, .groq:
            return nil
        }
    }

    public func existingLocalModelPath(for modelName: String) -> URL? {
        guard let model = availableModels.first(where: { $0.name == modelName }),
              let modelPath = localModelPath(for: model) else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: modelPath.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        return modelPath
    }
    
    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    
    public init(
        storageLocations: ModelStorageLocations,
        modelDownloadEventReporter: (any ModelDownloadEventReporting)? = nil
    ) {
        self.storageLocations = storageLocations
        self.modelDownloadEventReporter = modelDownloadEventReporter
        self.downloadOperations = .production()
        guard !Self.isPreview else { return }
    }

    /// Test/injection initializer. Hosts and production callers use the public convenience above.
    init(
        storageLocations: ModelStorageLocations,
        modelDownloadEventReporter: (any ModelDownloadEventReporting)? = nil,
        downloadOperations: DownloadOperations
    ) {
        self.storageLocations = storageLocations
        self.modelDownloadEventReporter = modelDownloadEventReporter
        self.downloadOperations = downloadOperations
        guard !Self.isPreview else { return }
    }
    
    public func refreshDownloadedModels() async {
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
        
        for model in availableModels where model.provider == .parakeet {
            #if os(macOS)
            if model.name == ParakeetEngine.orukeetModelName {
                let directory = ParakeetEngine.modelDirectory(forName: model.name, fluidAudioModelsRoot: fluidAudioModelsURL)
                if OrukeetModelStore.installed(at: directory) { downloaded.insert(model.name) }
                continue
            }
            #endif
            guard let version = try? parakeetVersion(forModelName: model.name) else { continue }
            let repoDir = parakeetRepoDirectory(for: version)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: repoDir.path, isDirectory: &isDirectory), isDirectory.boolValue {
                downloaded.insert(model.name)
            }
        }

        // SenseVoice catalog entry is int8-only: discovery and load share the
        // same precision decision so a fp16/fp32-only cache is never shown as ready.
        if SenseVoiceModels.modelsExist(
            at: senseVoiceModelsURL,
            precision: SenseVoiceEngine.catalogPrecision
        ) {
            downloaded.insert("sensevoice-small")
        }
        
        if downloaded != downloadedModelNames {
            Log.model.debug("Found \(downloaded.count) downloaded models: \(downloaded)")
        }
        downloadedModelNames = downloaded
    }
    
    public func getDownloadedModels() async -> [WhisperModel] {
        await refreshDownloadedModels()
        return availableModels.filter { downloadedModelNames.contains($0.name) }
    }
    
    public func isModelDownloaded(_ modelName: String) -> Bool {
        guard let model = availableModels.first(where: { $0.name == modelName }) else {
            return false
        }
        // System and cloud models have no local asset to download.
        if model.provider == .appleSpeech || (!model.provider.isLocal && model.availability == .available) {
            return true
        }
        return downloadedModelNames.contains(modelName)
    }

    public static func parakeetDownloadSnapshot(
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
            phase = .compiling(modelName: modelName)
        }

        return DownloadSnapshot(
            modelName: modelName,
            progress: progress.fractionCompleted,
            phase: phase
        )
    }

    public static func whisperDownloadSnapshot(
        modelName: String,
        fileDownloadFraction: Double
    ) -> DownloadSnapshot {
        DownloadSnapshot(
            modelName: modelName,
            progress: fileDownloadFraction * 0.8,
            phase: .downloading(completedFiles: nil, totalFiles: nil)
        )
    }

    public static func preparingDownloadSnapshot(
        modelName: String,
        progress: Double = 0.85
    ) -> DownloadSnapshot {
        DownloadSnapshot(modelName: modelName, progress: progress, phase: .preparing)
    }

    public static func completedDownloadSnapshot(modelName: String) -> DownloadSnapshot {
        DownloadSnapshot(modelName: modelName, progress: 1.0, phase: .completed)
    }

    public func updateDownloadSnapshot(
        _ snapshot: DownloadSnapshot,
        onProgress: ((DownloadSnapshot) -> Void)? = nil
    ) {
        let clampedSnapshot = DownloadSnapshot(
            modelName: snapshot.modelName,
            progress: min(max(snapshot.progress, 0.0), 1.0),
            phase: snapshot.phase
        )

        downloadSnapshot = clampedSnapshot
        downloadProgress = clampedSnapshot.progress
        onProgress?(clampedSnapshot)
    }

    public func clearDownloadState(resetProgress: Bool) {
        downloadSnapshot = nil
        if resetProgress {
            downloadProgress = 0.0
        }
    }
    
    public func downloadModel(
        named modelName: String,
        onProgress: ((DownloadSnapshot) -> Void)? = nil
    ) async throws {
        guard let model = availableModels.first(where: { $0.name == modelName }) else {
            throw ModelError.modelNotFound(modelName)
        }

        // Cloud models are remote and have no downloadable local asset.
        guard model.provider.isLocal else { return }
        
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

        modelDownloadEventReporter?.modelDownloadDidStart(modelName: modelName)
        do {
            if model.provider == .parakeet {
                try await downloadParakeetModel(named: modelName, onProgress: onProgress)
            } else if model.provider == .senseVoice {
                try await downloadSenseVoiceModel(named: modelName, onProgress: onProgress)
            } else {
                try await downloadWhisperKitModel(named: modelName, onProgress: onProgress)
            }
        } catch {
            modelDownloadEventReporter?.modelDownloadDidFail(modelName: modelName, error: error)
            throw error
        }
        Log.boot.info("ModelManager.downloadModel finished OK name=\(modelName) wallClock=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - downloadWallClock))")
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
            try await downloadOperations.downloadWhisperKit(
                modelName,
                self.modelsBaseURL
            ) { [weak self] fraction in
                Task { @MainActor in
                    guard let self else { return }
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
            Log.boot.info("WhisperKit.download finished elapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - fileDownloadStart))")
            
            Log.model.info("Download complete, prewarming model...")
            updateDownloadSnapshot(Self.preparingDownloadSnapshot(modelName: modelName), onProgress: onProgress)
            Log.boot.info("Entering prewarm phase (WhisperKitConfig prewarm=true load=false) — UI shows ~85% \"Preparing Model\"")
            
            let prewarmStart = CFAbsoluteTimeGetCurrent()
            try await downloadOperations.prewarmWhisperKit(modelName, self.modelsBaseURL)
            Log.boot.info("WhisperKit prewarm (init) completed elapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - prewarmStart))")
            
            Log.model.info("Model prewarmed successfully")
            updateDownloadSnapshot(Self.completedDownloadSnapshot(modelName: modelName), onProgress: onProgress)
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
        #if os(macOS)
        if modelName == ParakeetEngine.orukeetModelName {
            let directory = ParakeetEngine.modelDirectory(forName: modelName, fluidAudioModelsRoot: fluidAudioModelsURL)
            do {
                try await downloadOperations.prepareOrukeet(directory) { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.isDownloading, self.currentDownloadModel == modelName,
                              self.downloadSnapshot?.phase != .completed else { return }
                        self.updateDownloadSnapshot(
                            DownloadSnapshot(modelName: modelName, progress: progress, phase: progress < 0.9 ? .downloading(completedFiles: nil, totalFiles: nil) : .compiling(modelName: modelName)),
                            onProgress: onProgress)
                    }
                }
                updateDownloadSnapshot(Self.completedDownloadSnapshot(modelName: modelName), onProgress: onProgress)
                await refreshDownloadedModels()
            } catch {
                clearDownloadState(resetProgress: true)
                throw ModelError.downloadFailed(error.localizedDescription)
            }
            return
        }
        #endif
        let pipelineStart = CFAbsoluteTimeGetCurrent()
        let version = try parakeetVersion(forModelName: modelName)
        let targetDir = parakeetRepoDirectory(for: version)
        Log.model.info("Parakeet model download requested: \(modelName)")
        Log.model.info("Parakeet models path: \(targetDir.path)")
        Log.boot.info("Parakeet pipeline begin name=\(modelName)")

        do {
            try fileManager.createDirectory(at: targetDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            Log.boot.info("Parakeet storage directory ready")
        } catch {
            Log.boot.error("Parakeet mkdir failed: \(error.localizedDescription)")
            throw ModelError.downloadFailed("Failed to create Parakeet models directory: \(error.localizedDescription)")
        }

        Log.model.info("Starting Parakeet model download (version: \(version == .v3 ? "v3" : "v2"))")
        Log.boot.info("Parakeet AsrModels.downloadAndLoad starting version=\(version == .v3 ? "v3" : "v2")")

        do {
            let fetchStart = CFAbsoluteTimeGetCurrent()
            let versionLabel = version == .v3 ? "v3" : "v2"
            try await downloadOperations.downloadAndLoadParakeet(
                targetDir,
                versionLabel
            ) { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    self.updateDownloadSnapshot(
                        Self.parakeetDownloadSnapshot(modelName: modelName, progress: progress),
                        onProgress: onProgress
                    )
                }
            }
            Log.boot.info("Parakeet AsrModels.downloadAndLoad finished elapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - fetchStart))")
            
            Log.model.info("Parakeet model download complete")
            updateDownloadSnapshot(Self.completedDownloadSnapshot(modelName: modelName), onProgress: onProgress)
            
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

    private func downloadSenseVoiceModel(
        named modelName: String,
        onProgress: ((DownloadSnapshot) -> Void)? = nil
    ) async throws {
        let pipelineStart = CFAbsoluteTimeGetCurrent()
        let precision = SenseVoiceEngine.catalogPrecision
        let requiredArtifacts = SenseVoiceEngine.requiredDownloadArtifacts(precision: precision)
        Log.model.info(
            "SenseVoice model download requested: \(modelName) precision=\(precision.rawValue) artifacts=\(requiredArtifacts.sorted())"
        )
        Log.boot.info("SenseVoice pipeline begin name=\(modelName) precision=\(precision.rawValue)")

        // Guard the catalog contract: int8 must never pull fp16/fp32 encoders.
        #if DEBUG
        assert(
            !requiredArtifacts.contains(ModelNames.SenseVoice.encoderFile)
                && !requiredArtifacts.contains(ModelNames.SenseVoice.encoderFp32File),
            "SenseVoice int8 download set must not include fp16/fp32 encoders"
        )
        #endif

        do {
            try fileManager.createDirectory(at: fluidAudioModelsURL, withIntermediateDirectories: true)
        } catch {
            throw ModelError.downloadFailed(
                "Failed to create SenseVoice models directory: \(error.localizedDescription)"
            )
        }

        do {
            let fetchStart = CFAbsoluteTimeGetCurrent()
            // FluidAudio 0.15.4+ is precision-aware: variant=int8 fetches only
            // preprocessor + SenseVoiceSmall_int8 (+ vocab.json as root aux).
            // Download into the injected FluidAudio models root, never the dependency default.
            try await downloadOperations.downloadSenseVoiceRepo(
                fluidAudioModelsURL,
                precision.rawValue
            ) { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    self.updateDownloadSnapshot(
                        Self.parakeetDownloadSnapshot(modelName: modelName, progress: progress),
                        onProgress: onProgress
                    )
                }
            }
            Log.boot.info(
                "SenseVoice download finished elapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - fetchStart))"
            )

            guard SenseVoiceModels.modelsExist(at: senseVoiceModelsURL, precision: precision) else {
                throw ModelError.downloadFailed(
                    "SenseVoice int8 artifacts incomplete after download"
                )
            }

            // Compile/load once so first dictation does not pay cold-start cost.
            updateDownloadSnapshot(
                Self.preparingDownloadSnapshot(modelName: modelName),
                onProgress: onProgress
            )
            try downloadOperations.loadSenseVoiceModels(senseVoiceModelsURL, precision.rawValue)

            updateDownloadSnapshot(Self.completedDownloadSnapshot(modelName: modelName), onProgress: onProgress)
            await refreshDownloadedModels()
            Log.boot.info(
                "SenseVoice pipeline success totalElapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - pipelineStart))"
            )
        } catch {
            clearDownloadState(resetProgress: true)
            Log.model.error("SenseVoice model download failed: \(error.localizedDescription)")
            if let modelError = error as? ModelError {
                throw modelError
            }
            throw ModelError.downloadFailed(error.localizedDescription)
        }
    }
    
    public func deleteModel(named modelName: String) async throws {
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

    public func isFeatureModelDownloaded(_ type: FeatureModelType) -> Bool {
        downloadedFeatureModels.contains(type)
    }

    /// True when the specific streaming chunk variant matching `profile` is present on
    /// disk. `isFeatureModelDownloaded(.streaming)` answers the broader "any variant is
    /// present" question; this helper is for code paths that care which one.
    public func isStreamingChunkVariantDownloaded(_ profile: StreamingChunkProfile) -> Bool {
        let folder = fluidAudioModelsURL.appendingPathComponent(profile.repoFolderName)
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Complete offline Community-1 diarization readiness.
    ///
    /// Requires every CoreML asset in `ModelNames.OfflineDiarizer.requiredModels`
    /// (excluding `plda-parameters.json`) under `speaker-diarization-coreml`, plus
    /// `plda-parameters.json` in one of the three locations FluidAudio accepts.
    /// Directory existence alone is not readiness.
    ///
    /// FluidAudio 0.15+ lists PLDA inside `requiredModels`; we still treat it as a
    /// separate candidate check so root / coreml / offline-sibling placements all
    /// remain valid — forcing PLDA only under coreml would make the other two
    /// documented locations unreachable.
    public func isOfflineDiarizationReady() -> Bool {
        isOfflineDiarizationModelsReady(at: fluidAudioModelsURL)
    }

    /// Reusable complete-asset check used by refresh, download completion, and preflight.
    public func isOfflineDiarizationModelsReady(at modelsRoot: URL) -> Bool {
        Self.isOfflineDiarizationModelsReady(at: modelsRoot, fileManager: fileManager)
    }

    /// Nonisolated so a gated test can decide whether the bundle this needs is on
    /// disk without standing up a manager. One copy of the rule, so a gate and a
    /// download can never disagree about what "ready" means.
    public nonisolated static func isOfflineDiarizationModelsReady(
        at modelsRoot: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let coremlFolder = modelsRoot
            .appendingPathComponent(FeatureModelType.diarization.repoFolderName, isDirectory: true)

        let coremlRequiredModels = ModelNames.OfflineDiarizer.requiredModels.subtracting([
            ModelNames.OfflineDiarizer.pldaParameters
        ])
        for modelName in coremlRequiredModels {
            let modelURL = coremlFolder.appendingPathComponent(modelName)
            guard fileManager.fileExists(atPath: modelURL.path) else {
                return false
            }
        }

        // FluidAudio accepts PLDA params at the models root, inside the online/offline
        // shared coreml folder, or under the offline-specific sibling folder.
        let pldaCandidates = [
            modelsRoot.appendingPathComponent("plda-parameters.json", isDirectory: false),
            coremlFolder.appendingPathComponent("plda-parameters.json", isDirectory: false),
            modelsRoot
                .appendingPathComponent("speaker-diarization-offline", isDirectory: true)
                .appendingPathComponent("plda-parameters.json", isDirectory: false),
        ]
        return pldaCandidates.contains { fileManager.fileExists(atPath: $0.path) }
    }

    /// Streaming Sortformer readiness for live speaker labels.
    ///
    /// The live engine calls a FluidAudio entry point that downloads when the
    /// bundle is missing or partial, so this gate is what keeps a fetch off the
    /// capture path. It must be true before the engine loads anything.
    public func isLiveDiarizationReady() -> Bool {
        isLiveDiarizationModelsReady(at: fluidAudioModelsURL)
    }

    /// Reusable bundle check used by refresh, download completion, and preflight.
    ///
    /// The expected bundle name comes from `LiveDiarizationPreset`, never from a
    /// literal here: each preset ships its own bundle, so a hard-coded name would
    /// report "not ready" after a good download of a different preset.
    public func isLiveDiarizationModelsReady(at modelsRoot: URL) -> Bool {
        Self.isLiveDiarizationModelsReady(at: modelsRoot, fileManager: fileManager)
    }

    /// Nonisolated so `LiveDiarizationEngine` can gate its own load on this exact
    /// rule from its own executor. Two copies of the check would let readiness and
    /// the engine disagree, which reads as "downloaded" with no live labels ever.
    public nonisolated static func isLiveDiarizationModelsReady(
        at modelsRoot: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let bundle = modelsRoot
            .appendingPathComponent(
                FeatureModelType.liveDiarization.repoFolderName,
                isDirectory: true
            )
            .appendingPathComponent(LiveDiarizationPreset.bundleFileName, isDirectory: true)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: bundle.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        // A `.mlmodelc` is a directory. An interrupted download leaves an empty one
        // behind, and loading that is the corrupt-bundle failure, not a clean miss.
        let contents = (try? fileManager.contentsOfDirectory(atPath: bundle.path)) ?? []
        return !contents.isEmpty
    }

    /// The required feature models this install still has to fetch.
    ///
    /// Reads the state of a previous refresh, so callers refresh first. An
    /// empty answer means the install is complete, which is the answer for
    /// almost every launch after the first.
    public func missingRequiredFeatureModels(
        streamingChunkProfile: StreamingChunkProfile = .standard
    ) -> [FeatureModelType] {
        FeatureModelType.required.filter { type in
            switch type {
            case .streaming:
                // The variant this install actually runs has to be the one on
                // disk: the other one would load nothing.
                return !isStreamingChunkVariantDownloaded(streamingChunkProfile)
            default:
                return !isFeatureModelDownloaded(type)
            }
        }
    }

    /// Fetches every required feature model that is missing, in order.
    ///
    /// One failure does not stop the rest: an install with live transcription
    /// but no paragraph breaks is better than an install with neither. The
    /// failures are returned so the caller can say what is still missing.
    @discardableResult
    public func downloadMissingRequiredFeatureModels(
        streamingChunkProfile: StreamingChunkProfile = .standard,
        onProgress: ((FeatureModelType, Double) -> Void)? = nil
    ) async -> [(type: FeatureModelType, error: any Error)] {
        var failures: [(type: FeatureModelType, error: any Error)] = []
        for type in missingRequiredFeatureModels(streamingChunkProfile: streamingChunkProfile) {
            if Task.isCancelled { break }
            do {
                try await downloadFeatureModel(
                    type,
                    streamingChunkProfile: streamingChunkProfile,
                    onProgress: { progress in onProgress?(type, progress) }
                )
            } catch {
                Log.model.error(
                    "Required feature model \(type.rawValue) failed to download: \(error.localizedDescription)"
                )
                failures.append((type, error))
            }
        }
        return failures
    }

    public func refreshDownloadedFeatureModels() async {
        var downloaded: Set<FeatureModelType> = []

        for type in FeatureModelType.allCases {
            switch type {
            case .streaming:
                // Either chunk variant counts as "streaming downloaded" so toggling the
                // low-latency setting doesn't silently mark the feature as missing.
                if isStreamingChunkVariantDownloaded(.standard)
                    || isStreamingChunkVariantDownloaded(.lowLatency) {
                    downloaded.insert(type)
                }
            case .diarization:
                if isOfflineDiarizationModelsReady(at: fluidAudioModelsURL) {
                    downloaded.insert(type)
                }
            case .liveDiarization:
                if isLiveDiarizationModelsReady(at: fluidAudioModelsURL) {
                    downloaded.insert(type)
                }
            case .vad:
                let repoFolder = fluidAudioModelsURL.appendingPathComponent(type.repoFolderName)
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: repoFolder.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    downloaded.insert(type)
                }
            }
        }

        if downloaded != downloadedFeatureModels {
            Log.model.debug("Found \(downloaded.count) downloaded feature models: \(downloaded)")
        }
        downloadedFeatureModels = downloaded
    }

    public func downloadFeatureModel(
        _ type: FeatureModelType,
        streamingChunkProfile: StreamingChunkProfile = .standard,
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

        Log.model.info("Downloading feature model: \(type.rawValue)")

        do {
            switch type {
            case .vad:
                featureDownloadProgress = 0.1
                onProgress?(0.1)
                // VadManager(modelDirectory:) appends "Models" internally; pass the parent
                // of the injected FluidAudio models root so load lands under that root.
                let vadBaseDirectory = fluidAudioModelsURL.deletingLastPathComponent()
                _ = try await VadManager(
                    config: .default,
                    modelDirectory: vadBaseDirectory
                )

            case .diarization:
                // Offline Community-1 assets: download/prewarm via OfflineDiarizerModels,
                // bridge FluidAudio progress onto MainActor, and only mark complete once
                // every required artifact is present. Discard the in-memory models after.
                try await downloadOperations.downloadOfflineDiarization(
                    fluidAudioModelsURL
                ) { [weak self] progress in
                    let fraction = min(max(progress.fractionCompleted, 0), 0.99)
                    Task { @MainActor in
                        guard let self,
                              self.isDownloadingFeature,
                              self.currentDownloadingFeature == .diarization else {
                            return
                        }
                        // Never claim 1.0 from the handler — readiness sets that.
                        self.featureDownloadProgress = fraction
                        onProgress?(fraction)
                    }
                }
                guard isOfflineDiarizationModelsReady(at: fluidAudioModelsURL) else {
                    featureDownloadProgress = 0.0
                    onProgress?(0.0)
                    throw ModelError.downloadFailed(
                        "Speaker diarization model files are incomplete after download"
                    )
                }

            case .liveDiarization:
                featureDownloadProgress = 0.1
                onProgress?(0.1)
                try await downloadOperations.downloadLiveDiarization(
                    fluidAudioModelsURL,
                    LiveDiarizationPreset.bundleFileName
                ) { [weak self] progress in
                    let fraction = min(max(progress.fractionCompleted, 0), 0.99)
                    Task { @MainActor in
                        guard let self,
                              self.isDownloadingFeature,
                              self.currentDownloadingFeature == .liveDiarization else {
                            return
                        }
                        // Never claim 1.0 from the handler; readiness sets that.
                        self.featureDownloadProgress = fraction
                        onProgress?(fraction)
                    }
                }
                guard isLiveDiarizationModelsReady(at: fluidAudioModelsURL) else {
                    featureDownloadProgress = 0.0
                    onProgress?(0.0)
                    throw ModelError.downloadFailed(
                        "Live speaker model files are incomplete after download"
                    )
                }

            case .streaming:
                featureDownloadProgress = 0.1
                onProgress?(0.1)
                featureDownloadProgress = 0.3
                onProgress?(0.3)
                try await downloadOperations.downloadStreamingRepo(
                    fluidAudioModelsURL,
                    streamingChunkProfile.repoFolderName
                )
            }

            featureDownloadProgress = 1.0
            onProgress?(1.0)

            Log.model.info("Feature model download complete: \(type.rawValue)")
            await refreshDownloadedFeatureModels()

            // Diarization must still be marked ready after refresh; a race or partial
            // cache must not leave the feature enabled with incomplete assets.
            if type == .diarization, !downloadedFeatureModels.contains(.diarization) {
                featureDownloadProgress = 0.0
                onProgress?(0.0)
                throw ModelError.downloadFailed(
                    "Speaker diarization model files are incomplete after download"
                )
            }
        } catch {
            featureDownloadProgress = 0.0
            Log.model.error("Feature model download failed: \(error.localizedDescription)")
            if let modelError = error as? ModelError {
                throw modelError
            }
            throw ModelError.downloadFailed(error.localizedDescription)
        }
    }
}
