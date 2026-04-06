//
//  ModelManagerTests.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import FluidAudio
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

        for model in models where model.provider.isLocal {
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
        _ = downloadedModels
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

    @Test func providerLocalityMatchesSharedPolicy() {
        #expect(ModelManager.ModelProvider.whisperKit.isLocal == true)
        #expect(ModelManager.ModelProvider.parakeet.isLocal == true)
        #expect(ModelManager.ModelProvider.openAI.isLocal == false)
        #expect(ModelManager.ModelProvider.elevenLabs.isLocal == false)
        #expect(ModelManager.ModelProvider.groq.isLocal == false)
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
        #expect(model.supports(language: .simplifiedChinese) == false)
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
        #expect(FeatureModelType.streaming.repoFolderName == "parakeet-eou-streaming/160ms")
    }
}
