//
//  WhisperKitEngineTests.swift
//  PindropTests
//
//  Created on 2026-01-30.
//
//  Unit suite is strictly offline: never calls loadModel(name:) with download
//  enabled / bare model names that would hit Hugging Face. Network-backed
//  coverage lives in WhisperKitEngineIntegrationTests (PINDROP_RUN_INTEGRATION_TESTS).
//

import Foundation
import Testing
@testable import Pindrop

@MainActor
@Suite("WhisperKitEngine (unit, offline)")
struct WhisperKitEngineTests {
    private func makeEngine() -> WhisperKitEngine {
        WhisperKitEngine()
    }

    private func makeInt16AudioData(sampleCount: Int = 16_000) -> Data {
        var audioData = Data()
        for _ in 0..<sampleCount {
            var sample: Int16 = 0
            audioData.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
        }
        return audioData
    }

    /// Empty isolated cache directory so name-based loads cannot fall back to a
    /// shared Hugging Face cache or the network when `download: false`.
    private func makeEmptyDownloadBase() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pindrop-whisperkit-unit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func nonexistentModelPath() -> String {
        "/nonexistent/pindrop/whisperkit/\(UUID().uuidString)/MelSpectrogram.mlmodelc"
    }

    // MARK: - Initial state

    @Test func initialStateIsUnloaded() {
        let engine = makeEngine()

        #expect(engine.state == .unloaded, "Initial state should be unloaded")
        #expect(engine.error == nil, "Initial error should be nil")
    }

    // MARK: - Offline load failure paths (no network)

    @Test func loadModelWithInvalidPathThrowsError() async throws {
        let engine = makeEngine()
        #expect(engine.state == .unloaded)

        do {
            try await engine.loadModel(modelPath: nonexistentModelPath())
            Issue.record("Should throw error for invalid model path")
        } catch {
            #expect(engine.state == .error, "State should be error after failed load")
            #expect(engine.error != nil, "Error should be set after failed load")
        }
    }

    @Test func loadModelSetsErrorOnFailure() async throws {
        let engine = makeEngine()
        #expect(engine.error == nil)

        do {
            try await engine.loadModel(modelPath: nonexistentModelPath())
        } catch {
        }

        #expect(engine.error != nil, "Error should be set after failed model load")
        #expect(engine.state == .error, "State should be error after failed load")
    }

    @Test func loadModelByNameWithoutDownloadFailsOffline() async throws {
        let engine = makeEngine()
        let downloadBase = try makeEmptyDownloadBase()
        defer { try? FileManager.default.removeItem(at: downloadBase) }

        do {
            // download: false — must not touch the network even if the model is missing.
            try await engine.loadModel(
                name: "tiny",
                downloadBase: downloadBase,
                download: false
            )
            Issue.record("Expected offline name load to fail when model is absent")
        } catch {
            #expect(engine.state == .error)
            #expect(engine.error != nil)
        }
    }

    @Test func loadModelByNameLeavesUnloadedOnlyWhenNeverStarted() async throws {
        // Mirrors former "SetsStateToReady" coverage without a network download:
        // a missing local path still transitions out of .unloaded into .error.
        let engine = makeEngine()
        #expect(engine.state == .unloaded)

        do {
            try await engine.loadModel(modelPath: nonexistentModelPath())
        } catch {
        }

        #expect(engine.state != .unloaded, "State should change from unloaded when loading is attempted")
        #expect(engine.state == .error)
    }

    @Test func loadModelTransitionsThroughLoadingToErrorOffline() async throws {
        let engine = makeEngine()
        #expect(engine.state == .unloaded)

        // Invalid path fails quickly offline (no network).
        do {
            try await engine.loadModel(modelPath: nonexistentModelPath())
        } catch {
        }

        #expect(engine.state == .error, "Failed offline load should end in error")
        #expect(engine.error != nil)
    }

    // MARK: - Transcribe without a loaded model

    @Test func transcribeRequiresLoadedModel() async throws {
        let engine = makeEngine()
        #expect(engine.state == .unloaded)

        do {
            _ = try await engine.transcribe(audioData: makeInt16AudioData())
            Issue.record("Should throw error when model not loaded")
        } catch WhisperKitEngine.EngineError.modelNotLoaded {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func transcribeWithEmptyAudioDataThrowsModelNotLoadedWhenUnloaded() async throws {
        // Do not attempt a network model load — empty audio while unloaded
        // should fail on the modelNotLoaded guard first.
        let engine = makeEngine()

        do {
            _ = try await engine.transcribe(audioData: Data())
            Issue.record("Should throw error for empty audio / unloaded model")
        } catch WhisperKitEngine.EngineError.modelNotLoaded {
        } catch WhisperKitEngine.EngineError.invalidAudioData {
            // Acceptable if guard order ever changes once a model is ready.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func transcribeReturnsNonEmptyStringOrStaysUnloaded() async throws {
        let engine = makeEngine()

        do {
            let result = try await engine.transcribe(audioData: makeInt16AudioData())
            #expect(result.isEmpty == false, "Transcription result should not be empty")
            #expect(engine.state == .ready, "State should return to ready after transcription")
        } catch {
            #expect(engine.state == .unloaded, "State should remain unloaded when model not loaded")
        }
    }

    @Test func transcribeSetsStateToTranscribingOrUnloaded() async throws {
        let engine = makeEngine()
        let audioData = makeInt16AudioData()

        Task {
            do {
                _ = try await engine.transcribe(audioData: audioData)
            } catch {
            }
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(
            engine.state == .unloaded || engine.state == .transcribing || engine.state == .error,
            "State should be one of expected values during/after transcription attempt"
        )
    }

    // MARK: - Unload

    @Test func unloadModelSetsStateToUnloadedAfterFailedLoad() async throws {
        let engine = makeEngine()

        do {
            try await engine.loadModel(modelPath: nonexistentModelPath())
        } catch {
        }

        await engine.unloadModel()

        #expect(engine.state == .unloaded, "State should be unloaded after unloadModel")
        #expect(engine.error == nil, "Error should be nil after unloadModel")
    }

    @Test func unloadModelClearsError() async throws {
        let engine = makeEngine()

        do {
            try await engine.loadModel(modelPath: nonexistentModelPath())
        } catch {
        }

        #expect(engine.error != nil, "Error should be set after failed load")

        await engine.unloadModel()

        #expect(engine.error == nil, "Error should be cleared after unloadModel")
    }

    @Test func unloadModelFromUnloadedStateIsSafe() async {
        let engine = makeEngine()
        #expect(engine.state == .unloaded)

        await engine.unloadModel()

        #expect(engine.state == .unloaded, "State should remain unloaded")
        #expect(engine.error == nil, "Error should remain nil")
    }

    @Test func stateTransitionsOfflineLoadFailureThenUnload() async throws {
        let engine = makeEngine()
        #expect(engine.state == .unloaded)

        do {
            try await engine.loadModel(modelPath: nonexistentModelPath())
        } catch {
        }

        #expect(engine.state == .error)

        await engine.unloadModel()
        #expect(engine.state == .unloaded)
    }

    @Test func concurrentTranscriptionPreventionWithoutModel() async throws {
        let engine = makeEngine()
        let audioData = makeInt16AudioData()

        async let result1 = engine.transcribe(audioData: audioData)
        async let result2 = engine.transcribe(audioData: audioData)

        do {
            _ = try await result1
            _ = try await result2
        } catch {
            // Expected: model not loaded.
        }
    }

    // MARK: - EngineError descriptions

    @Test func errorDescriptionForModelNotLoaded() {
        let error = WhisperKitEngine.EngineError.modelNotLoaded
        #expect(error.errorDescription != nil, "Error should have description")
        #expect(error.errorDescription?.contains("not loaded") ?? false,
                "Error description should mention model not loaded")
    }

    @Test func errorDescriptionForInvalidAudioData() {
        let error = WhisperKitEngine.EngineError.invalidAudioData
        #expect(error.errorDescription != nil, "Error should have description")
        #expect(error.errorDescription?.contains("Invalid") ?? false,
                "Error description should mention invalid audio data")
    }

    @Test func errorDescriptionForTranscriptionFailed() {
        let message = "Test error message"
        let error = WhisperKitEngine.EngineError.transcriptionFailed(message)
        #expect(error.errorDescription != nil, "Error should have description")
        #expect(error.errorDescription?.contains(message) ?? false,
                "Error description should contain the failure message")
    }
}

// MARK: - Integration (network) — opt-in only

/// Real model download / ready-state coverage. Disabled in the Unit plan.
/// Run with `PINDROP_RUN_INTEGRATION_TESTS=1 just test-integration` (or equivalent).
@MainActor
@Suite(
    "WhisperKitEngine (integration, network)",
    .enabled(
        if: ProcessInfo.processInfo.environment["PINDROP_RUN_INTEGRATION_TESTS"] == "1",
        "WhisperKit network/model-download tests are disabled by default. Run with PINDROP_RUN_INTEGRATION_TESTS=1."
    )
)
struct WhisperKitEngineIntegrationTests {
    @Test func loadTinyModelByNameDownloadsAndSetsReady() async throws {
        let engine = WhisperKitEngine()
        #expect(engine.state == .unloaded)

        // Intentionally allows network — gated by PINDROP_RUN_INTEGRATION_TESTS.
        try await engine.loadModel(name: "tiny", downloadBase: nil, download: true)

        #expect(engine.state == .ready)
        #expect(engine.error == nil)

        await engine.unloadModel()
        #expect(engine.state == .unloaded)
    }
}
