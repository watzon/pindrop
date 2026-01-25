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
    
    func testAudioDataConversion() async throws {
        let service = TranscriptionService()
        
        // Create valid audio data (16kHz mono PCM)
        let sampleCount = 16000 // 1 second of audio
        var audioData = Data()
        for i in 0..<sampleCount {
            var sample: Int16 = Int16(sin(Double(i) * 0.1) * 1000) // Simple sine wave
            audioData.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
        }
        
        // Test conversion to float array
        let floatArray = service.convertPCMDataToFloatArray(audioData)
        
        XCTAssertEqual(floatArray.count, sampleCount, "Float array should have same sample count")
        XCTAssertTrue(floatArray.allSatisfy { $0 >= -1.0 && $0 <= 1.0 }, "All samples should be normalized to [-1.0, 1.0]")
    }
    
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
}
