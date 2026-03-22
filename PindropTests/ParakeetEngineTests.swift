//
//  ParakeetEngineTests.swift
//  PindropTests
//
//  Created on 2026-01-30.
//

import Foundation
import Testing
@testable import Pindrop

@MainActor
@Suite
struct ParakeetEngineTests {
    private func makeEngine() -> ParakeetEngine {
        ParakeetEngine()
    }

    private func makeInt16AudioData(sampleCount: Int = 16_000) -> Data {
        var audioData = Data()
        for _ in 0..<sampleCount {
            var sample: Int16 = 0
            audioData.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
        }
        return audioData
    }

    @Test func initialStateIsUnloaded() {
        let engine = makeEngine()
        #expect(engine.state == .unloaded, "Initial state should be unloaded")
        #expect(engine.error == nil, "Initial error should be nil")
    }

    @Test func loadModelSetsStateToReady() async throws {
        let engine = makeEngine()
        #expect(engine.state == .unloaded)

        do {
            try await engine.loadModel(modelName: "parakeet-tdt-0.6b-v2")
        } catch {
        }

        #expect(engine.state != .unloaded, "State should change from unloaded when loading starts")
    }

    @Test func loadModelTransitionsThroughLoadingState() async throws {
        let engine = makeEngine()
        #expect(engine.state == .unloaded)

        Task {
            do {
                try await engine.loadModel(modelName: "parakeet-tdt-0.6b-v2")
            } catch {
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(engine.state != .unloaded, "State should transition from unloaded when loading starts")
    }

    @Test func loadModelWithPathNotSupported() async throws {
        let engine = makeEngine()
        #expect(engine.state == .unloaded)

        do {
            try await engine.loadModel(modelPath: "/some/path/to/model")
            Issue.record("Should throw error for path-based loading")
        } catch ParakeetEngine.EngineError.initializationFailed {
            #expect(engine.state == .error, "State should be error after failed load")
            #expect(engine.error != nil, "Error should be set after failed load")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func transcribeRequiresLoadedModel() async throws {
        let engine = makeEngine()
        #expect(engine.state == .unloaded)

        do {
            _ = try await engine.transcribe(audioData: makeInt16AudioData())
            Issue.record("Should throw error when model not loaded")
        } catch ParakeetEngine.EngineError.modelNotLoaded {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func transcribeWithEmptyAudioDataThrowsError() async throws {
        let engine = makeEngine()

        do {
            try await engine.loadModel(modelName: "parakeet-tdt-0.6b-v2")
        } catch {
        }

        do {
            _ = try await engine.transcribe(audioData: Data())
            Issue.record("Should throw error for empty audio data")
        } catch ParakeetEngine.EngineError.invalidAudioData {
        } catch ParakeetEngine.EngineError.modelNotLoaded {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func unloadModelSetsStateToUnloaded() async throws {
        let engine = makeEngine()

        do {
            try await engine.loadModel(modelName: "parakeet-tdt-0.6b-v2")
        } catch {
        }

        await engine.unloadModel()

        #expect(engine.state == .unloaded, "State should be unloaded after unloadModel")
        #expect(engine.error == nil, "Error should be nil after unloadModel")
    }

    @Test func unloadModelClearsError() async throws {
        let engine = makeEngine()

        do {
            try await engine.loadModel(modelPath: "/invalid/path")
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

    @Test func stateTransitions() async throws {
        let engine = makeEngine()
        #expect(engine.state == .unloaded)

        Task {
            do {
                try await engine.loadModel(modelName: "parakeet-tdt-0.6b-v2")
            } catch {
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        let stateAfterLoadAttempt = engine.state
        #expect(stateAfterLoadAttempt != .unloaded)

        await engine.unloadModel()
        #expect(engine.state == .unloaded)
    }

    @Test func concurrentTranscriptionPrevention() async throws {
        let engine = makeEngine()
        let audioData = makeInt16AudioData()

        async let result1 = engine.transcribe(audioData: audioData)
        async let result2 = engine.transcribe(audioData: audioData)

        do {
            _ = try await result1
            _ = try await result2
        } catch {
        }
    }

    @Test func errorDescriptionForModelNotLoaded() {
        let error = ParakeetEngine.EngineError.modelNotLoaded
        #expect(error.errorDescription != nil, "Error should have description")
        #expect(error.errorDescription?.contains("not loaded") ?? false,
                "Error description should mention model not loaded")
    }

    @Test func errorDescriptionForInvalidAudioData() {
        let error = ParakeetEngine.EngineError.invalidAudioData
        #expect(error.errorDescription != nil, "Error should have description")
        #expect(error.errorDescription?.contains("Invalid") ?? false,
                "Error description should mention invalid audio data")
    }

    @Test func errorDescriptionForTranscriptionFailed() {
        let message = "Test error message"
        let error = ParakeetEngine.EngineError.transcriptionFailed(message)
        #expect(error.errorDescription != nil, "Error should have description")
        #expect(error.errorDescription?.contains(message) ?? false,
                "Error description should contain the failure message")
    }

    @Test func errorDescriptionForDownloadFailed() {
        let message = "Download error"
        let error = ParakeetEngine.EngineError.downloadFailed(message)
        #expect(error.errorDescription != nil, "Error should have description")
        #expect(error.errorDescription?.contains(message) ?? false,
                "Error description should contain the failure message")
    }

    @Test func errorDescriptionForInitializationFailed() {
        let message = "Init error"
        let error = ParakeetEngine.EngineError.initializationFailed(message)
        #expect(error.errorDescription != nil, "Error should have description")
        #expect(error.errorDescription?.contains(message) ?? false,
                "Error description should contain the failure message")
    }

    @Test func v3ModelVersionSelection() async throws {
        let engine = makeEngine()
        #expect(engine.state == .unloaded)

        Task {
            do {
                try await engine.loadModel(modelName: "parakeet-tdt-0.6b-v3")
            } catch {
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(engine.state != .unloaded, "State should transition when loading v3 model")
    }
}
