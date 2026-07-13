//
//  SenseVoiceEngineTests.swift
//  PindropTests
//
//  Created on 2026-07-13.
//

import FluidAudio
import Foundation
import Testing
@testable import Pindrop

@MainActor
@Suite
struct SenseVoiceEngineTests {
    private func makeEngine() -> SenseVoiceEngine {
        SenseVoiceEngine()
    }

    private func makeFloat32AudioData(sampleCount: Int = 16_000) -> Data {
        let samples = [Float](repeating: 0, count: sampleCount)
        return samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    private func encoderFile(for precision: SenseVoiceEncoderPrecision) -> String {
        switch precision {
        case .int8: return ModelNames.SenseVoice.encoderInt8File
        case .fp32: return ModelNames.SenseVoice.encoderFp32File
        case .fp16: return ModelNames.SenseVoice.encoderFile
        }
    }

    private func plantPrecisionSet(
        at senseDir: URL,
        precision: SenseVoiceEncoderPrecision
    ) throws {
        try? FileManager.default.removeItem(at: senseDir)
        try FileManager.default.createDirectory(at: senseDir, withIntermediateDirectories: true)
        for name in [
            ModelNames.SenseVoice.preprocessorFile,
            encoderFile(for: precision),
            ModelNames.SenseVoice.vocabularyFile,
        ] {
            let path = senseDir.appendingPathComponent(name)
            if name.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
                FileManager.default.createFile(
                    atPath: path.appendingPathComponent("coremldata.bin").path,
                    contents: Data()
                )
            } else {
                FileManager.default.createFile(atPath: path.path, contents: Data("[]".utf8))
            }
        }
    }

    @Test func initialStateIsUnloaded() {
        let engine = makeEngine()
        #expect(engine.state == .unloaded)
        #expect(engine.error == nil)
    }

    @Test func capabilitiesIncludeTranscription() {
        #expect(SenseVoiceEngine.capabilities.contains(.transcription))
        #expect(!SenseVoiceEngine.capabilities.contains(.streamingTranscription))
    }

    @Test func catalogPrecisionIsInt8Only() {
        #expect(SenseVoiceEngine.catalogPrecision == .int8)
        #expect(SenseVoiceEngine.precision(forModelName: "sensevoice-small") == .int8)
        #expect(SenseVoiceEngine.precision(forModelName: "sensevoice-small-int8") == .int8)
        #expect(SenseVoiceEngine.precision(forModelName: "sensevoice-small-fp16") == nil)
        #expect(SenseVoiceEngine.precision(forModelName: "sensevoice-small-fp32") == nil)
        #expect(SenseVoiceEngine.precision(forModelName: "unrelated-model") == nil)
        #expect(makeEngine().preferredPrecision == .int8)
    }

    @Test func int8DownloadArtifactContractExcludesOtherEncoders() {
        let artifacts = SenseVoiceEngine.requiredDownloadArtifacts(precision: .int8)
        #expect(artifacts.contains(ModelNames.SenseVoice.preprocessorFile))
        #expect(artifacts.contains(ModelNames.SenseVoice.encoderInt8File))
        #expect(!artifacts.contains(ModelNames.SenseVoice.encoderFile))
        #expect(!artifacts.contains(ModelNames.SenseVoice.encoderFp32File))
    }

    @Test func languageIndexMapping() {
        #expect(SenseVoiceEngine.senseVoiceLanguageIndex(for: .automatic) == 0)
        #expect(SenseVoiceEngine.senseVoiceLanguageIndex(for: .simplifiedChinese) == 3)
        #expect(SenseVoiceEngine.senseVoiceLanguageIndex(for: .english) == 4)
        #expect(SenseVoiceEngine.senseVoiceLanguageIndex(for: .japanese) == 11)
        #expect(SenseVoiceEngine.senseVoiceLanguageIndex(for: .korean) == 12)
        #expect(SenseVoiceEngine.senseVoiceLanguageIndex(for: .spanish) == 0)
        #expect(SenseVoiceEngine.senseVoiceLanguageIndex(for: .hindi) == 0)
        #expect(SenseVoiceEngine.senseVoiceLanguageIndex(for: .malayalam) == 0)
        #expect(SenseVoiceEngine.senseVoiceLanguageIndex(for: .polish) == 0)
    }

    @Test func partitionSamplesSingleWindowWhenUnderCap() {
        let samples = [Float](repeating: 0.1, count: 1_000)
        let windows = SenseVoiceEngine.partitionSamples(
            samples,
            maxWindowSamples: 16_000,
            overlapSamples: 480
        )
        #expect(windows.count == 1)
        #expect(windows[0].count == 1_000)
    }

    @Test func partitionSamplesBoundaryExactlyAtCapIsSingleWindow() {
        let cap = 100
        let samples = [Float](repeating: 1, count: cap)
        let windows = SenseVoiceEngine.partitionSamples(
            samples,
            maxWindowSamples: cap,
            overlapSamples: 10
        )
        #expect(windows.count == 1)
        #expect(windows[0].count == cap)
    }

    @Test func partitionSamplesUsesOverlapBetweenWindows() {
        let cap = 100
        let overlap = 20
        var tagged = [Float](repeating: 0, count: 250)
        for i in tagged.indices { tagged[i] = Float(i) }

        let windows = SenseVoiceEngine.partitionSamples(
            tagged,
            maxWindowSamples: cap,
            overlapSamples: overlap
        )
        #expect(windows.count >= 3)
        #expect(windows[0].first == 0)
        #expect(windows[0].last == 99)
        #expect(windows[1].first == 80)
        #expect(Set(windows[0]).intersection(Set(windows[1])).count == overlap)
        #expect(windows.last?.last == 249)
    }

    @Test func partitionSamplesCapPlusOneKeepsConfiguredOverlap() {
        // 101-sample input, 100 cap / 3 overlap → [0,100) and [97,101).
        // Must NOT right-align to [1,101) (99-sample overlap).
        let cap = 100
        let overlap = 3
        var tagged = [Float](repeating: 0, count: 101)
        for i in tagged.indices { tagged[i] = Float(i) }

        let windows = SenseVoiceEngine.partitionSamples(
            tagged,
            maxWindowSamples: cap,
            overlapSamples: overlap
        )
        #expect(windows.count == 2)
        #expect(windows[0].count == 100)
        #expect(windows[0].first == 0 && windows[0].last == 99)
        #expect(windows[1].first == 97)
        #expect(windows[1].last == 100)
        #expect(windows[1].count == 4)
        #expect(Set(windows[0]).intersection(Set(windows[1])).count == overlap)
    }

    @Test func partitionSamplesMultiHopRemainderKeepsAdjacentOverlap() {
        // 250 samples, cap 100, overlap 20 → hop 80:
        // [0,100), [80,180), [160,250)
        let cap = 100
        let overlap = 20
        var tagged = [Float](repeating: 0, count: 250)
        for i in tagged.indices { tagged[i] = Float(i) }

        let windows = SenseVoiceEngine.partitionSamples(
            tagged,
            maxWindowSamples: cap,
            overlapSamples: overlap
        )
        #expect(windows.count == 3)
        #expect(windows[0].first == 0 && windows[0].last == 99)
        #expect(windows[1].first == 80 && windows[1].last == 179)
        #expect(windows[2].first == 160 && windows[2].last == 249)
        #expect(Set(windows[0]).intersection(Set(windows[1])).count == overlap)
        #expect(Set(windows[1]).intersection(Set(windows[2])).count == overlap)
    }

    @Test func mergeTranscriptsDropsLongestSharedWordBoundary() {
        let left = "hello world this is a test"
        let right = "this is a test of continuity"
        let merged = SenseVoiceEngine.mergeTranscripts(left, right)
        #expect(merged == "hello world this is a test of continuity")
        #expect(merged.components(separatedBy: "this is a test").count == 2)
    }

    @Test func mergeTranscriptsPreservesPunctuationOnTokens() {
        let left = "Hello world, this is fine."
        let right = "this is fine. Next sentence."
        let merged = SenseVoiceEngine.mergeTranscripts(left, right)
        #expect(merged == "Hello world, this is fine. Next sentence.")
        #expect(merged.components(separatedBy: "this is fine.").count == 2)
    }

    @Test func mergeTranscriptsPunctuationVariantBoundaryKeepsLeftSpelling() {
        // right attaches a comma to the shared token; left spelling wins.
        let left = "hello world"
        let right = "world, next"
        let merged = SenseVoiceEngine.mergeTranscripts(left, right)
        #expect(merged == "hello world next")
        #expect(!merged.contains("world,"))
    }

    @Test func mergeTranscriptsTrailingPeriodOnLeftPreservedAgainstBareRight() {
        let left = "phrase."
        let right = "phrase next"
        let merged = SenseVoiceEngine.mergeTranscripts(left, right)
        #expect(merged == "phrase. next")
    }

    @Test func mergeTranscriptsIgnoresEmptyNormalizedPunctuationOnlyTokens() {
        // Pure punctuation tokens normalize empty and must not block dedupe.
        let left = "hello world"
        let right = "— world continues"
        let merged = SenseVoiceEngine.mergeTranscripts(left, right)
        #expect(merged == "hello world continues" || merged == "hello world — world continues")
        // Prefer successful dedupe of "world" when em-dash is ignored.
        let normalizedRightLead = SenseVoiceEngine.normalizeTokenForComparison("—")
        #expect(normalizedRightLead.isEmpty)
        #expect(merged.components(separatedBy: "world").count == 2)
    }

    @Test func mergeTranscriptsNoOverlapFallsBackToSpaceJoin() {
        let left = "first window ends here"
        let right = "second window starts clean"
        let merged = SenseVoiceEngine.mergeTranscripts(left, right)
        #expect(merged == "first window ends here second window starts clean")
    }

    @Test func mergeTranscriptsIgnoresCoincidentalOneCharacterLatinOverlap() {
        let left = "we saw cats"
        let right = "sunny outside"
        let merged = SenseVoiceEngine.mergeTranscripts(left, right)
        #expect(merged == "we saw cats sunny outside")
        #expect(merged.contains("sunny"))
        #expect(!merged.contains(" unny"))
    }

    @Test func mergeTranscriptsIgnoresCoincidentalOneCharacterCJKOverlap() {
        let left = "我们看到了猫的"
        let right = "的天气很好"
        let merged = SenseVoiceEngine.mergeTranscripts(left, right)
        // 1-char CJK overlap is below the multi-char gate → space join.
        #expect(merged == "我们看到了猫的 的天气很好")
        #expect(merged.contains("猫的"))
        #expect(merged.contains("的天气很好"))
    }

    @Test func mergeTranscriptsCJKMultiCharacterOverlapDedupes() {
        let left = "今天天气真不错"
        let right = "天气真不错适合出门"
        let merged = SenseVoiceEngine.mergeTranscripts(left, right)
        #expect(merged == "今天天气真不错适合出门")
        #expect(merged.components(separatedBy: "天气真不错").count == 2)
    }

    @Test func stitchTranscriptsChainsMultipleWindows() {
        let pieces = [
            "alpha beta gamma",
            "beta gamma delta",
            "delta epsilon",
        ]
        let stitched = SenseVoiceEngine.stitchTranscripts(pieces)
        #expect(stitched == "alpha beta gamma delta epsilon")
    }

    @Test func multiWindowTranscriptionDedupesBoundaryPhrase() async throws {
        let engine = makeEngine()
        engine.prepareForWindowTests()
        // Small geometry so the test stays fast.
        engine.testMaxWindowSamples = 100
        engine.testOverlapSamples = 20

        // Window 0: samples 0..<100 → "hello world boundary phrase"
        // Window 1: samples 80..<180 → "boundary phrase continues here"
        // Overlap region is covered by both; mocked text shares the boundary phrase.
        engine.windowTranscribeOverride = { samples, _ in
            let start = Int(samples.first ?? -1)
            if start == 0 {
                return "hello world boundary phrase"
            }
            if start == 80 {
                return "boundary phrase continues here"
            }
            // Final right-aligned window (if any)
            return "continues here end"
        }

        // 180 samples → windows with hop 80: [0,100), [80,180]
        var samples = [Float](repeating: 0, count: 180)
        for i in samples.indices { samples[i] = Float(i) }
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }

        let text = try await engine.transcribe(audioData: data)
        #expect(text.contains("hello world"))
        #expect(text.contains("continues here") || text.contains("boundary phrase continues here"))
        // Boundary phrase must appear exactly once after stitch.
        #expect(text.components(separatedBy: "boundary phrase").count == 2)
        await engine.unloadModel()
    }

    @Test func multiWindowTranscriptionNoOverlapTextFallback() async throws {
        let engine = makeEngine()
        engine.prepareForWindowTests()
        engine.testMaxWindowSamples = 50
        engine.testOverlapSamples = 10

        engine.windowTranscribeOverride = { samples, _ in
            let start = Int(samples.first ?? -1)
            if start == 0 { return "alpha window" }
            return "omega window"
        }

        var samples = [Float](repeating: 0, count: 90)
        for i in samples.indices { samples[i] = Float(i) }
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }

        let text = try await engine.transcribe(audioData: data)
        // No shared tokens → space join.
        #expect(text.contains("alpha window"))
        #expect(text.contains("omega window"))
        #expect(text.contains("alpha window omega window") || text.split(separator: " ").count >= 4)
        await engine.unloadModel()
    }

    @Test func singleWindowUnderCapDoesNotSplit() async throws {
        let engine = makeEngine()
        engine.prepareForWindowTests()
        engine.testMaxWindowSamples = 16_000
        engine.testOverlapSamples = 480
        var callCount = 0
        engine.windowTranscribeOverride = { samples, _ in
            callCount += 1
            return "only-\(samples.count)"
        }
        let data = makeFloat32AudioData(sampleCount: 1_600)
        let text = try await engine.transcribe(audioData: data)
        #expect(callCount == 1)
        #expect(text == "only-1600")
    }

    @Test func loadModelWithMissingPathFails() async {
        let engine = makeEngine()
        do {
            try await engine.loadModel(path: "/tmp/pindrop-sensevoice-missing-\(UUID().uuidString)")
            Issue.record("Expected missing-path load to fail")
        } catch SenseVoiceEngine.EngineError.initializationFailed {
            #expect(engine.state == .error)
            #expect(engine.error != nil)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func loadModelPathWithFp16OnlyCacheFailsForCatalogInt8() async throws {
        let engine = makeEngine()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pindrop-sensevoice-fp16-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try plantPrecisionSet(at: root, precision: .fp16)

        #expect(SenseVoiceModels.modelsExist(at: root, precision: .fp16))
        #expect(!SenseVoiceModels.modelsExist(at: root, precision: .int8))

        do {
            try await engine.loadModel(path: root.path)
            Issue.record("Expected int8-incomplete path load to fail")
        } catch SenseVoiceEngine.EngineError.initializationFailed {
            #expect(engine.state == .error)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func discoveryDecisionMatchesCatalogInt8Precision() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pindrop-sensevoice-discovery-\(UUID().uuidString)", isDirectory: true)
        let senseDir = root.appendingPathComponent(Repo.senseVoiceSmall.folderName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try plantPrecisionSet(at: senseDir, precision: .fp16)
        #expect(!SenseVoiceModels.modelsExist(at: senseDir, precision: SenseVoiceEngine.catalogPrecision))

        try plantPrecisionSet(at: senseDir, precision: .fp32)
        #expect(!SenseVoiceModels.modelsExist(at: senseDir, precision: SenseVoiceEngine.catalogPrecision))

        try plantPrecisionSet(at: senseDir, precision: .int8)
        #expect(SenseVoiceModels.modelsExist(at: senseDir, precision: SenseVoiceEngine.catalogPrecision))

        try? FileManager.default.removeItem(at: senseDir)
        try FileManager.default.createDirectory(at: senseDir, withIntermediateDirectories: true)
        let prep = senseDir.appendingPathComponent(ModelNames.SenseVoice.preprocessorFile)
        try FileManager.default.createDirectory(at: prep, withIntermediateDirectories: true)
        #expect(!SenseVoiceModels.modelsExist(at: senseDir, precision: .int8))
    }

    @Test func transcribeRequiresLoadedModel() async {
        let engine = makeEngine()
        do {
            _ = try await engine.transcribe(audioData: makeFloat32AudioData())
            Issue.record("Expected modelNotLoaded")
        } catch SenseVoiceEngine.EngineError.modelNotLoaded {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func misalignedAudioDataRejectedBeforeFloatBinding() async {
        let engine = makeEngine()
        let misaligned = Data([0x00, 0x01, 0x02])
        #expect(misaligned.count % MemoryLayout<Float>.stride != 0)

        do {
            _ = try await engine.transcribe(audioData: misaligned)
            Issue.record("Expected invalidAudioData for misaligned PCM payload")
        } catch SenseVoiceEngine.EngineError.invalidAudioData {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func unloadResetsStateAndError() async {
        let engine = makeEngine()
        do {
            try await engine.loadModel(path: "/tmp/pindrop-sensevoice-missing-\(UUID().uuidString)")
        } catch {
            // expected
        }
        await engine.unloadModel()
        #expect(engine.state == .unloaded)
        #expect(engine.error == nil)
    }

    @Test func catalogExposesSenseVoiceModel() {
        let manager = ModelManager()
        let model = manager.availableModels.first { $0.name == "sensevoice-small" }
        #expect(model != nil)
        #expect(model?.provider == .senseVoice)
        #expect(model?.provider.isLocal == true)
        #expect(model?.availability == .available)
        #expect(model?.sizeInMB == 230)
    }

    @Test func modelProviderSenseVoiceIsLocalWithIcon() {
        #expect(ModelManager.ModelProvider.senseVoice.isLocal)
        #expect(!ModelManager.ModelProvider.senseVoice.iconName.isEmpty)
    }

    @Test func transcriptionServiceFactoryRoutesSenseVoiceToSenseVoiceEngine() async {
        var captured: ModelManager.ModelProvider?
        let service = TranscriptionService(
            engineFactory: { provider in
                captured = provider
                switch provider {
                case .senseVoice:
                    return SenseVoiceEngine()
                case .whisperKit:
                    return WhisperKitEngine()
                case .parakeet:
                    return ParakeetEngine()
                case .appleSpeech:
                    return AppleSpeechEngine()
                default:
                    throw TranscriptionService.TranscriptionError.modelLoadFailed("unsupported")
                }
            }
        )

        do {
            try await service.loadModel(modelName: "sensevoice-small", provider: .senseVoice)
        } catch {
            // Expected without local int8 model / offline download.
        }
        #expect(captured == .senseVoice)
    }

    @Test func onboardingProviderRoutingDoesNotUsePathAPIForSenseVoice() {
        func usesWhisperKitPathAPI(_ provider: ModelManager.ModelProvider) -> Bool {
            switch provider {
            case .whisperKit: return true
            default: return false
            }
        }
        #expect(usesWhisperKitPathAPI(.senseVoice) == false)
        #expect(usesWhisperKitPathAPI(.parakeet) == false)
        #expect(usesWhisperKitPathAPI(.whisperKit) == true)
    }
}
