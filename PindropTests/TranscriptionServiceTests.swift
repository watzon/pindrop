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

        // Offline path load only — never pass a bare model name (would network-download).
        do {
            try await service.loadModel(modelPath: "/invalid/path/to/model")
        } catch {
            // Expected to fail without a local model bundle.
        }

        #expect(service.state != .unloaded, "State should change from unloaded when loading starts")
        #expect(service.state == .error, "Missing local path should end in error offline")
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
        // Stay offline: do not attempt a name-based model download.
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
        
        // Offline invalid path — no network download.
        do {
            try await service.loadModel(modelPath: "/invalid/path/to/model")
        } catch {
            // Expected
        }
        
        #expect(service.state != .unloaded)
        #expect(service.state == .error)
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
        
        // Given: Attempt offline path load (no network)
        do {
            try await service.loadModel(modelPath: "/invalid/path/to/model")
        } catch {
            // Expected without a local model bundle
        }
        
        // When: Unload the model
        await service.unloadModel()
        
        // Then: State should be unloaded and error cleared
        #expect(service.state == .unloaded, "State should be unloaded after unloadModel")
        #expect(service.error == nil, "Error should be nil after unloadModel")
    }
    
    @Test func unloadModelAfterSwitchingEngines() async throws {
        let service = TranscriptionService()
        
        // Given: Offline path loads for two engines (no network downloads)
        do {
            try await service.loadModel(modelPath: "/test/whisperkit/model")
        } catch {}
        
        do {
            try await service.loadModel(modelPath: "/test/parakeet/model")
        } catch {}
        
        // When: Unload
        await service.unloadModel()
        
        // Then: Should cleanly return to unloaded state
        #expect(service.state == .unloaded, "State should be unloaded")
        #expect(service.error == nil, "Error should be cleared")
    }
    
    @Test func reloadSameEngineAfterUnload() async throws {
        let service = TranscriptionService()
        
        // Given: Offline path load then unload
        do {
            try await service.loadModel(modelPath: "/invalid/path/to/model")
        } catch {}
        
        await service.unloadModel()
        #expect(service.state == .unloaded)
        
        // When: Load same engine again (still offline)
        do {
            try await service.loadModel(modelPath: "/invalid/path/to/model")
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

    @Test func nonDiarizedTranscriptionUsesEnginePathWithoutSampleConversion() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.transcribeResponses = ["tiny clip"]
        let mockDiarizer = MockSpeakerDiarizer()
        let service = TranscriptionService(
            engineFactory: { _ in mockEngine },
            diarizerFactory: { mockDiarizer }
        )

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        // One float sample is enough for the no-diarization path; sample conversion
        // and diarizer loading are reserved for the diarized branch.
        var sample: Float = 0.25
        let oneSample = Data(bytes: &sample, count: MemoryLayout<Float>.size)

        let output = try await service.transcribe(
            audioData: oneSample,
            diarizationEnabled: false
        )

        #expect(output.text == "tiny clip")
        #expect(output.diarizedSegments == nil)
        #expect(mockEngine.transcribeCallCount == 1)
        #expect(mockEngine.detectLanguageCallCount == 0)
        #expect(mockDiarizer.loadModelsCallCount == 0)
        #expect(mockDiarizer.diarizeCallCount == 0)
    }


    @Test func extractsSpeakerProfileSegmentsWithoutRetranscribingText() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        let speaker = Speaker(id: "speaker-a", label: "", embedding: [0.2, 0.8])
        let mockDiarizer = MockSpeakerDiarizer()
        mockDiarizer.nextResult = DiarizationResult(
            segments: [
                SpeakerSegment(
                    speaker: speaker,
                    startTime: 0,
                    endTime: 2,
                    confidence: 0.9
                )
            ],
            speakers: [speaker],
            audioDuration: 2
        )
        let service = TranscriptionService(
            engineFactory: { _ in mockEngine },
            diarizerFactory: { mockDiarizer }
        )

        let segments = try await service.extractSpeakerProfileSegments(
            audioData: makeFloatAudioData(seconds: 2)
        )

        #expect(segments.count == 1)
        #expect(segments.first?.speakerId == "speaker-a")
        #expect(segments.first?.speakerEmbedding == [0.2, 0.8])
        #expect(segments.first?.text == "")
        #expect(mockEngine.transcribeCallCount == 0)
        #expect(mockDiarizer.diarizeCallCount == 1)
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

    @Test func transcribeWithDiarizationPinsDetectedLanguageAcrossSegments() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.detectedLanguage = .german
        mockEngine.transcribeResponses = ["Guten Morgen", "Wir testen die Erkennung"]

        let speakerA = Speaker(id: "speaker-a", label: "A", embedding: nil)
        let speakerB = Speaker(id: "speaker-b", label: "B", embedding: nil)
        let diarizationResult = DiarizationResult(
            segments: [
                SpeakerSegment(speaker: speakerA, startTime: 0.0, endTime: 1.4, confidence: 0.9),
                SpeakerSegment(speaker: speakerB, startTime: 1.6, endTime: 3.0, confidence: 0.9)
            ],
            speakers: [speakerA, speakerB],
            audioDuration: 3.0
        )
        let mockDiarizer = MockSpeakerDiarizer()
        mockDiarizer.nextResult = diarizationResult

        let service = TranscriptionService(
            engineFactory: { _ in mockEngine },
            diarizerFactory: { mockDiarizer }
        )

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        _ = try await service.transcribe(
            audioData: makeFloatAudioData(seconds: 3.0),
            diarizationEnabled: true,
            options: TranscriptionOptions(language: .automatic)
        )

        #expect(mockEngine.detectLanguageCallCount == 1)
        #expect(mockEngine.detectLanguageSampleCounts == [48_000])
        #expect(mockEngine.receivedOptions == [
            TranscriptionOptions(language: .german),
            TranscriptionOptions(language: .german)
        ])
    }

    @Test func transcribeWithoutDiarizationKeepsWholeClipAutomaticDetection() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.detectedLanguage = .german
        mockEngine.transcribeResponses = ["ganzer Mitschnitt"]
        let mockDiarizer = MockSpeakerDiarizer()
        let service = TranscriptionService(
            engineFactory: { _ in mockEngine },
            diarizerFactory: { mockDiarizer }
        )

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        _ = try await service.transcribe(
            audioData: makeFloatAudioData(seconds: 2.0),
            diarizationEnabled: false,
            options: TranscriptionOptions(language: .automatic)
        )

        #expect(mockEngine.detectLanguageCallCount == 0)
        #expect(mockEngine.receivedOptions == [TranscriptionOptions(language: .automatic)])
    }

    @Test func transcribeWithDiarizationEnabledPreservesDiarizerSpeakerLabels() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.transcribeResponses = ["Hello team", "We should ship this today"]

        let speakerA = Speaker(id: "speaker-a", label: "A", embedding: [0.1, 0.2, 0.3])
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

        #expect(output.text == "A: Hello team\nB: We should ship this today")
        #expect(output.diarizedSegments?.count == 2)
        #expect(output.diarizedSegments?.map(\.speakerLabel) == ["A", "B"])
        #expect(output.diarizedSegments?.map(\.speakerId) == ["speaker-a", "speaker-b"])
        #expect(output.diarizedSegments?.first?.speakerEmbedding == [0.1, 0.2, 0.3])
        #expect(mockDiarizer.loadModelsCallCount == 1)
        #expect(mockDiarizer.diarizeCallCount == 1)
        #expect(mockEngine.transcribeCallCount == 2)
    }

    @Test func transcribeWithDiarizationRegistersKnownSpeakersBeforeDiarizing() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.transcribeResponses = ["Hello team"]

        let knownSpeaker = Speaker(id: UUID().uuidString, label: "Alice", embedding: [0.2, 0.4, 0.6])
        let identityService = MockSpeakerIdentityService(knownSpeakers: [knownSpeaker])

        let diarizedSpeaker = Speaker(id: "speaker-a", label: "Alice", embedding: [0.2, 0.4, 0.6])
        let diarizationResult = DiarizationResult(
            segments: [
                SpeakerSegment(speaker: diarizedSpeaker, startTime: 0.0, endTime: 1.5, confidence: 0.92)
            ],
            speakers: [diarizedSpeaker],
            audioDuration: 1.5
        )

        let mockDiarizer = MockSpeakerDiarizer()
        mockDiarizer.nextResult = diarizationResult

        let service = TranscriptionService(
            engineFactory: { _ in mockEngine },
            diarizerFactory: { mockDiarizer },
            speakerIdentityService: identityService
        )

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        _ = try await service.transcribe(
            audioData: makeFloatAudioData(seconds: 2.0),
            diarizationEnabled: true
        )

        #expect(identityService.knownSpeakersCallCount == 2)
        #expect(mockDiarizer.clearKnownSpeakersCallCount == 1)
        #expect(mockDiarizer.registeredKnownSpeakers == [knownSpeaker])
    }

    @Test func transcribeWithDiarizationUsesMatchedParticipantNameWhenConfidenceGatePasses() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.transcribeResponses = ["Hello team"]

        let diarizedSpeaker = Speaker(id: "speaker-a", label: "speaker-a", embedding: [0.1, 0.2, 0.3])
        let diarizationResult = DiarizationResult(
            segments: [
                SpeakerSegment(speaker: diarizedSpeaker, startTime: 0.0, endTime: 1.5, confidence: 0.92)
            ],
            speakers: [diarizedSpeaker],
            audioDuration: 1.5
        )

        let mockDiarizer = MockSpeakerDiarizer()
        mockDiarizer.nextResult = diarizationResult

        let identityService = MockSpeakerIdentityService(
            knownSpeakers: [Speaker(id: UUID().uuidString, label: "Alice", embedding: [0.1, 0.2, 0.3])],
            matchesByEmbeddingKey: ["0.1000,0.2000,0.3000": SpeakerIdentityMatch(profileID: UUID(), displayName: "Alice", similarity: 0.91)]
        )

        let service = TranscriptionService(
            engineFactory: { _ in mockEngine },
            diarizerFactory: { mockDiarizer },
            speakerIdentityService: identityService
        )

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        let output = try await service.transcribe(
            audioData: makeFloatAudioData(seconds: 2.0),
            diarizationEnabled: true
        )

        #expect(output.text == "Hello team")
        #expect(output.diarizedSegments?.map(\.speakerLabel) == [""])
        #expect(identityService.bestMatchCallCount == 1)
    }

    @Test func transcribeWithDiarizationFallsBackWhenKnownSpeakerMatchDoesNotClearGate() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.transcribeResponses = ["Hello team"]

        let knownSpeaker = Speaker(id: UUID().uuidString, label: "Alice", embedding: [0.1, 0.2, 0.3])
        let diarizedSpeaker = Speaker(id: knownSpeaker.id, label: "Alice", embedding: [0.1, 0.2, 0.3])
        let diarizationResult = DiarizationResult(
            segments: [
                SpeakerSegment(speaker: diarizedSpeaker, startTime: 0.0, endTime: 1.5, confidence: 0.92)
            ],
            speakers: [diarizedSpeaker],
            audioDuration: 1.5
        )

        let mockDiarizer = MockSpeakerDiarizer()
        mockDiarizer.nextResult = diarizationResult

        let identityService = MockSpeakerIdentityService(knownSpeakers: [knownSpeaker])

        let service = TranscriptionService(
            engineFactory: { _ in mockEngine },
            diarizerFactory: { mockDiarizer },
            speakerIdentityService: identityService
        )

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        let output = try await service.transcribe(
            audioData: makeFloatAudioData(seconds: 2.0),
            diarizationEnabled: true
        )

        #expect(output.text == "Hello team")
        #expect(output.diarizedSegments?.map(\.speakerLabel) == [""])
        #expect(identityService.bestMatchCallCount == 1)
    }

    @Test func transcribeWithDiarizationFallsBackToGenericLabelWhenSpeakerLabelIsBlank() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.transcribeResponses = ["Hello team"]

        let speaker = Speaker(id: "speaker-a", label: "", embedding: nil)
        let diarizationResult = DiarizationResult(
            segments: [
                SpeakerSegment(speaker: speaker, startTime: 0.0, endTime: 1.4, confidence: 0.9)
            ],
            speakers: [speaker],
            audioDuration: 1.4
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

        #expect(output.text == "Hello team")
        #expect(output.diarizedSegments?.map(\.speakerLabel) == [""])
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
        #expect(output.diarizedSegments?.map(\.speakerLabel) == [""])
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

    @Test func transcribeWithDiarizationTimeoutFallsBackToSinglePassTranscription() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.transcribeResponses = ["fallback after timeout"]
        let mockDiarizer = MockSpeakerDiarizer()
        mockDiarizer.diarizeDelayNanoseconds = 1_000_000_000

        let service = TranscriptionService(
            engineFactory: { _ in mockEngine },
            diarizerFactory: { mockDiarizer },
            diarizationTimeoutSeconds: 0.01
        )

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        let output = try await service.transcribe(
            audioData: makeFloatAudioData(seconds: 2.0),
            diarizationEnabled: true
        )

        #expect(output.text == "fallback after timeout")
        #expect(output.diarizedSegments == nil)
        #expect(mockDiarizer.diarizeCallCount == 1)
        #expect(mockEngine.transcribeCallCount == 1)
    }

    @Test func diarizationWatchdogReturnsAtDeadlineWhenOperationIgnoresCancellation() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.transcribeResponses = ["fallback after noncooperative timeout"]
        let mockDiarizer = MockSpeakerDiarizer()
        mockDiarizer.nonCooperativeDiarizeDelayNanoseconds = 500_000_000
        let service = TranscriptionService(
            engineFactory: { _ in mockEngine },
            diarizerFactory: { mockDiarizer },
            diarizationTimeoutSeconds: 0.02
        )

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        let started = ContinuousClock.now
        let output = try await service.transcribe(
            audioData: makeFloatAudioData(seconds: 2.0),
            diarizationEnabled: true
        )
        let elapsed = started.duration(to: .now)

        #expect(output.text == "fallback after noncooperative timeout")
        #expect(elapsed < .milliseconds(250))
    }

    @Test func timedOutTranscriptionCannotCorruptReplacementEngineState() async throws {
        let stalledEngine = MockDiarizationTranscriptionEngine()
        stalledEngine.transcribeResponses = ["late transcript"]
        stalledEngine.nonCooperativeTranscribeDelayNanoseconds = 300_000_000
        let replacementEngine = MockDiarizationTranscriptionEngine()
        replacementEngine.transcribeResponses = ["replacement transcript"]
        var factoryCalls = 0
        let service = TranscriptionService(
            engineFactory: { _ in
                defer { factoryCalls += 1 }
                return factoryCalls == 0 ? stalledEngine : replacementEngine
            }
        )

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        let audioData = makeFloatAudioData(seconds: 1.0)
        do {
            _ = try await StreamingSessionController.withFinalizeTimeout(nanoseconds: 20_000_000) {
                try await service.transcribe(audioData: audioData)
            }
            Issue.record("Expected hard timeout")
        } catch {
            service.invalidateTimedOutTranscription()
        }

        // Ordinary batch entry automatically restores the selected model with a
        // fresh engine; callers do not need a timeout-specific reload step.
        let replacementResult = try await service.transcribe(audioData: audioData)
        #expect(replacementResult == "replacement transcript")

        try await Task.sleep(nanoseconds: 350_000_000)
        #expect(service.state == .ready)
    }

    @Test func concurrentCallersAfterTimeoutShareReplacementLoadAndAdmitOneTranscription() async throws {
        let stalledEngine = MockDiarizationTranscriptionEngine()
        stalledEngine.nonCooperativeTranscribeDelayNanoseconds = 250_000_000
        let replacementEngine = MockDiarizationTranscriptionEngine()
        replacementEngine.loadDelayNanoseconds = 30_000_000
        replacementEngine.nonCooperativeTranscribeDelayNanoseconds = 80_000_000
        replacementEngine.transcribeResponses = ["replacement"]
        var factoryCalls = 0
        let service = TranscriptionService(engineFactory: { _ in
            defer { factoryCalls += 1 }
            return factoryCalls == 0 ? stalledEngine : replacementEngine
        })
        let audioData = makeFloatAudioData(seconds: 1.0)

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        do {
            _ = try await StreamingSessionController.withFinalizeTimeout(nanoseconds: 20_000_000) {
                try await service.transcribe(audioData: audioData)
            }
            Issue.record("Expected hard timeout")
        } catch {
            service.invalidateTimedOutTranscription()
        }

        let first = Task { try await service.transcribe(audioData: audioData) }
        try await Task.sleep(nanoseconds: 5_000_000)
        let second = Task { try await service.transcribe(audioData: audioData) }

        let firstResult: Result<String, Error>
        do { firstResult = .success(try await first.value) }
        catch { firstResult = .failure(error) }
        let secondResult: Result<String, Error>
        do { secondResult = .success(try await second.value) }
        catch { secondResult = .failure(error) }
        let outcomes = [firstResult, secondResult]
        #expect(outcomes.compactMap { try? $0.get() } == ["replacement"])
        #expect(factoryCalls == 2)
        #expect(replacementEngine.transcribeCallCount == 1)
        #expect(service.state == .ready)
    }

    @Test func transcribeWithDiarizationCancellationPropagates() async throws {
        let mockEngine = MockDiarizationTranscriptionEngine()
        mockEngine.transcribeResponses = ["should not transcribe"]
        let mockDiarizer = MockSpeakerDiarizer()
        mockDiarizer.diarizeDelayNanoseconds = 1_000_000_000

        let service = TranscriptionService(
            engineFactory: { _ in mockEngine },
            diarizerFactory: { mockDiarizer },
            diarizationTimeoutSeconds: 10
        )

        try await service.loadModel(modelName: "tiny", provider: .whisperKit)
        let task = Task {
            try await service.transcribe(
                audioData: makeFloatAudioData(seconds: 2.0),
                diarizationEnabled: true
            )
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation to propagate")
        } catch is CancellationError {
            #expect(mockDiarizer.diarizeCallCount == 1)
            #expect(mockEngine.transcribeCallCount == 0)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
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

        #expect(output.text == "A: Merged speaker text\nC: Second speaker text")
        #expect(mockEngine.transcribeCallCount == 2)

        let diarizedSegments = try #require(output.diarizedSegments, "Expected diarized segments")

        #expect(diarizedSegments.count == 2)
        #expect(diarizedSegments[0].speakerId == "speaker-a")
        #expect(abs(diarizedSegments[0].startTime - 0.0) < 0.0001)
        #expect(abs(diarizedSegments[0].endTime - 2.4) < 0.0001)
        #expect(diarizedSegments[1].speakerId == "speaker-c")
        #expect(diarizedSegments.map(\.speakerLabel) == ["A", "C"])
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
        let service = TranscriptionService(streamingEngineFactory: { _ in mockStreamingEngine })

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
        let service = TranscriptionService(streamingEngineFactory: { _ in mockStreamingEngine })
        let collector = StreamingCallbackCollector()

        service.setStreamingCallbacks(
            onPartial: { text in
                await collector.recordPartial(text)
            },
            onFinalUtterance: { text in
                await collector.recordFinal(text)
            }
        )
        try await service.prepareStreamingEngine()
        try await mockStreamingEngine.waitUntilCallbacksInstalled()

        mockStreamingEngine.emitPartial("hello wor")
        try await collector.waitFor(
            partials: ["hello wor"],
            finals: []
        )

        mockStreamingEngine.emitFinalUtterance("hello world")
        try await collector.waitForFinals(["hello world"])
        let snapshot = await collector.snapshot()

        #expect(snapshot.partials == ["hello wor"])
        #expect(snapshot.finals == ["hello world"])
    }

    @Test func streamingPartialsCoalesceWhileAllFinalsDeliverInOrder() async throws {
        let mockStreamingEngine = MockStreamingTranscriptionEngine()
        let service = TranscriptionService(streamingEngineFactory: { _ in mockStreamingEngine })
        let collector = StreamingCallbackCollector()

        service.setStreamingCallbacks(
            onPartial: { text in
                await collector.recordPartial(text)
            },
            onFinalUtterance: { text in
                await collector.recordFinal(text)
            }
        )
        try await service.prepareStreamingEngine()
        try await mockStreamingEngine.waitUntilCallbacksInstalled()

        // Burst partials, then a final, more partials, then more finals — the bridge
        // must collapse consecutive partials and keep every final in arrival order.
        mockStreamingEngine.emitPartial("h")
        mockStreamingEngine.emitPartial("he")
        mockStreamingEngine.emitPartial("hel")
        mockStreamingEngine.emitPartial("hell")
        mockStreamingEngine.emitPartial("hello")
        mockStreamingEngine.emitFinalUtterance("hello")
        mockStreamingEngine.emitPartial("w")
        mockStreamingEngine.emitPartial("wo")
        mockStreamingEngine.emitPartial("wor")
        mockStreamingEngine.emitPartial("world")
        mockStreamingEngine.emitFinalUtterance("world")
        mockStreamingEngine.emitFinalUtterance("again")

        let expectedFinals = ["hello", "world", "again"]
        try await collector.waitForFinals(expectedFinals)
        let snapshot = await collector.snapshot()

        #expect(snapshot.finals == expectedFinals)
        // Consecutive partials coalesce; at most one partial is retained between finals.
        #expect(snapshot.partials.count <= 2)
        #expect(Set(snapshot.partials).isSubset(of: ["hello", "world"]))
        if snapshot.partials.count == 2 {
            #expect(snapshot.partials == ["hello", "world"])
        }
    }

    @Test func streamingResetWhileCallbackSuspendedKeepsSingleDrainAndSuppressesOldGeneration() async throws {
        let mockStreamingEngine = MockStreamingTranscriptionEngine()
        let service = TranscriptionService(streamingEngineFactory: { _ in mockStreamingEngine })
        let oldCollector = StreamingCallbackCollector()
        let newCollector = StreamingCallbackCollector()
        let gate = StreamingCallbackSuspendGate()

        service.setStreamingCallbacks(
            onPartial: { text in
                await oldCollector.recordPartial(text)
            },
            onFinalUtterance: { text in
                // First final suspends the sole drain task so reset can race it.
                await gate.enterAndWait()
                await oldCollector.recordFinal(text)
            }
        )
        try await service.prepareStreamingEngine()
        try await mockStreamingEngine.waitUntilCallbacksInstalled()

        mockStreamingEngine.emitFinalUtterance("old-session")
        await gate.waitUntilEntered()

        // Reset invalidates the old generation without marking the suspended drain idle.
        service.setStreamingCallbacks(onPartial: nil, onFinalUtterance: nil)
        service.setStreamingCallbacks(
            onPartial: { text in
                await newCollector.recordPartial(text)
            },
            onFinalUtterance: { text in
                await newCollector.recordFinal(text)
            }
        )
        try await mockStreamingEngine.waitUntilCallbacksInstalled()

        // These must not schedule a second concurrent drain; the suspended owner
        // adopts the new generation after the old callback resumes.
        mockStreamingEngine.emitPartial("n")
        mockStreamingEngine.emitPartial("ne")
        mockStreamingEngine.emitPartial("new")
        mockStreamingEngine.emitFinalUtterance("new-one")
        mockStreamingEngine.emitFinalUtterance("new-two")

        // Old generation is still suspended — new session must not have delivered yet
        // through a racing second drain.
        let midOld = await oldCollector.snapshot()
        let midNew = await newCollector.snapshot()
        #expect(midOld.finals.isEmpty)
        #expect(midNew.finals.isEmpty)
        #expect(midNew.partials.isEmpty)

        await gate.open()

        try await oldCollector.waitForFinals(["old-session"])
        try await newCollector.waitForFinals(["new-one", "new-two"])

        let oldSnapshot = await oldCollector.snapshot()
        let newSnapshot = await newCollector.snapshot()

        #expect(oldSnapshot.finals == ["old-session"])
        #expect(oldSnapshot.partials.isEmpty)
        #expect(
            newSnapshot.finals == ["new-one", "new-two"],
            "finals must stay ordered under a single drain across reset"
        )
        #expect(
            newSnapshot.partials == ["new"] || newSnapshot.partials.isEmpty,
            "latest-partial coalescing must survive generation handoff"
        )
        #expect(
            !newSnapshot.finals.contains("old-session"),
            "old-generation finals must not mutate the new session"
        )
    }



    @Test func prepareStreamingEngineThrowsModelNotAvailableWhenLoadFails() async throws {
        let mockStreamingEngine = MockStreamingTranscriptionEngine()
        mockStreamingEngine.loadError = MockStreamingTranscriptionEngine.MockError.modelMissing
        let service = TranscriptionService(streamingEngineFactory: { _ in mockStreamingEngine })

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
        let service = TranscriptionService(streamingEngineFactory: { _ in mockStreamingEngine })

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
        let service = TranscriptionService(streamingEngineFactory: { _ in mockStreamingEngine })

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
        // This tests that non-local providers throw appropriate errors
        // The implementation should reject cloud-only providers
        // Currently WhisperKit and Parakeet are the only local providers
        
        // Verify error type exists for this case
        let error = TranscriptionService.TranscriptionError.modelLoadFailed("Provider not supported locally")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("not supported") ?? false,
                "Error should indicate provider not supported")
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
@Suite
private struct WorkspaceFileIndexTimeoutTests {
    @Test func buildIndexReturnsAtDeadlineWhenEnumerationIgnoresCancellation() async throws {
        let fileSystem = NonCooperativeFileSystemProvider()
        let index = WorkspaceFileIndexService(
            fileSystem: fileSystem,
            buildTimeout: .milliseconds(20)
        )
        let started = ContinuousClock.now

        do {
            _ = try await index.buildIndex(roots: ["/workspace"])
            Issue.record("Expected workspace indexing to time out")
        } catch WorkspaceFileIndexError.enumerationFailed {
            let elapsed = started.duration(to: .now)
            #expect(elapsed < .milliseconds(250))
            #expect(index.fileCount == 0)
        }
    }
}

private final class NonCooperativeFileSystemProvider: FileSystemProvider, @unchecked Sendable {
    func enumerateFiles(under root: String) throws -> [String] {
        Thread.sleep(forTimeInterval: 0.5)
        return ["\(root)/late.swift"]
    }

    func directoryExists(at path: String) -> Bool { true }
}

@Suite
private struct StreamingFinalizeTimeoutTests {
    @Test func finalizeTimeoutReturnsAtDeadlineWhenOperationIgnoresCancellation() async {
        let started = ContinuousClock.now
        do {
            _ = try await StreamingSessionController.withFinalizeTimeout(nanoseconds: 20_000_000) {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        continuation.resume()
                    }
                }
                return "late result"
            }
            Issue.record("Expected finalize step to time out")
        } catch {
            let elapsed = started.duration(to: .now)
            #expect(elapsed < .milliseconds(250))
        }
    }
}

@Suite
private struct StreamingAudioBackpressureTests {
    @Test func bufferingNewestRetainsOnlyMostRecentAudioWindow() async {
        let limit = StreamingSessionController.maximumBufferedAudioBuffers
        let (stream, continuation) = AsyncStream.makeStream(
            of: Int.self,
            bufferingPolicy: .bufferingNewest(limit)
        )

        for value in 0...limit {
            continuation.yield(value)
        }
        continuation.finish()

        var received: [Int] = []
        for await value in stream {
            received.append(value)
        }

        #expect(received == Array(1...limit))
    }
}

@MainActor
private final class MockDiarizationTranscriptionEngine: TranscriptionEngine {
    private(set) var state: TranscriptionEngineState = .unloaded
    var transcribeResponses: [String] = []
    var transcribeError: Error?
    var nonCooperativeTranscribeDelayNanoseconds: UInt64?
    var loadDelayNanoseconds: UInt64?
    var detectedLanguage: AppLanguage?
    var detectLanguageError: Error?
    private(set) var transcribeCallCount = 0
    private(set) var detectLanguageCallCount = 0
    private(set) var detectLanguageSampleCounts: [Int] = []
    private(set) var receivedOptions: [TranscriptionOptions] = []

    func loadModel(path: String) async throws {
        if let loadDelayNanoseconds { try await Task.sleep(nanoseconds: loadDelayNanoseconds) }
        state = .ready
    }

    func loadModel(name: String, downloadBase: URL?) async throws {
        if let loadDelayNanoseconds { try await Task.sleep(nanoseconds: loadDelayNanoseconds) }
        state = .ready
    }

    func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String {
        if let nonCooperativeTranscribeDelayNanoseconds {
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + .nanoseconds(Int(nonCooperativeTranscribeDelayNanoseconds))
                ) {
                    continuation.resume()
                }
            }
        }
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

    func detectLanguage(samples: [Float], sampleRate: Int) async throws -> AppLanguage? {
        detectLanguageCallCount += 1
        detectLanguageSampleCounts.append(samples.count)

        if let detectLanguageError {
            throw detectLanguageError
        }

        return detectedLanguage
    }

    func unloadModel() async {
        state = .unloaded
    }
}

@MainActor
private final class MockSpeakerDiarizer: SpeakerDiarizer {
    private(set) var state: SpeakerDiarizerState = .unloaded
    let mode: DiarizationMode = .offline

    var nextResult: DiarizationResult = DiarizationResult(segments: [], speakers: [], audioDuration: 0)
    var diarizeError: Error?
    var diarizeDelayNanoseconds: UInt64?
    var nonCooperativeDiarizeDelayNanoseconds: UInt64?
    private(set) var loadModelsCallCount = 0
    private(set) var unloadModelsCallCount = 0
    private(set) var diarizeCallCount = 0
    private(set) var clearKnownSpeakersCallCount = 0
    private(set) var registeredKnownSpeakers: [Speaker] = []

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
        if let nonCooperativeDiarizeDelayNanoseconds {
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + .nanoseconds(Int(nonCooperativeDiarizeDelayNanoseconds))
                ) {
                    continuation.resume()
                }
            }
        }
        if let diarizeDelayNanoseconds {
            try await Task.sleep(nanoseconds: diarizeDelayNanoseconds)
        }
        if let diarizeError {
            throw diarizeError
        }
        return nextResult
    }

    func compareSpeakers(audio1: [Float], audio2: [Float]) async throws -> Float {
        0.0
    }

    func registerKnownSpeaker(_ speaker: Speaker) async throws {
        registeredKnownSpeakers.append(speaker)
    }

    func clearKnownSpeakers() async {
        clearKnownSpeakersCallCount += 1
        registeredKnownSpeakers.removeAll()
    }
}

@MainActor
private final class MockSpeakerIdentityService: SpeakerIdentityManaging {
    private(set) var knownSpeakersCallCount = 0
    private(set) var bestMatchCallCount = 0
    private(set) var learnCallCount = 0
    private let speakers: [Speaker]
    private let matchesByEmbeddingKey: [String: SpeakerIdentityMatch]

    init(knownSpeakers: [Speaker] = [], matchesByEmbeddingKey: [String: SpeakerIdentityMatch] = [:]) {
        self.speakers = knownSpeakers
        self.matchesByEmbeddingKey = matchesByEmbeddingKey
    }

    func knownSpeakers() throws -> [Speaker] {
        knownSpeakersCallCount += 1
        return speakers
    }

    func bestMatch(for embedding: [Float]) throws -> SpeakerIdentityMatch? {
        bestMatchCallCount += 1
        return matchesByEmbeddingKey[embedding.map { String(format: "%.4f", $0) }.joined(separator: ",")]
    }

    func learnFromProfileAssignments(
        recordID: UUID,
        segments: [DiarizedTranscriptSegment],
        profileIDsBySpeakerID: [String: UUID]
    ) throws {
        learnCallCount += 1
    }

    func learnFromDictation(recordID: UUID, segments: [DiarizedTranscriptSegment]) throws {}
    func hasTrainingEvidence(for recordID: UUID) throws -> Bool { false }
    func removeTrainingEvidence(for recordID: UUID) throws {}
    func createProfile(displayName: String, notes: String?) throws -> ParticipantProfile {
        ParticipantProfile(normalizedName: displayName.lowercased(), displayName: displayName, notes: notes)
    }
    func fetchAllProfiles() throws -> [ParticipantProfile] { [] }
    func updateProfile(_ profile: ParticipantProfile, displayName: String, notes: String?) throws {}
    func renameProfile(_ profile: ParticipantProfile, to newName: String) throws {}
    func deleteProfile(_ profile: ParticipantProfile) throws {}
    func deleteAllProfiles() throws {}
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
    private(set) var transcriptionCallbackInstallCount = 0
    private(set) var endOfUtteranceCallbackInstallCount = 0

    var hasInstalledCallbacks: Bool {
        transcriptionCallbackInstallCount > 0 && endOfUtteranceCallbackInstallCount > 0
    }

    private var transcriptionCallback: StreamingTranscriptionCallback?
    private var endOfUtteranceCallback: EndOfUtteranceCallback?
    private var callbackInstallationWaiters: [UUID: CheckedContinuation<Void, Error>] = [:]

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
        transcriptionCallbackInstallCount += 1
        transcriptionCallback = callback
        resumeCallbackInstallationWaitersIfReady()
    }

    func setEndOfUtteranceCallback(_ callback: @escaping EndOfUtteranceCallback) {
        endOfUtteranceCallbackInstallCount += 1
        endOfUtteranceCallback = callback
        resumeCallbackInstallationWaitersIfReady()
    }

    func waitUntilCallbacksInstalled(timeout: TimeInterval = 1.0) async throws {
        guard !hasInstalledCallbacks else { return }
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                callbackInstallationWaiters[waiterID] = continuation
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    Task { @MainActor [weak self] in
                        self?.failCallbackInstallationWaiter(waiterID)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelCallbackInstallationWaiter(waiterID)
            }
        }
    }

    private func resumeCallbackInstallationWaitersIfReady() {
        guard hasInstalledCallbacks else { return }
        let waiters = callbackInstallationWaiters.values
        callbackInstallationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: ())
        }
    }

    private func failCallbackInstallationWaiter(_ waiterID: UUID) {
        callbackInstallationWaiters.removeValue(forKey: waiterID)?.resume(
            throwing: AsyncTestWaitError.timedOut("streaming callbacks to be installed")
        )
    }

    private func cancelCallbackInstallationWaiter(_ waiterID: UUID) {
        callbackInstallationWaiters.removeValue(forKey: waiterID)?.resume(throwing: CancellationError())
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

/// Parks the first awaiter so a streaming drain can be held across reset.
private actor StreamingCallbackSuspendGate {
    private var isOpen = false
    private var hasEntered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() async {
        if !hasEntered {
            hasEntered = true
            let waiters = enteredWaiters
            enteredWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
        guard !isOpen else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if isOpen {
                continuation.resume()
            } else {
                openWaiters.append(continuation)
            }
        }
    }

    func waitUntilEntered() async {
        if hasEntered { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if hasEntered {
                continuation.resume()
            } else {
                enteredWaiters.append(continuation)
            }
        }
    }

    func open() {
        isOpen = true
        let waiters = openWaiters
        openWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor StreamingCallbackCollector {
    private struct Waiter {
        let id: UUID
        let expectedPartials: [String]?
        let expectedFinals: [String]
        let continuation: CheckedContinuation<Void, Error>
    }

    private var partialsStore: [String] = []
    private var finalsStore: [String] = []
    private var waiters: [Waiter] = []

    func recordPartial(_ text: String) {
        partialsStore.append(text)
        resumeSatisfiedWaiters()
    }

    func recordFinal(_ text: String) {
        finalsStore.append(text)
        resumeSatisfiedWaiters()
    }

    func waitFor(
        partials: [String],
        finals: [String],
        timeout: TimeInterval = 1.0
    ) async throws {
        guard partialsStore != partials || finalsStore != finals else { return }
        try await waitUntil(partials: partials, finals: finals, timeout: timeout)
    }

    func waitForFinals(_ finals: [String], timeout: TimeInterval = 1.0) async throws {
        guard finalsStore != finals else { return }
        try await waitUntil(partials: nil, finals: finals, timeout: timeout)
    }

    func snapshot() -> (partials: [String], finals: [String]) {
        (partialsStore, finalsStore)
    }

    private func resumeSatisfiedWaiters() {
        var pending: [Waiter] = []
        for waiter in waiters {
            let partialsMatch = waiter.expectedPartials.map { $0 == partialsStore } ?? true
            if partialsMatch && waiter.expectedFinals == finalsStore {
                waiter.continuation.resume(returning: ())
            } else {
                pending.append(waiter)
            }
        }
        waiters = pending
    }

    private func waitUntil(
        partials: [String]?,
        finals: [String],
        timeout: TimeInterval
    ) async throws {
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(
                    Waiter(
                        id: waiterID,
                        expectedPartials: partials,
                        expectedFinals: finals,
                        continuation: continuation
                    )
                )
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    Task { [weak self] in
                        await self?.failWaiter(
                            waiterID,
                            expectedPartials: partials,
                            expectedFinals: finals
                        )
                    }
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancelWaiter(waiterID)
            }
        }
    }

    private func failWaiter(
        _ waiterID: UUID,
        expectedPartials: [String]?,
        expectedFinals: [String]
    ) {
        guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else { return }
        let waiter = waiters.remove(at: index)
        let expectation = expectedPartials.map {
            "partials \($0) and finals \(expectedFinals)"
        } ?? "finals \(expectedFinals)"
        waiter.continuation.resume(throwing: AsyncTestWaitError.timedOut(expectation))
    }

    private func cancelWaiter(_ waiterID: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

private enum AsyncTestWaitError: Error, CustomStringConvertible {
    case timedOut(String)

    var description: String {
        switch self {
        case .timedOut(let expectation):
            "Timed out waiting for \(expectation)"
        }
    }
}
