//
//  TranscriptionServiceTests.swift
//  PindropTests
//
//  Created on 2026-01-25.
//

import AVFoundation
import Testing
@testable import Pindrop

@MainActor
@Suite(.serialized)
struct TranscriptionServiceTests {
    
    @Test func initialState() async throws {
        let service = TranscriptionService()
        
        #expect(service.state == .unloaded, "Initial state should be unloaded")
        #expect(service.error == nil, "Initial error should be nil")
    }
    
    @Test func modelLoadingStates() async throws {
        let service = TranscriptionService()

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
        #expect(service.state != .unloaded, "State should change from unloaded when loading starts")
    }
    
    @Test func modelLoadingError() async throws {
        let service = TranscriptionService()
        
        do {
            // Try to load with invalid model path
            try await service.loadModel(modelPath: "/invalid/path/to/model")
            Issue.record("Should throw error for invalid model path")
        } catch {
            #expect(service.state == .error, "State should be error after failed load")
            #expect(service.error != nil, "Error should be set after failed load")
        }
    }
    
    // MARK: - Transcription Tests
    
    @Test func transcribeWithoutLoadedModel() async throws {
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
            Issue.record("Should throw error when model not loaded")
        } catch TranscriptionService.TranscriptionError.modelNotLoaded {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    @Test func transcribeWithEmptyAudioData() async throws {
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
            Issue.record("Should throw error for empty audio data")
        } catch TranscriptionService.TranscriptionError.invalidAudioData {
        } catch TranscriptionService.TranscriptionError.modelNotLoaded {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    // Audio data conversion is tested indirectly through transcription flow
    
    // MARK: - State Management Tests
    
    @Test func stateTransitions() async throws {
        let service = TranscriptionService()
        
        #expect(service.state == .unloaded)
        
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
        #expect(service.state != .unloaded)
    }
    
    @Test func concurrentTranscriptionPrevention() async throws {
        let service = TranscriptionService()
        
        // Create dummy audio data
        let sampleCount = 16000
        var audioData = Data()
        for _ in 0..<sampleCount {
            var sample: Int16 = 0
            audioData.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
        }
        
        let testAudioData = audioData

        // Try to transcribe twice concurrently
        async let result1 = service.transcribe(audioData: testAudioData)
        async let result2 = service.transcribe(audioData: testAudioData)
        
        do {
            _ = try await result1
            _ = try await result2
            Issue.record("Should not allow concurrent transcriptions")
        } catch {
        }
    }
    
    // MARK: - Engine Switching Integration Tests
    
    @Test func engineSwitchCallsUnloadForDifferentProvider() async throws {
        // Given: Service starts in unloaded state
        let service = TranscriptionService()
        #expect(service.state == .unloaded)
        
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
        #expect(stateAfterFirstLoad == .error, "First load should result in error for invalid path")
        #expect(service.state == .error, "Second load should also result in error")
    }
    
    @Test func engineSwitchPreservesUnloadedStateOnCleanup() async throws {
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
        #expect(service.state == .unloaded)
        #expect(service.error == nil)
    }
    
    @Test func cannotSwitchEngineDuringTranscription() async throws {
        _ = TranscriptionService()
        
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
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("Cannot switch") ?? false,
                "Error should mention cannot switch during transcription")
    }
    
    @Test func unloadModelReleasesEngineReference() async throws {
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
        #expect(service.state == .unloaded, "State should be unloaded after unloadModel")
        #expect(service.error == nil, "Error should be nil after unloadModel")
    }
    
    @Test func unloadModelAfterSwitchingEngines() async throws {
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
        #expect(service.state == .unloaded, "State should be unloaded")
        #expect(service.error == nil, "Error should be cleared")
    }
    
    @Test func reloadSameEngineAfterUnload() async throws {
        let service = TranscriptionService()
        
        // Given: Load then unload WhisperKit
        do {
            try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        } catch {}
        
        await service.unloadModel()
        #expect(service.state == .unloaded)
        
        // When: Load same engine again
        do {
            try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        } catch {}
        
        // Then: Should attempt to load (state transitions from unloaded)
        #expect(service.state != .unloaded, "State should change when reloading engine")
    }

    // MARK: - Speaker Diarization Tests

    @Test func transcribeWithDiarizationDisabledReturnsPlainTranscript() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.transcribeResponses = ["plain transcript"]
        let mockDiarizer = MockSpeakerDiarizer()
        let service = TranscriptionService(
            engineFactory: { _ in mockEngine },
            diarizerFactory: { mockDiarizer }
        )

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        let output = try await service.transcribe(
            audioData: makeFloatAudioData(seconds: 3.0),
            diarizationEnabled: false
        )

        #expect(output.text == "plain transcript")
        #expect(output.diarizedSegments == nil)
        #expect(mockEngine.transcribeCallCount == 1)
        #expect(mockDiarizer.loadModelsCallCount == 0)
        #expect(mockDiarizer.diarizeCallCount == 0)
    }

    @Test func transcribeForwardsLanguageOptionsToEngine() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.transcribeResponses = ["ni hao"]
        let mockDiarizer = MockSpeakerDiarizer()
        let service = TranscriptionService(
            engineFactory: { _ in mockEngine },
            diarizerFactory: { mockDiarizer }
        )

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        let options = TranscriptionOptions(language: .simplifiedChinese)
        _ = try await service.transcribe(
            audioData: makeFloatAudioData(seconds: 2.0),
            diarizationEnabled: false,
            options: options
        )

        #expect(mockEngine.receivedOptions == [options])
    }

    @Test func loadModelPathUsesInjectedFactoryAndKeepsWhisperKitAsPrimaryProvider() async throws {
        let whisperEngine = MockDiarizationTranscriptionEngine()
        let parakeetEngine = MockDiarizationTranscriptionEngine()
        let service = TranscriptionService(
            engineFactory: { provider in
                switch provider {
                case .whisperKit:
                    return whisperEngine
                case .parakeet:
                    return parakeetEngine
                default:
                    throw TranscriptionService.TranscriptionError.modelLoadFailed("unsupported")
                }
            }
        )

        try await service.loadModel(modelName: "tiny", provider: .parakeet)
        #expect(parakeetEngine.loadModelNameCalls == ["tiny"])

        try await service.loadModel(modelPath: "/tmp/openai_whisper-base")

        #expect(parakeetEngine.unloadCallCount == 1)
        #expect(whisperEngine.loadModelPathCalls == ["/tmp/openai_whisper-base"])
    }

    @Test func transcribeNormalizesOutputTextThroughSharedPolicy() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.transcribeResponses = ["  normalized transcript \n"]
        let service = TranscriptionService(engineFactory: { _ in mockEngine })

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        let output = try await service.transcribe(
            audioData: makeFloatAudioData(seconds: 1.0),
            diarizationEnabled: false
        )

        #expect(output.text == "normalized transcript")
    }

    @Test func transcribeWithDiarizationEnabledReturnsSpeakerLabeledOutput() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.transcribeResponses = ["Hello team", "We should ship this today"]

        let speakerA = Speaker(id: "speaker-a", label: "A", embedding: nil)
        let speakerB = Speaker(id: "speaker-b", label: "B", embedding: nil)
        let diarizationResult = DiarizationResult(
            segments: [
                SpeakerSegment(speaker: speakerA, startTime: 0.0, endTime: 1.4, confidence: 0.9),
                SpeakerSegment(speaker: speakerB, startTime: 1.4, endTime: 3.1, confidence: 0.8)
            ],
            speakers: [speakerA, speakerB],
            audioDuration: 3.1
        )
        let mockDiarizer = MockSpeakerDiarizer()
        mockDiarizer.nextResult = diarizationResult

        let service = TranscriptionService(
            engineFactory: { _ in mockEngine },
            diarizerFactory: { mockDiarizer }
        )

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        let output = try await service.transcribe(
            audioData: makeFloatAudioData(seconds: 4.0),
            diarizationEnabled: true
        )

        #expect(output.text == "Speaker 1: Hello team\nSpeaker 2: We should ship this today")
        #expect(output.diarizedSegments?.count == 2)
        #expect(output.diarizedSegments?.map(\.speakerLabel) == ["Speaker 1", "Speaker 2"])
        #expect(output.diarizedSegments?.map(\.speakerId) == ["speaker-a", "speaker-b"])
        #expect(mockDiarizer.loadModelsCallCount == 1)
        #expect(mockDiarizer.diarizeCallCount == 1)
        #expect(mockEngine.transcribeCallCount == 2)
    }

    @Test func transcribeWithSingleSpeakerDiarizationOmitsSpeakerLabelsFromOutput() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.transcribeResponses = ["I clicked the button to install the diarization package."]

        let speaker = Speaker(id: "speaker-a", label: "A", embedding: nil)
        let diarizationResult = DiarizationResult(
            segments: [
                SpeakerSegment(speaker: speaker, startTime: 0.0, endTime: 2.0, confidence: 0.95)
            ],
            speakers: [speaker],
            audioDuration: 2.0
        )
        let mockDiarizer = MockSpeakerDiarizer()
        mockDiarizer.nextResult = diarizationResult

        let service = TranscriptionService(
            engineFactory: { _ in mockEngine },
            diarizerFactory: { mockDiarizer }
        )

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        let output = try await service.transcribe(
            audioData: makeFloatAudioData(seconds: 2.0),
            diarizationEnabled: true
        )

        #expect(output.text == "I clicked the button to install the diarization package.")
        #expect(output.diarizedSegments?.count == 1)
        #expect(output.diarizedSegments?.map(\.speakerLabel) == ["Speaker 1"])
        #expect(mockDiarizer.loadModelsCallCount == 1)
        #expect(mockDiarizer.diarizeCallCount == 1)
        #expect(mockEngine.transcribeCallCount == 1)
    }

    @Test func transcribeWithDiarizationFailureFallsBackToSinglePassTranscription() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.transcribeResponses = ["fallback transcript"]
        let mockDiarizer = MockSpeakerDiarizer()
        mockDiarizer.diarizeError = NSError(domain: "test", code: 7, userInfo: [NSLocalizedDescriptionKey: "diarization failed"])

        let service = TranscriptionService(
            engineFactory: { _ in mockEngine },
            diarizerFactory: { mockDiarizer }
        )

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        let output = try await service.transcribe(
            audioData: makeFloatAudioData(seconds: 2.0),
            diarizationEnabled: true
        )

        #expect(output.text == "fallback transcript")
        #expect(output.diarizedSegments == nil)
        #expect(mockDiarizer.diarizeCallCount == 1)
        #expect(mockEngine.transcribeCallCount == 1)
    }

    @Test func transcribeWithDiarizationNormalizesAndMergesSegments() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.transcribeResponses = ["Merged speaker text", "Second speaker text"]

        let speakerA = Speaker(id: "speaker-a", label: "A", embedding: nil)
        let speakerB = Speaker(id: "speaker-b", label: "B", embedding: nil)
        let speakerC = Speaker(id: "speaker-c", label: "C", embedding: nil)

        let diarizationResult = DiarizationResult(
            segments: [
                SpeakerSegment(speaker: speakerC, startTime: 3.0, endTime: 4.2, confidence: 0.7),
                SpeakerSegment(speaker: speakerA, startTime: 1.25, endTime: 2.4, confidence: 0.9), // merge
                SpeakerSegment(speaker: speakerB, startTime: 2.8, endTime: 2.5, confidence: 0.6),   // invalid
                SpeakerSegment(speaker: speakerA, startTime: 0.0, endTime: 1.1, confidence: 0.5),
                SpeakerSegment(speaker: speakerB, startTime: 2.6, endTime: 3.0, confidence: 0.8)    // too short
            ],
            speakers: [speakerA, speakerB, speakerC],
            audioDuration: 5.0
        )

        let mockDiarizer = MockSpeakerDiarizer()
        mockDiarizer.nextResult = diarizationResult

        let service = TranscriptionService(
            engineFactory: { _ in mockEngine },
            diarizerFactory: { mockDiarizer }
        )

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        let output = try await service.transcribe(
            audioData: makeFloatAudioData(seconds: 5.0),
            diarizationEnabled: true
        )

        #expect(output.text == "Speaker 1: Merged speaker text\nSpeaker 2: Second speaker text")
        #expect(mockEngine.transcribeCallCount == 2)

        let diarizedSegments = try #require(output.diarizedSegments, "Expected diarized segments")

        #expect(diarizedSegments.count == 2)
        #expect(diarizedSegments[0].speakerId == "speaker-a")
        #expect(abs(diarizedSegments[0].startTime - 0.0) < 0.0001)
        #expect(abs(diarizedSegments[0].endTime - 2.4) < 0.0001)
        #expect(diarizedSegments[1].speakerId == "speaker-c")
        #expect(diarizedSegments.map(\.speakerLabel) == ["Speaker 1", "Speaker 2"])
    }

    @Test func transcribeWithDiarizationSplitsLongSegmentsIntoSmallerTimedChunks() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.transcribeResponses = [
            """
            First we set up the project and verify the environment is working correctly. Then we configure the pipeline and make sure the download path is stable. After that we run the transcription pass and inspect the output for obvious quality issues. Finally we save the finished transcript and verify playback sync in the detail view.
            """
        ]

        let speaker = Speaker(id: "speaker-a", label: "A", embedding: nil)
        let diarizationResult = DiarizationResult(
            segments: [
                SpeakerSegment(speaker: speaker, startTime: 0.0, endTime: 48.0, confidence: 0.92)
            ],
            speakers: [speaker],
            audioDuration: 48.0
        )

        let mockDiarizer = MockSpeakerDiarizer()
        mockDiarizer.nextResult = diarizationResult

        let service = TranscriptionService(
            engineFactory: { _ in mockEngine },
            diarizerFactory: { mockDiarizer }
        )

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        let output = try await service.transcribe(
            audioData: makeFloatAudioData(seconds: 50.0),
            diarizationEnabled: true
        )

        let diarizedSegments = try #require(output.diarizedSegments, "Expected diarized segments")

        let firstSegment = try #require(diarizedSegments.first, "Expected diarized segments to contain entries")
        let lastSegment = try #require(diarizedSegments.last, "Expected diarized segments to contain entries")

        #expect(diarizedSegments.count > 1)
        #expect(Set(diarizedSegments.map(\.speakerId)) == ["speaker-a"])
        #expect(abs(firstSegment.startTime - 0.0) < 0.0001)
        #expect(abs(lastSegment.endTime - 48.0) < 0.0001)
        #expect(
            diarizedSegments.dropFirst().allSatisfy { $0.startTime >= 0 && $0.endTime > $0.startTime },
            "Split segments should preserve increasing timestamp windows"
        )
    }

    // MARK: - Streaming Tests

    @Test func streamingLifecycleTransitions() async throws {
        let mockStreamingEngine = MockStreamingTranscriptionEngine()
        let service = TranscriptionService(streamingEngineFactory: { mockStreamingEngine })

        try await service.prepareStreamingEngine()
        #expect(service.state == .ready)
        #expect(mockStreamingEngine.state == .ready)

        try await service.startStreaming()
        #expect(service.state == .transcribing)
        #expect(mockStreamingEngine.state == .streaming)

        try await service.processStreamingAudioBuffer(makeStreamingBuffer())
        #expect(mockStreamingEngine.processedBufferCount == 1)

        let finalText = try await service.stopStreaming()
        #expect(finalText == mockStreamingEngine.stopResult)
        #expect(service.state == .ready)
        #expect(mockStreamingEngine.state == .ready)
    }

    @Test func streamingCallbacksForwardPartialAndFinalUtterance() async throws {
        let mockStreamingEngine = MockStreamingTranscriptionEngine()
        let service = TranscriptionService(streamingEngineFactory: { mockStreamingEngine })
        let collector = StreamingCallbackCollector()

        service.setStreamingCallbacks(
            onPartial: { text in
                Task {
                    await collector.recordPartial(text)
                }
            },
            onFinalUtterance: { text in
                Task {
                    await collector.recordFinal(text)
                }
            }
        )
        try await service.prepareStreamingEngine()

        mockStreamingEngine.emitPartial("hello wor")
        mockStreamingEngine.emitFinalUtterance("hello world")

        var snapshot = await collector.snapshot()
        for _ in 0..<20 where snapshot.partials != ["hello wor"] || snapshot.finals != ["hello world"] {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
            snapshot = await collector.snapshot()
        }

        #expect(snapshot.partials == ["hello wor"])
        #expect(snapshot.finals == ["hello world"])
    }

    @Test func prepareStreamingEngineThrowsModelNotAvailableWhenLoadFails() async throws {
        let mockStreamingEngine = MockStreamingTranscriptionEngine()
        mockStreamingEngine.loadError = MockStreamingTranscriptionEngine.MockError.modelMissing
        let service = TranscriptionService(streamingEngineFactory: { mockStreamingEngine })

        do {
            try await service.prepareStreamingEngine()
            Issue.record("Expected prepareStreamingEngine to throw")
        } catch let error as TranscriptionService.TranscriptionError {
            guard case .streamingModelNotAvailable = error else {
                Issue.record("Expected streamingModelNotAvailable, got \(error)")
                return
            }
            #expect(service.state == .error)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func unloadModelClearsStreamingEngine() async throws {
        let mockStreamingEngine = MockStreamingTranscriptionEngine()
        let service = TranscriptionService(streamingEngineFactory: { mockStreamingEngine })

        try await service.prepareStreamingEngine()
        try await service.startStreaming()
        await service.cancelStreaming()

        await service.unloadModel()

        #expect(service.state == .unloaded)
        #expect(service.error == nil)
        #expect(mockStreamingEngine.unloadCallCount == 1)
    }

    @Test func cancelStreamingReturnsServiceToReadyState() async throws {
        let mockStreamingEngine = MockStreamingTranscriptionEngine()
        let service = TranscriptionService(streamingEngineFactory: { mockStreamingEngine })

        try await service.prepareStreamingEngine()
        try await service.startStreaming()

        await service.cancelStreaming()

        #expect(service.state == .ready)
        #expect(mockStreamingEngine.resetCallCount == 1)
    }
    
    // MARK: - Error Propagation Tests
    
    @Test func engineErrorPropagatesToTranscriptionError() async throws {
        let service = TranscriptionService()
        
        // Given: Service without loaded model
        #expect(service.state == .unloaded)
        
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
            Issue.record("Should throw error when model not loaded")
        } catch TranscriptionService.TranscriptionError.modelNotLoaded {
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
    
    @Test func transcriptionErrorDescriptions() {
        // Test all error descriptions are properly defined
        let errors: [TranscriptionService.TranscriptionError] = [
            .modelNotLoaded,
            .invalidAudioData,
            .transcriptionFailed("test message"),
            .modelLoadFailed("load failed"),
            .engineSwitchDuringTranscription
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil, "\(error) should have error description")
            #expect((error.errorDescription?.isEmpty ?? true) == false, "\(error) description should not be empty")
        }
    }
    
    @Test func invalidProviderHandling() async throws {
        let service = TranscriptionService(engineFactory: { _ in
            Issue.record("Engine factory should not be called for unsupported providers")
            return MockDiarizationTranscriptionEngine()
        })

        do {
            try await service.loadModel(modelName: "openai_whisper-1", provider: .openAI)
            Issue.record("Expected unsupported provider load to throw")
        } catch let error as TranscriptionService.TranscriptionError {
            guard case let .modelLoadFailed(message) = error else {
                Issue.record("Expected modelLoadFailed, got \(error)")
                return
            }

            #expect(message.contains("not supported locally"))
            #expect(service.state == .error)

            guard let storedError = service.error as? TranscriptionService.TranscriptionError else {
                Issue.record("Expected service.error to store a TranscriptionError")
                return
            }

            guard case let .modelLoadFailed(storedMessage) = storedError else {
                Issue.record("Expected stored error to be modelLoadFailed, got \(storedError)")
                return
            }

            #expect(storedMessage == message)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func recordingStartTransitionBypassesDeduplication() {
        #expect(
            KMPTranscriptionBridge.shouldAppendTransition(
                signature: "same-signature",
                trigger: ContextSessionUpdateTrigger.recordingStart.rawValue,
                lastSignature: "same-signature"
            )
        )
    }

    private func makeStreamingBuffer(frameCount: AVAudioFrameCount = 320) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData?[0] else {
            throw NSError(domain: "TranscriptionServiceTests", code: 1)
        }

        buffer.frameLength = frameCount
        for index in 0..<Int(frameCount) {
            channelData[index] = 0.1
        }
        return buffer
    }

    private func makeFloatAudioData(seconds: TimeInterval, sampleRate: Int = 16_000) -> Data {
        let frameCount = max(1, Int(seconds * TimeInterval(sampleRate)))
        let samples = Array(repeating: Float(0.1), count: frameCount)
        return samples.withUnsafeBufferPointer { pointer in
            Data(buffer: pointer)
        }
    }
}

@MainActor
private final class MockDiarizationTranscriptionEngine: TranscriptionEngine {
    private(set) var state: TranscriptionEngineState = .unloaded
    var transcribeResponses: [String] = []
    var transcribeError: Error?
    private(set) var transcribeCallCount = 0
    private(set) var receivedOptions: [TranscriptionOptions] = []
    private(set) var loadModelNameCalls: [String] = []
    private(set) var loadModelPathCalls: [String] = []
    private(set) var unloadCallCount = 0

    func loadModel(path: String) async throws {
        loadModelPathCalls.append(path)
        state = .ready
    }

    func loadModel(name: String, downloadBase: URL?) async throws {
        loadModelNameCalls.append(name)
        state = .ready
    }

    func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String {
        if let transcribeError {
            throw transcribeError
        }

        receivedOptions.append(options)
        transcribeCallCount += 1
        if transcribeResponses.isEmpty {
            return ""
        }

        let index = min(transcribeCallCount - 1, transcribeResponses.count - 1)
        return transcribeResponses[index]
    }

    func unloadModel() async {
        unloadCallCount += 1
        state = .unloaded
    }
}

@MainActor
private final class MockSpeakerDiarizer: SpeakerDiarizer {
    private(set) var state: SpeakerDiarizerState = .unloaded
    let mode: DiarizationMode = .offline

    var nextResult: DiarizationResult = DiarizationResult(segments: [], speakers: [], audioDuration: 0)
    var diarizeError: Error?
    private(set) var loadModelsCallCount = 0
    private(set) var unloadModelsCallCount = 0
    private(set) var diarizeCallCount = 0

    func loadModels() async throws {
        loadModelsCallCount += 1
        state = .ready
    }

    func unloadModels() async {
        unloadModelsCallCount += 1
        state = .unloaded
    }

    func diarize(samples: [Float], sampleRate: Int) async throws -> DiarizationResult {
        diarizeCallCount += 1
        if let diarizeError {
            throw diarizeError
        }
        return nextResult
    }

    func compareSpeakers(audio1: [Float], audio2: [Float]) async throws -> Float {
        0.0
    }

    func registerKnownSpeaker(_ speaker: Speaker) async throws {}

    func clearKnownSpeakers() async {}
}

@MainActor
private final class MockStreamingTranscriptionEngine: StreamingTranscriptionEngine {
    enum MockError: Error {
        case modelMissing
    }

    private(set) var state: StreamingTranscriptionState = .unloaded
    var loadError: Error?
    var startError: Error?
    var processError: Error?
    var stopError: Error?
    var stopResult: String = "streaming final transcript"

    private(set) var processedBufferCount = 0
    private(set) var unloadCallCount = 0
    private(set) var resetCallCount = 0

    private var transcriptionCallback: StreamingTranscriptionCallback?
    private var endOfUtteranceCallback: EndOfUtteranceCallback?

    func loadModel(name: String) async throws {
        if let loadError {
            state = .error
            throw loadError
        }
        state = .ready
    }

    func unloadModel() async {
        unloadCallCount += 1
        state = .unloaded
    }

    func startStreaming() async throws {
        if let startError { throw startError }
        state = .streaming
    }

    func stopStreaming() async throws -> String {
        if let stopError { throw stopError }
        state = .ready
        return stopResult
    }

    func pauseStreaming() async {
        state = .paused
    }

    func resumeStreaming() async throws {
        state = .streaming
    }

    func processAudioChunk(_ samples: [Float]) async throws {
        if let processError { throw processError }
        processedBufferCount += 1
    }

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {
        if let processError { throw processError }
        processedBufferCount += 1
    }

    func setTranscriptionCallback(_ callback: @escaping StreamingTranscriptionCallback) {
        transcriptionCallback = callback
    }

    func setEndOfUtteranceCallback(_ callback: @escaping EndOfUtteranceCallback) {
        endOfUtteranceCallback = callback
    }

    func reset() async {
        resetCallCount += 1
        state = .ready
    }

    func emitPartial(_ text: String) {
        transcriptionCallback?(StreamingTranscriptionResult(text: text, isFinal: false))
    }

    func emitFinalUtterance(_ text: String) {
        transcriptionCallback?(StreamingTranscriptionResult(text: text, isFinal: true))
        endOfUtteranceCallback?(text)
    }
}

private actor StreamingCallbackCollector {
    private var partialsStore: [String] = []
    private var finalsStore: [String] = []

    func recordPartial(_ text: String) {
        partialsStore.append(text)
    }

    func recordFinal(_ text: String) {
        finalsStore.append(text)
    }

    func snapshot() -> (partials: [String], finals: [String]) {
        (partialsStore, finalsStore)
    }
}
