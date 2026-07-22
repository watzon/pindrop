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

    @Test func openAIEngineUploadsMultipartAudioAndParsesTranscript() async throws {
        let session = OpenAITranscriptionSessionStub()
        session.responseData = Data(#"{"text":"Cloud transcript"}"#.utf8)
        session.statusCode = 200
        let engine = OpenAITranscriptionEngine(
            apiKeyProvider: { "sk-test-key" },
            session: session
        )

        try await engine.loadModel(name: "openai_gpt-4o-transcribe", downloadBase: nil)
        let audioData = Data(count: 16_000 * MemoryLayout<Float>.size)
        let transcript = try await engine.transcribe(
            audioData: audioData,
            options: TranscriptionOptions(
                language: .english,
                vocabularyBiasWords: ["Pindrop", "WhisperKit"]
            )
        )

        #expect(transcript == "Cloud transcript")
        let request = try #require(session.lastRequest)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/transcriptions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-key")
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("name=\"model\""))
        #expect(body.contains("gpt-4o-transcribe"))
        #expect(body.contains("name=\"language\""))
        #expect(body.contains("\r\n\r\nen\r\n"))
        #expect(body.contains("name=\"prompt\""))
        #expect(body.contains("Pindrop, WhisperKit"))
        #expect(body.contains("filename=\"audio.m4a\""))
    }

    @Test func openAIEngineRequiresConfiguredAPIKey() async {
        let engine = OpenAITranscriptionEngine(apiKeyProvider: { "" })

        await #expect(throws: OpenAITranscriptionEngine.EngineError.self) {
            try await engine.loadModel(name: "openai_gpt-4o-transcribe", downloadBase: nil)
        }
        #expect(engine.state == .error)
    }

    @Test func openAIEngineSurfacesAPIErrorMessage() async throws {
        let session = OpenAITranscriptionSessionStub()
        session.responseData = Data(#"{"error":{"message":"Incorrect API key provided"}}"#.utf8)
        session.statusCode = 401
        let engine = OpenAITranscriptionEngine(
            apiKeyProvider: { "sk-invalid" },
            session: session
        )

        try await engine.loadModel(name: "openai_gpt-4o-mini-transcribe", downloadBase: nil)
        await #expect(throws: OpenAITranscriptionEngine.EngineError.self) {
            _ = try await engine.transcribe(
                audioData: Data(count: 4),
                options: TranscriptionOptions()
            )
        }
        #expect(engine.error?.localizedDescription.contains("Incorrect API key provided") == true)
        #expect(engine.state == .ready)
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


@MainActor
private final class OpenAITranscriptionSessionStub: URLSessionProtocol {
    var responseData = Data()
    var statusCode = 200
    private(set) var lastRequest: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["x-request-id": "req-test"]
        )!
        return (responseData, response)
    }
}

enum MockError: Error {
    case loadFailed
    case modelNotLoaded
}
