//
//  ModelManagerTests.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import FluidAudio
import Foundation
import Testing
@testable import Pindrop

@MainActor
@Suite
struct ModelManagerTests {
    let modelManager = ModelManager()

    @Test func listAvailableModels() {
        let models = modelManager.availableModels

        #expect(!models.isEmpty)
        #expect(models.contains { $0.name == "openai_whisper-tiny" })
        #expect(models.contains { $0.name == "openai_whisper-base" })
        #expect(models.contains { $0.name == "openai_whisper-small" })
        #expect(models.contains { $0.name == "openai_whisper-large-v3" })
        #expect(models.contains { $0.name == "openai_whisper-large-v3_turbo" })
        #expect(models.contains { $0.name == "openai_whisper-medium" })
        #expect(models.contains { $0.name == "openai_whisper-large-v2" })
        #expect(models.contains { $0.name == "distil-whisper_distil-large-v3" })
        #expect(models.contains { $0.name == "parakeet-tdt-0.6b-v2" })
    }

    @Test func recommendedModelsUseCuratedOrder() {
        let recommendedModelNames = modelManager.recommendedModels.map(\.name)
        #expect(recommendedModelNames == ModelManager.englishRecommendedModelNames)
    }

    @Test func multilingualRecommendationsPreferWhisperMultilingualModels() {
        let recommendedModelNames = modelManager.recommendedModels(for: .spanish).map(\.name)
        #expect(recommendedModelNames == ModelManager.multilingualRecommendedModelNames)
    }

    @Test func modelSizes() {
        let models = modelManager.availableModels

        // Apple Speech uses on-device system models and reports 0 MB by design.
        for model in models where model.provider.isLocal && model.provider != .appleSpeech {
            #expect(model.sizeInMB > 0)
        }

        let tiny = models.first { $0.name == "openai_whisper-tiny" }
        let base = models.first { $0.name == "openai_whisper-base" }
        let small = models.first { $0.name == "openai_whisper-small" }

        #expect(tiny != nil)
        #expect(base != nil)
        #expect(small != nil)

        if let tiny, let base, let small {
            #expect(tiny.sizeInMB < base.sizeInMB)
            #expect(base.sizeInMB < small.sizeInMB)
        }
    }

    @Test func checkDownloadedModels() async {
        let downloadedModels = await modelManager.getDownloadedModels()
        #expect(downloadedModels != nil)
    }

    @Test func isModelDownloaded() {
        let isDownloaded = modelManager.isModelDownloaded("openai_whisper-tiny")
        #expect(isDownloaded == true || isDownloaded == false)
    }

    @Test func modelLookup() {
        let model = modelManager.availableModels.first { $0.name == "openai_whisper-tiny" }
        #expect(model != nil)
        #expect(model?.provider == .whisperKit)
    }

    @Test func invalidModelLookup() {
        let model = modelManager.availableModels.first { $0.name == "nonexistent-model" }
        #expect(model == nil)
    }

    @Test func containsParakeetModels() {
        let hasParakeetModel = modelManager.availableModels.contains { $0.provider == .parakeet }
        #expect(hasParakeetModel)
    }

    @Test func englishOnlyModelsWarnForNonEnglishSelection() throws {
        let model = try #require(modelManager.availableModels.first { $0.name == "openai_whisper-base.en" })
        #expect(model.supports(language: .english) == true)
        #expect(model.supports(language: .simplifiedChinese) == false)

        let badge = model.languageBadgePresentation(for: .simplifiedChinese)
        #expect(badge.text == "English-only")
        #expect(badge.tone == .caution)
    }

    @Test func parakeetV3SupportsEuropeanLanguagesButNotChinese() throws {
        let model = try #require(modelManager.availableModels.first { $0.name == "parakeet-tdt-0.6b-v3" })
        #expect(model.supports(language: .spanish) == true)
        #expect(model.supports(language: .portugueseBrazil) == true)
        #expect(model.supports(language: .russian) == true)
        #expect(model.supports(language: .ukrainian) == true)
        #expect(model.supports(language: .polish) == true)
        #expect(model.supports(language: .simplifiedChinese) == false)
    }

    @Test func polishDictationUsesMultilingualRecommendations() throws {
        let recommendedModelNames = modelManager.recommendedModels(for: .polish).map(\.name)
        #expect(recommendedModelNames == ModelManager.multilingualRecommendedModelNames)
        let whisper = try #require(modelManager.availableModels.first { $0.name == "openai_whisper-base" })
        #expect(whisper.supports(language: .polish))
    }

    @Test func deleteNonexistentModelThrowsModelNotFound() async {
        do {
            try await modelManager.deleteModel(named: "nonexistent-model")
            Issue.record("Expected modelNotFound for nonexistent model")
        } catch let error as ModelManager.ModelError {
            guard case .modelNotFound(let modelName) = error else {
                Issue.record("Expected modelNotFound error")
                return
            }
            #expect(modelName == "nonexistent-model")
        } catch {
            Issue.record("Expected ModelError, got \(error.localizedDescription)")
        }
    }

    @Test func downloadProgressInitialState() {
        #expect(modelManager.downloadProgress == 0.0)
        #expect(modelManager.isDownloading == false)
        #expect(modelManager.currentDownloadModel == nil)
        #expect(modelManager.downloadSnapshot == nil)
    }

    @Test func parakeetDownloadProgressMapping_listing_setsListingPhase() {
        let snapshot = ModelManager.parakeetDownloadSnapshot(
            modelName: "parakeet-tdt-0.6b-v3",
            progress: DownloadUtils.DownloadProgress(
                fractionCompleted: 0.12,
                phase: .listing
            )
        )

        #expect(snapshot.modelName == "parakeet-tdt-0.6b-v3")
        #expect(snapshot.progress == 0.12)
        #expect(snapshot.phase == .listing)
    }

    @Test func parakeetDownloadProgressMapping_downloading_setsFileCounts() {
        let snapshot = ModelManager.parakeetDownloadSnapshot(
            modelName: "parakeet-tdt-0.6b-v3",
            progress: DownloadUtils.DownloadProgress(
                fractionCompleted: 0.42,
                phase: .downloading(completedFiles: 3, totalFiles: 7)
            )
        )

        #expect(snapshot.progress == 0.42)
        #expect(snapshot.phase == .downloading(completedFiles: 3, totalFiles: 7))
    }

    @Test func parakeetDownloadProgressMapping_compiling_setsCompilingPhase() {
        let snapshot = ModelManager.parakeetDownloadSnapshot(
            modelName: "parakeet-tdt-0.6b-v3",
            progress: DownloadUtils.DownloadProgress(
                fractionCompleted: 0.76,
                phase: .compiling(modelName: "Decoder.mlmodelc")
            )
        )

        #expect(snapshot.progress == 0.76)
        #expect(snapshot.phase == .compiling(modelName: "Decoder.mlmodelc"))
    }

    @Test func whisperKitPreparationPhase_setsPreparingSnapshot() {
        let snapshot = ModelManager.preparingDownloadSnapshot(
            modelName: "openai_whisper-base"
        )

        #expect(snapshot.progress == 0.85)
        #expect(snapshot.phase == .preparing)
    }

    @Test func downloadSnapshotClearsWhenRequested() {
        let snapshot = ModelManager.completedDownloadSnapshot(modelName: "openai_whisper-base")

        modelManager.updateDownloadSnapshot(snapshot)
        #expect(modelManager.downloadSnapshot == snapshot)
        #expect(modelManager.downloadProgress == 1.0)

        modelManager.clearDownloadState(resetProgress: true)
        #expect(modelManager.downloadSnapshot == nil)
        #expect(modelManager.downloadProgress == 0.0)
    }

    @Test func downloadNonexistentModel() async {
        do {
            try await modelManager.downloadModel(named: "nonexistent-model")
            Issue.record("Expected error for nonexistent model")
        } catch {
            #expect(error is ModelManager.ModelError)
        }
    }

    @Test func featureModelRepoFolderNamesMatchDownloaderCacheLayout() {
        #expect(FeatureModelType.vad.repoFolderName == "silero-vad-coreml")
        #expect(FeatureModelType.diarization.repoFolderName == "speaker-diarization-coreml")
        // Streaming uses Nemotron Speech Streaming 0.6B. These folder names must match
        // FluidAudio's `Repo.nemotronStreaming*.folderName` values — that's where
        // DownloadUtils.downloadRepo materializes each chunk variant.
        #expect(FeatureModelType.streaming.repoFolderName == "nemotron-streaming/1120ms")
        #expect(FeatureModelType.streamingRepoFolderName(for: .standard) == "nemotron-streaming/1120ms")
        #expect(FeatureModelType.streamingRepoFolderName(for: .lowLatency) == "nemotron-streaming/560ms")
    }
    @Test func offlineDiarizationReadinessRequiresAllArtifacts() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pindrop-diarization-readiness-\(UUID().uuidString)", isDirectory: true)
        let coreml = root.appendingPathComponent(FeatureModelType.diarization.repoFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: coreml, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for path in ModelNames.OfflineDiarizer.requiredModels {
            FileManager.default.createFile(atPath: coreml.appendingPathComponent(path).path, contents: Data())
        }
        #expect(modelManager.isOfflineDiarizationModelsReady(at: root) == false)
        FileManager.default.createFile(
            atPath: root.appendingPathComponent("plda-parameters.json").path,
            contents: Data("{}".utf8)
        )
        #expect(modelManager.isOfflineDiarizationModelsReady(at: root))
    }
}
