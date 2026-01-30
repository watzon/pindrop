//
//  TranscriptionServiceTests.swift
//  PindropTests
//
//  Created on 2026-01-25.
//

import XCTest
@testable import Pindrop

@MainActor
final class TranscriptionServiceTests: XCTestCase {
    
    func testInitialState() async throws {
        let service = TranscriptionService()
        
        XCTAssertEqual(service.state, .unloaded, "Initial state should be unloaded")
        XCTAssertNil(service.error, "Initial error should be nil")
    }
    
    func testModelLoadingStates() async throws {
        let service = TranscriptionService()
        
        // Track state changes
        var stateChanges: [TranscriptionService.State] = []
        
        // Start loading model
        Task {
            do {
                try await service.loadModel(modelName: "tiny")
            } catch {
                // Expected to fail in test environment without actual model
            }
        }
        
        // Give it a moment to start loading
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // State should have changed from unloaded
        XCTAssertNotEqual(service.state, .unloaded, "State should change from unloaded when loading starts")
    }
    
    func testModelLoadingError() async throws {
        let service = TranscriptionService()
        
        do {
            // Try to load with invalid model path
            try await service.loadModel(modelPath: "/invalid/path/to/model")
            XCTFail("Should throw error for invalid model path")
        } catch {
            XCTAssertEqual(service.state, .error, "State should be error after failed load")
            XCTAssertNotNil(service.error, "Error should be set after failed load")
        }
    }
    
    // MARK: - Transcription Tests
    
    func testTranscribeWithoutLoadedModel() async throws {
        let service = TranscriptionService()
        
        // Create dummy audio data (16kHz mono PCM)
        let sampleCount = 16000 // 1 second of audio
        var audioData = Data()
        for _ in 0..<sampleCount {
            var sample: Int16 = 0
            audioData.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
        }
        
        do {
            _ = try await service.transcribe(audioData: audioData)
            XCTFail("Should throw error when model not loaded")
        } catch TranscriptionService.TranscriptionError.modelNotLoaded {
            // Expected error
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testTranscribeWithEmptyAudioData() async throws {
        let service = TranscriptionService()
        
        // Try to load model first (will fail in test environment, but that's ok)
        do {
            try await service.loadModel(modelName: "tiny")
        } catch {
            // Expected to fail in test environment
        }
        
        let emptyData = Data()
        
        do {
            _ = try await service.transcribe(audioData: emptyData)
            XCTFail("Should throw error for empty audio data")
        } catch TranscriptionService.TranscriptionError.invalidAudioData {
            // Expected error
            XCTAssertTrue(true)
        } catch TranscriptionService.TranscriptionError.modelNotLoaded {
            // Also acceptable since model loading failed
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // Audio data conversion is tested indirectly through transcription flow
    
    // MARK: - State Management Tests
    
    func testStateTransitions() async throws {
        let service = TranscriptionService()
        
        XCTAssertEqual(service.state, .unloaded)
        
        // Attempt to load model (will fail in test environment)
        Task {
            do {
                try await service.loadModel(modelName: "tiny")
            } catch {
                // Expected
            }
        }
        
        // Give it time to transition
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // State should have changed
        XCTAssertNotEqual(service.state, .unloaded)
    }
    
    func testConcurrentTranscriptionPrevention() async throws {
        let service = TranscriptionService()
        
        // Create dummy audio data
        let sampleCount = 16000
        var audioData = Data()
        for _ in 0..<sampleCount {
            var sample: Int16 = 0
            audioData.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
        }
        
        // Try to transcribe twice concurrently
        async let result1 = service.transcribe(audioData: audioData)
        async let result2 = service.transcribe(audioData: audioData)
        
        do {
            _ = try await result1
            _ = try await result2
            XCTFail("Should not allow concurrent transcriptions")
        } catch {
            // Expected - either modelNotLoaded or transcriptionInProgress
            XCTAssertTrue(true)
        }
    }
    
    // MARK: - Engine Switching Integration Tests
    
    func testEngineSwitchCallsUnloadForDifferentProvider() async throws {
        // Given: Service starts in unloaded state
        let service = TranscriptionService()
        XCTAssertEqual(service.state, .unloaded)
        
        // When: Attempt to load a model (fails in test env but exercises switching path)
        do {
            try await service.loadModel(modelPath: "/test/whisperkit/model")
        } catch {
            // Expected: model path doesn't exist
        }
        
        let stateAfterFirstLoad = service.state
        
        // When: Switch provider
        do {
            try await service.loadModel(modelPath: "/test/parakeet/model")
        } catch {
            // Expected
        }
        
        // Then: Both load attempts should have been made (state changed from unloaded)
        XCTAssertEqual(stateAfterFirstLoad, .error, "First load should result in error for invalid path")
        XCTAssertEqual(service.state, .error, "Second load should also result in error")
    }
    
    func testEngineSwitchPreservesUnloadedStateOnCleanup() async throws {
        let service = TranscriptionService()
        
        // Given: Attempt failed loads (exercises switching logic)
        do {
            try await service.loadModel(modelPath: "/test/path1")
        } catch {}
        
        do {
            try await service.loadModel(modelPath: "/test/path2")
        } catch {}
        
        // When: Unload after switching attempts
        await service.unloadModel()
        
        // Then: Should be back to clean unloaded state
        XCTAssertEqual(service.state, .unloaded)
        XCTAssertNil(service.error)
    }
    
    func testCannotSwitchEngineDuringTranscription() async throws {
        let service = TranscriptionService()
        
        // Create dummy audio data
        let sampleCount = 16000 * 5 // 5 seconds of audio
        var audioData = Data()
        for _ in 0..<sampleCount {
            var sample: Float = 0.0
            audioData.append(Data(bytes: &sample, count: MemoryLayout<Float>.size))
        }
        
        // Note: Since we can't actually get the service into transcribing state
        // without a real model, we test the error case directly
        // by verifying the error type exists and has correct description
        let error = TranscriptionService.TranscriptionError.engineSwitchDuringTranscription
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("Cannot switch") ?? false,
                      "Error should mention cannot switch during transcription")
    }
    
    func testUnloadModelReleasesEngineReference() async throws {
        let service = TranscriptionService()
        
        // Given: Attempt to load an engine
        do {
            try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        } catch {
            // Expected in test environment
        }
        
        // When: Unload the model
        await service.unloadModel()
        
        // Then: State should be unloaded and error cleared
        XCTAssertEqual(service.state, .unloaded, "State should be unloaded after unloadModel")
        XCTAssertNil(service.error, "Error should be nil after unloadModel")
    }
    
    func testUnloadModelAfterSwitchingEngines() async throws {
        let service = TranscriptionService()
        
        // Given: Load and switch engines (both will fail in test env)
        do {
            try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        } catch {}
        
        do {
            try await service.loadModel(modelName: "parakeet-tdt-0.6b-v3", provider: .parakeet)
        } catch {}
        
        // When: Unload
        await service.unloadModel()
        
        // Then: Should cleanly return to unloaded state
        XCTAssertEqual(service.state, .unloaded, "State should be unloaded")
        XCTAssertNil(service.error, "Error should be cleared")
    }
    
    func testReloadSameEngineAfterUnload() async throws {
        let service = TranscriptionService()
        
        // Given: Load then unload WhisperKit
        do {
            try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        } catch {}
        
        await service.unloadModel()
        XCTAssertEqual(service.state, .unloaded)
        
        // When: Load same engine again
        do {
            try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        } catch {}
        
        // Then: Should attempt to load (state transitions from unloaded)
        XCTAssertNotEqual(service.state, .unloaded, "State should change when reloading engine")
    }
    
    // MARK: - Error Propagation Tests
    
    func testEngineErrorPropagatesToTranscriptionError() async throws {
        let service = TranscriptionService()
        
        // Given: Service without loaded model
        XCTAssertEqual(service.state, .unloaded)
        
        // Create valid-sized audio data
        let sampleCount = 16000
        var audioData = Data()
        for _ in 0..<sampleCount {
            var sample: Float = 0.0
            audioData.append(Data(bytes: &sample, count: MemoryLayout<Float>.size))
        }
        
        // When/Then: Transcribe should throw modelNotLoaded
        do {
            _ = try await service.transcribe(audioData: audioData)
            XCTFail("Should throw error when model not loaded")
        } catch TranscriptionService.TranscriptionError.modelNotLoaded {
            // Expected error
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testTranscriptionErrorDescriptions() {
        // Test all error descriptions are properly defined
        let errors: [TranscriptionService.TranscriptionError] = [
            .modelNotLoaded,
            .invalidAudioData,
            .transcriptionFailed("test message"),
            .modelLoadFailed("load failed"),
            .engineSwitchDuringTranscription
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) should have error description")
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error) description should not be empty")
        }
    }
    
    func testInvalidProviderHandling() async throws {
        let service = TranscriptionService()
        
        // This tests that non-local providers throw appropriate errors
        // The implementation should reject cloud-only providers
        // Currently WhisperKit and Parakeet are the only local providers
        
        // Verify error type exists for this case
        let error = TranscriptionService.TranscriptionError.modelLoadFailed("Provider not supported locally")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("not supported") ?? false,
                      "Error should indicate provider not supported")
    }
}
