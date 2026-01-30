//
//  TranscriptionEngineTests.swift
//  PindropTests
//
//  Created on 2026-01-30.
//

import XCTest
@testable import Pindrop

@MainActor
final class TranscriptionEngineTests: XCTestCase {
    
    // MARK: - State Enum Tests
    
    func testTranscriptionEngineStateEquatable() {
        XCTAssertEqual(TranscriptionEngineState.unloaded, TranscriptionEngineState.unloaded)
        XCTAssertEqual(TranscriptionEngineState.loading, TranscriptionEngineState.loading)
        XCTAssertEqual(TranscriptionEngineState.ready, TranscriptionEngineState.ready)
        XCTAssertEqual(TranscriptionEngineState.transcribing, TranscriptionEngineState.transcribing)
        XCTAssertEqual(TranscriptionEngineState.error, TranscriptionEngineState.error)
        
        XCTAssertNotEqual(TranscriptionEngineState.unloaded, TranscriptionEngineState.loading)
        XCTAssertNotEqual(TranscriptionEngineState.ready, TranscriptionEngineState.transcribing)
    }
    
    func testTranscriptionEngineStateCases() {
        let states: [TranscriptionEngineState] = [
            .unloaded,
            .loading,
            .ready,
            .transcribing,
            .error
        ]
        
        XCTAssertEqual(states.count, 5, "Should have exactly 5 state cases")
    }
    
    // MARK: - Protocol Conformance Tests
    
    func testMockEngineConformsToProtocol() {
        let engine = MockTranscriptionEngine()
        
        XCTAssertTrue(engine is TranscriptionEngine, "Mock should conform to TranscriptionEngine protocol")
    }
    
    func testMockEngineInitialState() {
        let engine = MockTranscriptionEngine()
        
        XCTAssertEqual(engine.state, .unloaded, "Initial state should be unloaded")
    }
    
    func testMockEngineStateTransitions() async throws {
        let engine = MockTranscriptionEngine()
        
        XCTAssertEqual(engine.state, .unloaded)
        
        try await engine.loadModel(name: "tiny", downloadBase: nil)
        XCTAssertEqual(engine.state, .ready, "State should be ready after successful load")
        
        let audioData = Data([0x00, 0x01, 0x02, 0x03])
        _ = try await engine.transcribe(audioData: audioData)
        XCTAssertEqual(engine.state, .ready, "State should return to ready after transcription")
        
        await engine.unloadModel()
        XCTAssertEqual(engine.state, .unloaded, "State should be unloaded after unload")
    }
    
    func testMockEngineLoadByPath() async throws {
        let engine = MockTranscriptionEngine()
        
        try await engine.loadModel(path: "/path/to/model")
        XCTAssertEqual(engine.state, .ready)
    }
    
    func testMockEngineTranscription() async throws {
        let engine = MockTranscriptionEngine()
        
        try await engine.loadModel(name: "tiny", downloadBase: nil)
        
        let audioData = Data([0x00, 0x01, 0x02, 0x03])
        let result = try await engine.transcribe(audioData: audioData)
        
        XCTAssertEqual(result, "Mock transcription result", "Should return mock transcription text")
    }
    
    func testMockEngineErrorState() async {
        let engine = MockTranscriptionEngine()
        engine.shouldFailLoad = true
        
        do {
            try await engine.loadModel(name: "tiny", downloadBase: nil)
            XCTFail("Should throw error when shouldFailLoad is true")
        } catch {
            XCTAssertEqual(engine.state, .error, "State should be error after failed load")
        }
    }
}

// MARK: - Mock Implementation

@MainActor
final class MockTranscriptionEngine: TranscriptionEngine {
    private(set) var state: TranscriptionEngineState = .unloaded
    var shouldFailLoad = false
    var mockTranscriptionResult = "Mock transcription result"
    
    func loadModel(path: String) async throws {
        if shouldFailLoad {
            state = .error
            throw MockError.loadFailed
        }
        state = .ready
    }
    
    func loadModel(name: String, downloadBase: URL?) async throws {
        if shouldFailLoad {
            state = .error
            throw MockError.loadFailed
        }
        state = .ready
    }
    
    func transcribe(audioData: Data) async throws -> String {
        guard state == .ready else {
            throw MockError.modelNotLoaded
        }
        
        state = .transcribing
        
        try await Task.sleep(nanoseconds: 10_000_000)
        
        state = .ready
        return mockTranscriptionResult
    }
    
    func unloadModel() async {
        state = .unloaded
    }
}

enum MockError: Error {
    case loadFailed
    case modelNotLoaded
}
