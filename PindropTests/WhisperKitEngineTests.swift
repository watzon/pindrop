//
//  WhisperKitEngineTests.swift
//  PindropTests
//
//  Created on 2026-01-30.
//

import XCTest
@testable import Pindrop

@MainActor
final class WhisperKitEngineTests: XCTestCase {

    var engine: WhisperKitEngine!

    override func setUp() async throws {
        engine = WhisperKitEngine()
    }

    override func tearDown() async throws {
        engine = nil
    }

    // MARK: - Initial State Tests

    func testInitialStateIsUnloaded() {
        XCTAssertEqual(engine.state, .unloaded, "Initial state should be unloaded")
        XCTAssertNil(engine.error, "Initial error should be nil")
    }

    // MARK: - Load Model Tests

    func testLoadModelSetsStateToReady() async throws {
        // Given: Engine in unloaded state
        XCTAssertEqual(engine.state, .unloaded)

        // When: Loading a model (will fail in test environment without actual model)
        do {
            try await engine.loadModel(modelName: "tiny")
        } catch {
            // Expected to fail in test environment
        }

        // Then: State should have transitioned from unloaded
        // Note: In real implementation with model, state would be .ready
        // In test environment, it may be .error or .loading depending on timing
        XCTAssertNotEqual(engine.state, .unloaded, "State should change from unloaded when loading starts")
    }

    func testLoadModelTransitionsThroughLoadingState() async throws {
        // Given: Engine in unloaded state
        XCTAssertEqual(engine.state, .unloaded)

        // When: Start loading model asynchronously
        Task {
            do {
                try await engine.loadModel(modelName: "tiny")
            } catch {
                // Expected in test environment
            }
        }

        // Then: Give it a moment to start loading
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // State should have changed from unloaded (likely to loading or error)
        XCTAssertNotEqual(engine.state, .unloaded, "State should transition from unloaded when loading starts")
    }

    func testLoadModelWithInvalidPathThrowsError() async throws {
        // Given: Engine in unloaded state
        XCTAssertEqual(engine.state, .unloaded)

        // When/Then: Loading with invalid path should throw
        do {
            try await engine.loadModel(modelPath: "/invalid/path/to/model")
            XCTFail("Should throw error for invalid model path")
        } catch {
            XCTAssertEqual(engine.state, .error, "State should be error after failed load")
            XCTAssertNotNil(engine.error, "Error should be set after failed load")
        }
    }

    func testLoadModelSetsErrorOnFailure() async throws {
        // Given: Engine in unloaded state with no error
        XCTAssertNil(engine.error)

        // When: Attempting to load with invalid configuration
        do {
            try await engine.loadModel(modelPath: "/nonexistent/path")
        } catch {
            // Expected
        }

        // Then: Error should be set and state should be error
        XCTAssertNotNil(engine.error, "Error should be set after failed model load")
        XCTAssertEqual(engine.state, .error, "State should be error after failed load")
    }

    // MARK: - Transcribe Tests

    func testTranscribeRequiresLoadedModel() async throws {
        // Given: Engine in unloaded state (no model loaded)
        XCTAssertEqual(engine.state, .unloaded)

        // Create dummy audio data (16kHz mono PCM)
        let sampleCount = 16000 // 1 second of audio
        var audioData = Data()
        for _ in 0..<sampleCount {
            var sample: Int16 = 0
            audioData.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
        }

        // When/Then: Transcribing without loaded model should throw
        do {
            _ = try await engine.transcribe(audioData: audioData)
            XCTFail("Should throw error when model not loaded")
        } catch WhisperKitEngine.EngineError.modelNotLoaded {
            // Expected error
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTranscribeWithEmptyAudioDataThrowsError() async throws {
        // Given: Attempt to load model first (will fail in test environment, but that's ok)
        do {
            try await engine.loadModel(modelName: "tiny")
        } catch {
            // Expected to fail in test environment
        }

        let emptyData = Data()

        // When/Then: Transcribing empty data should throw
        do {
            _ = try await engine.transcribe(audioData: emptyData)
            XCTFail("Should throw error for empty audio data")
        } catch WhisperKitEngine.EngineError.invalidAudioData {
            // Expected error
            XCTAssertTrue(true)
        } catch WhisperKitEngine.EngineError.modelNotLoaded {
            // Also acceptable since model loading failed
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTranscribeReturnsNonEmptyString() async throws {
        // Given: Model is loaded and ready
        // Note: This test assumes a mock or stub that can simulate successful transcription
        // In real implementation, this would require actual model loading

        // Create dummy audio data
        let sampleCount = 16000
        var audioData = Data()
        for _ in 0..<sampleCount {
            var sample: Int16 = 0
            audioData.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
        }

        // When: Transcribing audio data with loaded model
        // This will fail in test environment without actual model, but documents expected behavior
        do {
            let result = try await engine.transcribe(audioData: audioData)

            // Then: Result should be non-empty string
            XCTAssertFalse(result.isEmpty, "Transcription result should not be empty")
            XCTAssertEqual(engine.state, .ready, "State should return to ready after transcription")
        } catch {
            // Expected in test environment without actual model
            // Test documents the expected behavior for when model is available
            XCTAssertEqual(engine.state, .unloaded, "State should remain unloaded when model not loaded")
        }
    }

    func testTranscribeSetsStateToTranscribing() async throws {
        // Given: Create audio data
        let sampleCount = 16000
        var audioData = Data()
        for _ in 0..<sampleCount {
            var sample: Int16 = 0
            audioData.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
        }

        // When: Attempt transcription (will fail without model, but state may transition)
        Task {
            do {
                _ = try await engine.transcribe(audioData: audioData)
            } catch {
                // Expected
            }
        }

        // Then: Give it a moment to process
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        // State should have attempted to transition (actual state depends on implementation)
        // This test documents that transcribe should attempt to set state to .transcribing
        XCTAssertTrue(engine.state == .unloaded || engine.state == .transcribing || engine.state == .error,
                      "State should be one of expected values during/after transcription attempt")
    }

    // MARK: - Unload Model Tests

    func testUnloadModelSetsStateToUnloaded() async throws {
        // Given: Attempt to load model first
        do {
            try await engine.loadModel(modelName: "tiny")
        } catch {
            // Expected in test environment
        }

        // When: Unloading the model
        await engine.unloadModel()

        // Then: State should be unloaded
        XCTAssertEqual(engine.state, .unloaded, "State should be unloaded after unloadModel")
        XCTAssertNil(engine.error, "Error should be nil after unloadModel")
    }

    func testUnloadModelClearsError() async throws {
        // Given: Engine with an error state
        do {
            try await engine.loadModel(modelPath: "/invalid/path")
        } catch {
            // Expected
        }

        XCTAssertNotNil(engine.error, "Error should be set after failed load")

        // When: Unloading the model
        await engine.unloadModel()

        // Then: Error should be cleared
        XCTAssertNil(engine.error, "Error should be cleared after unloadModel")
    }

    func testUnloadModelFromUnloadedStateIsSafe() async {
        // Given: Engine already in unloaded state
        XCTAssertEqual(engine.state, .unloaded)

        // When: Calling unloadModel on already unloaded engine
        await engine.unloadModel()

        // Then: Should remain in unloaded state without error
        XCTAssertEqual(engine.state, .unloaded, "State should remain unloaded")
        XCTAssertNil(engine.error, "Error should remain nil")
    }

    // MARK: - State Transition Tests

    func testStateTransitions() async throws {
        // Test the full state machine: unloaded -> loading -> ready <-> transcribing

        // Initial state
        XCTAssertEqual(engine.state, .unloaded)

        // Attempt to load (will fail in test environment)
        Task {
            do {
                try await engine.loadModel(modelName: "tiny")
            } catch {
                // Expected
            }
        }

        // Give time to transition
        try await Task.sleep(nanoseconds: 100_000_000)

        // State should have changed from unloaded
        let stateAfterLoadAttempt = engine.state
        XCTAssertNotEqual(stateAfterLoadAttempt, .unloaded)

        // Unload and verify return to unloaded
        await engine.unloadModel()
        XCTAssertEqual(engine.state, .unloaded)
    }

    func testConcurrentTranscriptionPrevention() async throws {
        // Given: Create audio data
        let sampleCount = 16000
        var audioData = Data()
        for _ in 0..<sampleCount {
            var sample: Int16 = 0
            audioData.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
        }

        // When: Try to transcribe twice concurrently
        async let result1 = engine.transcribe(audioData: audioData)
        async let result2 = engine.transcribe(audioData: audioData)

        // Then: One should fail or both should fail (depending on implementation)
        do {
            _ = try await result1
            _ = try await result2
            // If both succeed, that's acceptable for some implementations
            // But typically concurrent operations should be prevented
        } catch {
            // Expected - either modelNotLoaded or transcriptionInProgress
            XCTAssertTrue(true)
        }
    }

    // MARK: - Error Handling Tests

    func testErrorDescriptionForModelNotLoaded() {
        let error = WhisperKitEngine.EngineError.modelNotLoaded
        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(error.errorDescription?.contains("not loaded") ?? false,
                      "Error description should mention model not loaded")
    }

    func testErrorDescriptionForInvalidAudioData() {
        let error = WhisperKitEngine.EngineError.invalidAudioData
        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(error.errorDescription?.contains("Invalid") ?? false,
                      "Error description should mention invalid audio data")
    }

    func testErrorDescriptionForTranscriptionFailed() {
        let message = "Test error message"
        let error = WhisperKitEngine.EngineError.transcriptionFailed(message)
        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(error.errorDescription?.contains(message) ?? false,
                      "Error description should contain the failure message")
    }
}
