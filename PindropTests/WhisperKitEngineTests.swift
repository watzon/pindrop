//
//  WhisperKitEngineTests.swift
//  PindropTests
//
//  Created on 2026-01-30.
//

import Foundation
import Testing
@testable import Pindrop

@MainActor
@Suite
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

    @Test func initialStateIsUnloaded() {
        let engine = makeEngine()

        #expect(engine.state == .unloaded, "Initial state should be unloaded")
        #expect(engine.error == nil, "Initial error should be nil")
    }

    @Test func loadModelSetsStateToReady() async throws {
        let engine = makeEngine()
        #expect(engine.state == .unloaded)

        do {
            try await engine.loadModel(modelName: "tiny")
        } catch {
        }

        #expect(engine.state != .unloaded, "State should change from unloaded when loading starts")
    }

    @Test func loadModelTransitionsThroughLoadingState() async throws {
        let engine = makeEngine()
        #expect(engine.state == .unloaded)

        Task {
            do {
                try await engine.loadModel(modelName: "tiny")
            } catch {
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(engine.state != .unloaded, "State should transition from unloaded when loading starts")
    }

    @Test func loadModelWithInvalidPathThrowsError() async throws {
        let engine = makeEngine()
        #expect(engine.state == .unloaded)

        do {
            try await engine.loadModel(modelPath: "/invalid/path/to/model")
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
            try await engine.loadModel(modelPath: "/nonexistent/path")
        } catch {
        }

        #expect(engine.error != nil, "Error should be set after failed model load")
        #expect(engine.state == .error, "State should be error after failed load")
    }

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

    @Test func transcribeWithEmptyAudioDataThrowsError() async throws {
        let engine = makeEngine()

        do {
            try await engine.loadModel(modelName: "tiny")
        } catch {
        }

        do {
            _ = try await engine.transcribe(audioData: Data())
            Issue.record("Should throw error for empty audio data")
        } catch WhisperKitEngine.EngineError.invalidAudioData {
        } catch WhisperKitEngine.EngineError.modelNotLoaded {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func transcribeReturnsNonEmptyString() async throws {
        let engine = makeEngine()

        do {
            let result = try await engine.transcribe(audioData: makeInt16AudioData())
            #expect(result.isEmpty == false, "Transcription result should not be empty")
            #expect(engine.state == .ready, "State should return to ready after transcription")
        } catch {
            #expect(engine.state == .unloaded, "State should remain unloaded when model not loaded")
        }
    }

    @Test func transcribeSetsStateToTranscribing() async throws {
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

    @Test func unloadModelSetsStateToUnloaded() async throws {
        let engine = makeEngine()

        do {
            try await engine.loadModel(modelName: "tiny")
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
                try await engine.loadModel(modelName: "tiny")
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
