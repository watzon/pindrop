//
//  TranscriptionEngineTests.swift
//  PindropTests
//
//  Created on 2026-01-30.
//

import Foundation
import Testing
@testable import Pindrop

@MainActor
@Suite
struct TranscriptionEngineTests {
    @Test func transcriptionEngineStateEquatable() {
        #expect(TranscriptionEngineState.unloaded == .unloaded)
        #expect(TranscriptionEngineState.loading == .loading)
        #expect(TranscriptionEngineState.ready == .ready)
        #expect(TranscriptionEngineState.transcribing == .transcribing)
        #expect(TranscriptionEngineState.error == .error)

        #expect(TranscriptionEngineState.unloaded != .loading)
        #expect(TranscriptionEngineState.ready != .transcribing)
    }

    @Test func transcriptionEngineStateCases() {
        let states: [TranscriptionEngineState] = [.unloaded, .loading, .ready, .transcribing, .error]
        #expect(states.count == 5)
    }

    @Test func mockEngineConformsToProtocol() {
        let engine = MockTranscriptionEngine()
        #expect(engine is TranscriptionEngine)
    }

    @Test func mockEngineInitialState() {
        let engine = MockTranscriptionEngine()
        #expect(engine.state == .unloaded)
    }

    @Test func mockEngineStateTransitions() async throws {
        let engine = MockTranscriptionEngine()

        #expect(engine.state == .unloaded)

        try await engine.loadModel(name: "tiny", downloadBase: nil)
        #expect(engine.state == .ready)

        let audioData = Data([0x00, 0x01, 0x02, 0x03])
        _ = try await engine.transcribe(audioData: audioData)
        #expect(engine.state == .ready)

        await engine.unloadModel()
        #expect(engine.state == .unloaded)
    }

    @Test func mockEngineLoadByPath() async throws {
        let engine = MockTranscriptionEngine()
        try await engine.loadModel(path: "/path/to/model")
        #expect(engine.state == .ready)
    }

    @Test func mockEngineTranscription() async throws {
        let engine = MockTranscriptionEngine()
        try await engine.loadModel(name: "tiny", downloadBase: nil)

        let audioData = Data([0x00, 0x01, 0x02, 0x03])
        let result = try await engine.transcribe(audioData: audioData)

        #expect(result == "Mock transcription result")
    }

    @Test func mockEngineErrorState() async {
        let engine = MockTranscriptionEngine()
        engine.shouldFailLoad = true

        do {
            try await engine.loadModel(name: "tiny", downloadBase: nil)
            Issue.record("Expected load failure")
        } catch {
            #expect(engine.state == .error)
        }
    }
}

@MainActor
final class MockTranscriptionEngine: TranscriptionEngine {
    private(set) var state: TranscriptionEngineState = .unloaded
    var shouldFailLoad = false
    var mockTranscriptionResult = "Mock transcription result"
    private(set) var lastOptions: TranscriptionOptions?

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

    func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String {
        guard state == .ready else {
            throw MockError.modelNotLoaded
        }

        lastOptions = options
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
