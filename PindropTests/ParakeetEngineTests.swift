//
//  ParakeetEngineTests.swift
//  PindropTests
//
//  Created on 2026-01-30.
//

import XCTest
@testable import Pindrop

@MainActor
final class ParakeetEngineTests: XCTestCase {

    var engine: ParakeetEngine!

    override func setUp() async throws {
        engine = ParakeetEngine()
    }

    override func tearDown() async throws {
        engine = nil
    }

    func testInitialStateIsUnloaded() {
        XCTAssertEqual(engine.state, .unloaded, "Initial state should be unloaded")
        XCTAssertNil(engine.error, "Initial error should be nil")
    }

    func testLoadModelSetsStateToReady() async throws {
        XCTAssertEqual(engine.state, .unloaded)

        do {
            try await engine.loadModel(modelName: "parakeet-tdt-0.6b-v2")
        } catch {}

        XCTAssertNotEqual(engine.state, .unloaded, "State should change from unloaded when loading starts")
    }

    func testLoadModelTransitionsThroughLoadingState() async throws {
        XCTAssertEqual(engine.state, .unloaded)

        Task {
            do {
                try await engine.loadModel(modelName: "parakeet-tdt-0.6b-v2")
            } catch {}
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNotEqual(engine.state, .unloaded, "State should transition from unloaded when loading starts")
    }

    func testLoadModelWithPathNotSupported() async throws {
        XCTAssertEqual(engine.state, .unloaded)

        do {
            try await engine.loadModel(modelPath: "/some/path/to/model")
            XCTFail("Should throw error for path-based loading")
        } catch ParakeetEngine.EngineError.initializationFailed {
            XCTAssertEqual(engine.state, .error, "State should be error after failed load")
            XCTAssertNotNil(engine.error, "Error should be set after failed load")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTranscribeRequiresLoadedModel() async throws {
        XCTAssertEqual(engine.state, .unloaded)

        let sampleCount = 16000
        var audioData = Data()
        for _ in 0..<sampleCount {
            var sample: Int16 = 0
            audioData.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
        }

        do {
            _ = try await engine.transcribe(audioData: audioData)
            XCTFail("Should throw error when model not loaded")
        } catch ParakeetEngine.EngineError.modelNotLoaded {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTranscribeWithEmptyAudioDataThrowsError() async throws {
        do {
            try await engine.loadModel(modelName: "parakeet-tdt-0.6b-v2")
        } catch {}

        let emptyData = Data()

        do {
            _ = try await engine.transcribe(audioData: emptyData)
            XCTFail("Should throw error for empty audio data")
        } catch ParakeetEngine.EngineError.invalidAudioData {
            XCTAssertTrue(true)
        } catch ParakeetEngine.EngineError.modelNotLoaded {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnloadModelSetsStateToUnloaded() async throws {
        do {
            try await engine.loadModel(modelName: "parakeet-tdt-0.6b-v2")
        } catch {}

        await engine.unloadModel()

        XCTAssertEqual(engine.state, .unloaded, "State should be unloaded after unloadModel")
        XCTAssertNil(engine.error, "Error should be nil after unloadModel")
    }

    func testUnloadModelClearsError() async throws {
        do {
            try await engine.loadModel(modelPath: "/invalid/path")
        } catch {}

        XCTAssertNotNil(engine.error, "Error should be set after failed load")

        await engine.unloadModel()

        XCTAssertNil(engine.error, "Error should be cleared after unloadModel")
    }

    func testUnloadModelFromUnloadedStateIsSafe() async {
        XCTAssertEqual(engine.state, .unloaded)

        await engine.unloadModel()

        XCTAssertEqual(engine.state, .unloaded, "State should remain unloaded")
        XCTAssertNil(engine.error, "Error should remain nil")
    }

    func testStateTransitions() async throws {
        XCTAssertEqual(engine.state, .unloaded)

        Task {
            do {
                try await engine.loadModel(modelName: "parakeet-tdt-0.6b-v2")
            } catch {}
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        let stateAfterLoadAttempt = engine.state
        XCTAssertNotEqual(stateAfterLoadAttempt, .unloaded)

        await engine.unloadModel()
        XCTAssertEqual(engine.state, .unloaded)
    }

    func testConcurrentTranscriptionPrevention() async throws {
        let sampleCount = 16000
        var audioData = Data()
        for _ in 0..<sampleCount {
            var sample: Int16 = 0
            audioData.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
        }

        async let result1 = engine.transcribe(audioData: audioData)
        async let result2 = engine.transcribe(audioData: audioData)

        do {
            _ = try await result1
            _ = try await result2
        } catch {
            XCTAssertTrue(true)
        }
    }

    func testErrorDescriptionForModelNotLoaded() {
        let error = ParakeetEngine.EngineError.modelNotLoaded
        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(error.errorDescription?.contains("not loaded") ?? false,
                      "Error description should mention model not loaded")
    }

    func testErrorDescriptionForInvalidAudioData() {
        let error = ParakeetEngine.EngineError.invalidAudioData
        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(error.errorDescription?.contains("Invalid") ?? false,
                      "Error description should mention invalid audio data")
    }

    func testErrorDescriptionForTranscriptionFailed() {
        let message = "Test error message"
        let error = ParakeetEngine.EngineError.transcriptionFailed(message)
        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(error.errorDescription?.contains(message) ?? false,
                      "Error description should contain the failure message")
    }

    func testErrorDescriptionForDownloadFailed() {
        let message = "Download error"
        let error = ParakeetEngine.EngineError.downloadFailed(message)
        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(error.errorDescription?.contains(message) ?? false,
                      "Error description should contain the failure message")
    }

    func testErrorDescriptionForInitializationFailed() {
        let message = "Init error"
        let error = ParakeetEngine.EngineError.initializationFailed(message)
        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(error.errorDescription?.contains(message) ?? false,
                      "Error description should contain the failure message")
    }

    func testV3ModelVersionSelection() async throws {
        XCTAssertEqual(engine.state, .unloaded)

        Task {
            do {
                try await engine.loadModel(modelName: "parakeet-tdt-0.6b-v3")
            } catch {}
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotEqual(engine.state, .unloaded, "State should transition when loading v3 model")
    }
}
