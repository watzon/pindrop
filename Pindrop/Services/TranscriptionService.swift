//
//  TranscriptionService.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import AVFoundation
import Foundation
import os.log

@MainActor
@Observable
class TranscriptionService {

    enum State: Equatable {
        case unloaded
        case loading
        case ready
        case transcribing
        case error
    }

    enum TranscriptionError: Error, LocalizedError {
        case modelNotLoaded
        case invalidAudioData
        case transcriptionFailed(String)
        case modelLoadFailed(String)
        case engineSwitchDuringTranscription
        case streamingModelNotAvailable(String)
        case streamingNotReady
        case streamingStartFailed(String)
        case streamingProcessingFailed(String)
        case streamingStopFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Model not loaded. Call loadModel() first."
            case .invalidAudioData:
                return "Invalid audio data. Expected 16kHz mono PCM format."
            case .transcriptionFailed(let message):
                return "Transcription failed: \(message)"
            case .modelLoadFailed(let message):
                return "Model load failed: \(message)"
            case .engineSwitchDuringTranscription:
                return "Cannot switch engines during active transcription"
            case .streamingModelNotAvailable(let path):
                return "Streaming model not available at path: \(path)"
            case .streamingNotReady:
                return "Streaming engine not ready. Call prepareStreamingEngine() first."
            case .streamingStartFailed(let message):
                return "Failed to start streaming transcription: \(message)"
            case .streamingProcessingFailed(let message):
                return "Failed to process streaming audio: \(message)"
            case .streamingStopFailed(let message):
                return "Failed to stop streaming transcription: \(message)"
            }
        }
    }

    private static let sampleRate = 16_000
    private static let diarizationMergeGapSeconds: TimeInterval = 0.30
    private static let minimumSegmentDurationSeconds: TimeInterval = 1.0
    private static let maximumTranscriptChunkDurationSeconds: TimeInterval = 12.0
    private static let maximumTranscriptChunkWordCount = 28
    private static let targetTranscriptChunkWordCount = 20

    private(set) var state: State = .unloaded
    private(set) var error: Error?
    private var engine: (any TranscriptionEngine)?
    private var speakerDiarizer: (any SpeakerDiarizer)?
    private var streamingEngine: (any StreamingTranscriptionEngine)?
    private var currentProvider: ModelManager.ModelProvider?
    private var streamingPartialCallback: (@Sendable (String) -> Void)?
    private var streamingFinalUtteranceCallback: (@Sendable (String) -> Void)?

    private let engineFactory: @MainActor (ModelManager.ModelProvider) throws -> any TranscriptionEngine
    private let speakerDiarizerFactory: @MainActor () -> any SpeakerDiarizer
    private let streamingEngineFactory: @MainActor () -> any StreamingTranscriptionEngine

    init(
        engineFactory: @escaping @MainActor (ModelManager.ModelProvider) throws -> any TranscriptionEngine = {
            try TranscriptionService.defaultEngineFactory(provider: $0)
        },
        diarizerFactory: @escaping @MainActor () -> any SpeakerDiarizer = {
            FluidSpeakerDiarizer()
        },
        streamingEngineFactory: @escaping @MainActor () -> any StreamingTranscriptionEngine = {
            ParakeetStreamingEngine()
        }
    ) {
        self.engineFactory = engineFactory
        self.speakerDiarizerFactory = diarizerFactory
        self.streamingEngineFactory = streamingEngineFactory
    }

    func loadModel(modelName: String = "tiny", provider: ModelManager.ModelProvider = .whisperKit) async throws {
        if state == .transcribing {
            throw TranscriptionError.engineSwitchDuringTranscription
        }

        if currentProvider != nil && currentProvider != provider {
            await unloadModel()
        }

        state = .loading
        error = nil

        Log.transcription.info("Loading model: \(modelName) with provider: \(provider.rawValue)...")

        do {
            let newEngine = try engineFactory(provider)

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await newEngine.loadModel(name: modelName, downloadBase: self.getDownloadBase())
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(120))
                    throw TranscriptionError.modelLoadFailed("Model loading timed out after 120s. This can happen on first launch after an update. Try restarting the app, or delete and re-download the model from Settings.")
                }

                try await group.next()
                group.cancelAll()
            }

            engine = newEngine
            currentProvider = provider
            Log.transcription.info("Model loaded successfully with \(provider.rawValue) engine")
            state = .ready
        } catch let error as TranscriptionError {
            Log.transcription.error("Model load failed: \(error)")
            self.error = error
            state = .error
            throw error
        } catch {
            Log.transcription.error("Model load failed: \(error)")
            let loadError = TranscriptionError.modelLoadFailed(error.localizedDescription)
            self.error = loadError
            state = .error
            throw loadError
        }
    }

    func loadModel(modelPath: String) async throws {
        if state == .transcribing {
            throw TranscriptionError.engineSwitchDuringTranscription
        }

        if currentProvider != nil {
            await unloadModel()
        }

        state = .loading
        error = nil

        Log.transcription.info("Loading model from path: \(modelPath) with prewarm enabled...")

        do {
            let newEngine = WhisperKitEngine()

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await newEngine.loadModel(path: modelPath)
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(120))
                    throw TranscriptionError.modelLoadFailed("Model loading timed out after 120s. This can happen on first launch after an update. Try restarting the app, or delete and re-download the model from Settings.")
                }

                try await group.next()
                group.cancelAll()
            }

            engine = newEngine
            currentProvider = .whisperKit
            Log.transcription.info("Model loaded and prewarmed successfully")
            state = .ready
        } catch let error as TranscriptionError {
            Log.transcription.error("Model load failed: \(error)")
            self.error = error
            state = .error
            throw error
        } catch {
            Log.transcription.error("Model load failed: \(error)")
            let loadError = TranscriptionError.modelLoadFailed(error.localizedDescription)
            self.error = loadError
            state = .error
            throw loadError
        }
    }

    func transcribe(audioData: Data) async throws -> String {
        try await transcribe(audioData: audioData, diarizationEnabled: false).text
    }

    func transcribe(audioData: Data, diarizationEnabled: Bool) async throws -> TranscriptionOutput {
        Log.transcription.debug("Transcribe called with \(audioData.count) bytes, state: \(String(describing: self.state))")

        guard let engine else {
            throw TranscriptionError.modelNotLoaded
        }

        guard !audioData.isEmpty else {
            throw TranscriptionError.invalidAudioData
        }

        guard state != .transcribing else {
            throw TranscriptionError.transcriptionFailed("Transcription already in progress")
        }

        state = .transcribing

        do {
            let floatCount = audioData.count / MemoryLayout<Float>.size
            let duration = Double(floatCount) / Double(Self.sampleRate)
            let providerName = currentProvider?.rawValue ?? "unknown"
            Log.transcription.info("Transcribing \(floatCount) samples (\(String(format: "%.2f", duration))s) using \(providerName)")

            let startTime = Date()
            let samples = dataToFloatArray(audioData)

            let output = try await transcribeWithOptionalDiarization(
                engine: engine,
                audioData: audioData,
                samples: samples,
                sampleRate: Self.sampleRate,
                diarizationEnabled: diarizationEnabled
            )

            let elapsed = Date().timeIntervalSince(startTime)
            Log.transcription.info("Transcription completed in \(String(format: "%.2f", elapsed))s")

            state = .ready
            Log.transcription.debug("Result redacted (chars=\(output.text.count), diarizedSegments=\(output.diarizedSegments?.count ?? 0))")
            return output
        } catch let error as TranscriptionError {
            state = .ready
            throw error
        } catch {
            state = .ready
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    func unloadModel() async {
        await engine?.unloadModel()
        await speakerDiarizer?.unloadModels()
        await streamingEngine?.unloadModel()
        engine = nil
        speakerDiarizer = nil
        streamingEngine = nil
        currentProvider = nil
        state = .unloaded
        error = nil
    }

    func setStreamingCallbacks(
        onPartial: (@Sendable (String) -> Void)? = nil,
        onFinalUtterance: (@Sendable (String) -> Void)? = nil
    ) {
        streamingPartialCallback = onPartial
        streamingFinalUtteranceCallback = onFinalUtterance
        applyStreamingCallbacks()
    }

    func prepareStreamingEngine() async throws {
        if streamingEngine == nil {
            streamingEngine = streamingEngineFactory()
            applyStreamingCallbacks()
        }

        guard let streamingEngine else {
            throw TranscriptionError.streamingNotReady
        }

        switch streamingEngine.state {
        case .ready, .streaming, .paused:
            if state == .unloaded || state == .error {
                state = .ready
            }
            return
        case .loading:
            return
        case .unloaded, .error:
            break
        }

        let modelPath = FeatureModelType.streaming.repoFolderName
        do {
            try await streamingEngine.loadModel(name: modelPath)
            if state == .unloaded || state == .error {
                state = .ready
            }
        } catch {
            let path = getStreamingModelBase()
                .appendingPathComponent(modelPath, isDirectory: true)
                .path
            let streamingError = TranscriptionError.streamingModelNotAvailable(path)
            self.error = streamingError
            state = .error
            throw streamingError
        }
    }

    func startStreaming() async throws {
        guard state != .transcribing else {
            throw TranscriptionError.transcriptionFailed("Transcription already in progress")
        }

        do {
            try await prepareStreamingEngine()
            guard let streamingEngine else {
                throw TranscriptionError.streamingNotReady
            }
            try await streamingEngine.startStreaming()
            state = .transcribing
            error = nil
        } catch let error as TranscriptionError {
            self.error = error
            throw error
        } catch {
            let streamingError = TranscriptionError.streamingStartFailed(error.localizedDescription)
            self.error = streamingError
            throw streamingError
        }
    }

    func processStreamingAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {
        guard state == .transcribing else {
            throw TranscriptionError.streamingNotReady
        }

        guard let streamingEngine else {
            throw TranscriptionError.streamingNotReady
        }

        do {
            try await streamingEngine.processAudioBuffer(buffer)
        } catch let error as TranscriptionError {
            throw error
        } catch {
            let streamingError = TranscriptionError.streamingProcessingFailed(error.localizedDescription)
            self.error = streamingError
            throw streamingError
        }
    }

    func stopStreaming() async throws -> String {
        guard let streamingEngine else {
            throw TranscriptionError.streamingNotReady
        }

        do {
            let finalText = try await streamingEngine.stopStreaming()
            state = .ready
            return finalText
        } catch let error as TranscriptionError {
            state = .ready
            throw error
        } catch {
            let streamingError = TranscriptionError.streamingStopFailed(error.localizedDescription)
            self.error = streamingError
            state = .ready
            throw streamingError
        }
    }

    func cancelStreaming() async {
        await streamingEngine?.reset()
        if engine != nil || streamingEngine != nil {
            state = .ready
        } else {
            state = .unloaded
        }
    }

    private func transcribeWithOptionalDiarization(
        engine: any TranscriptionEngine,
        audioData: Data,
        samples: [Float],
        sampleRate: Int,
        diarizationEnabled: Bool
    ) async throws -> TranscriptionOutput {
        guard diarizationEnabled else {
            return try await transcribeWithoutDiarization(engine: engine, audioData: audioData)
        }

        Log.transcription.info("Speaker diarization enabled for current transcription")

        do {
            let diarizer = getOrCreateSpeakerDiarizer()
            try await diarizer.loadModels()
            let diarizationResult = try await diarizer.diarize(samples: samples, sampleRate: sampleRate)
            let normalizedSegments = normalizedDiarizationSegments(
                diarizationResult.segments,
                audioDuration: diarizationResult.audioDuration
            )

            guard !normalizedSegments.isEmpty else {
                Log.transcription.warning("Speaker diarization returned no usable segments. Falling back to plain transcript.")
                return try await transcribeWithoutDiarization(engine: engine, audioData: audioData)
            }

            let output = try await transcribeBySpeakerSegments(
                engine: engine,
                samples: samples,
                sampleRate: sampleRate,
                segments: normalizedSegments
            )

            if let diarizedSegments = output.diarizedSegments, !diarizedSegments.isEmpty {
                Log.transcription.info("Speaker diarization succeeded with \(diarizedSegments.count) segments")
                return output
            }

            Log.transcription.warning("Speaker diarization produced no transcript text. Falling back to plain transcript.")
            return try await transcribeWithoutDiarization(engine: engine, audioData: audioData)
        } catch {
            Log.transcription.warning("Speaker diarization unavailable, falling back to plain transcript: \(error.localizedDescription)")
            return try await transcribeWithoutDiarization(engine: engine, audioData: audioData)
        }
    }

    private func transcribeWithoutDiarization(
        engine: any TranscriptionEngine,
        audioData: Data
    ) async throws -> TranscriptionOutput {
        let text = try await engine.transcribe(audioData: audioData)
        return TranscriptionOutput(text: text, diarizedSegments: nil)
    }

    private func transcribeBySpeakerSegments(
        engine: any TranscriptionEngine,
        samples: [Float],
        sampleRate: Int,
        segments: [SpeakerSegment]
    ) async throws -> TranscriptionOutput {
        var speakerLabelsByID: [String: String] = [:]
        var transcriptSegments: [DiarizedTranscriptSegment] = []
        var textLines: [String] = []

        for segment in segments {
            guard let segmentData = extractAudioData(
                samples: samples,
                sampleRate: sampleRate,
                startTime: segment.startTime,
                endTime: segment.endTime
            ) else {
                continue
            }

            let segmentText = try await engine.transcribe(audioData: segmentData)
            let trimmed = segmentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let speakerID = segment.speaker.id
            let speakerLabel: String
            if let existing = speakerLabelsByID[speakerID] {
                speakerLabel = existing
            } else {
                speakerLabel = "Speaker \(speakerLabelsByID.count + 1)"
                speakerLabelsByID[speakerID] = speakerLabel
            }

            let diarizedSegment = DiarizedTranscriptSegment(
                speakerId: speakerID,
                speakerLabel: speakerLabel,
                startTime: segment.startTime,
                endTime: segment.endTime,
                confidence: segment.confidence,
                text: trimmed
            )

            let splitSegments = splitTranscriptSegmentIfNeeded(diarizedSegment)
            transcriptSegments.append(contentsOf: splitSegments)
            textLines.append(contentsOf: splitSegments.map { "\(speakerLabel): \($0.text)" })
        }

        let mergedText: String
        if speakerLabelsByID.count <= 1 {
            if !transcriptSegments.isEmpty {
                Log.transcription.info("Speaker diarization detected a single speaker; omitting labels from transcript output")
            }
            mergedText = transcriptSegments
                .map(\.text)
                .joined(separator: " ")
        } else {
            mergedText = textLines.joined(separator: "\n")
        }

        return TranscriptionOutput(
            text: mergedText,
            diarizedSegments: transcriptSegments.isEmpty ? nil : transcriptSegments
        )
    }

    private func splitTranscriptSegmentIfNeeded(
        _ segment: DiarizedTranscriptSegment
    ) -> [DiarizedTranscriptSegment] {
        let duration = max(segment.endTime - segment.startTime, 0)
        let totalWords = wordCount(in: segment.text)

        guard duration > Self.maximumTranscriptChunkDurationSeconds ||
                totalWords > Self.maximumTranscriptChunkWordCount else {
            return [segment]
        }

        let textualUnits = transcriptTextUnits(from: segment.text)
        guard textualUnits.count > 1 || totalWords > Self.maximumTranscriptChunkWordCount else {
            return [segment]
        }

        let chunkTexts = packedTranscriptChunks(from: textualUnits)
        guard chunkTexts.count > 1 else {
            return [segment]
        }

        let weightedChunkWordCounts = chunkTexts.map { max(1, wordCount(in: $0)) }
        let totalWeightedWords = max(1, weightedChunkWordCounts.reduce(0, +))

        var splitSegments: [DiarizedTranscriptSegment] = []
        splitSegments.reserveCapacity(chunkTexts.count)

        var chunkStart = segment.startTime

        for (index, chunkText) in chunkTexts.enumerated() {
            let chunkEnd: TimeInterval
            if index == chunkTexts.count - 1 {
                chunkEnd = segment.endTime
            } else {
                let proportionalDuration = duration * (Double(weightedChunkWordCounts[index]) / Double(totalWeightedWords))
                chunkEnd = min(segment.endTime, max(chunkStart, chunkStart + proportionalDuration))
            }

            splitSegments.append(
                DiarizedTranscriptSegment(
                    speakerId: segment.speakerId,
                    speakerLabel: segment.speakerLabel,
                    startTime: chunkStart,
                    endTime: chunkEnd,
                    confidence: segment.confidence,
                    text: chunkText
                )
            )
            chunkStart = chunkEnd
        }

        return splitSegments
    }

    private func transcriptTextUnits(from text: String) -> [String] {
        let sentenceUnits = sentenceUnits(from: text)
        let baseUnits = sentenceUnits.isEmpty ? [text] : sentenceUnits

        return baseUnits.flatMap { sentence in
            let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSentence.isEmpty else { return [String]() }

            if wordCount(in: trimmedSentence) <= Self.maximumTranscriptChunkWordCount {
                return [trimmedSentence]
            }

            return splitTextByWordCount(trimmedSentence, maximumWords: Self.targetTranscriptChunkWordCount)
        }
    }

    private func sentenceUnits(from text: String) -> [String] {
        let nsText = text as NSString
        var units: [String] = []

        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: nsText.length),
            options: [.bySentences, .substringNotRequired]
        ) { _, range, _, _ in
            guard range.location != NSNotFound else { return }
            let sentence = nsText.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else { return }
            units.append(sentence)
        }

        return units
    }

    private func packedTranscriptChunks(from units: [String]) -> [String] {
        guard !units.isEmpty else { return [] }

        var chunks: [String] = []
        var currentUnits: [String] = []
        var currentWordCount = 0

        for unit in units {
            let unitWordCount = max(1, wordCount(in: unit))
            let exceedsWordLimit = !currentUnits.isEmpty &&
                (currentWordCount + unitWordCount) > Self.maximumTranscriptChunkWordCount

            if exceedsWordLimit {
                chunks.append(currentUnits.joined(separator: " "))
                currentUnits = [unit]
                currentWordCount = unitWordCount
                continue
            }

            currentUnits.append(unit)
            currentWordCount += unitWordCount
        }

        if !currentUnits.isEmpty {
            chunks.append(currentUnits.joined(separator: " "))
        }

        return chunks
    }

    private func splitTextByWordCount(_ text: String, maximumWords: Int) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }

        var chunks: [String] = []
        var startIndex = 0

        while startIndex < words.count {
            let endIndex = min(startIndex + maximumWords, words.count)
            let chunk = words[startIndex..<endIndex].joined(separator: " ")
            chunks.append(chunk)
            startIndex = endIndex
        }

        return chunks
    }

    private func wordCount(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private func normalizedDiarizationSegments(
        _ segments: [SpeakerSegment],
        audioDuration: TimeInterval
    ) -> [SpeakerSegment] {
        let clampedSegments: [SpeakerSegment] = segments
            .compactMap { segment in
                let start = max(0, min(segment.startTime, audioDuration))
                let end = max(0, min(segment.endTime, audioDuration))
                guard end > start else { return nil }
                return SpeakerSegment(
                    speaker: segment.speaker,
                    startTime: start,
                    endTime: end,
                    confidence: segment.confidence
                )
            }
            .sorted { $0.startTime < $1.startTime }

        guard !clampedSegments.isEmpty else { return [] }

        var mergedSegments: [SpeakerSegment] = []
        mergedSegments.reserveCapacity(clampedSegments.count)

        for segment in clampedSegments {
            guard let previous = mergedSegments.last else {
                mergedSegments.append(segment)
                continue
            }

            let gap = segment.startTime - previous.endTime
            let sameSpeaker = previous.speaker.id == segment.speaker.id

            if sameSpeaker && gap <= Self.diarizationMergeGapSeconds {
                let previousDuration = max(previous.duration, 0.001)
                let currentDuration = max(segment.duration, 0.001)
                let combinedDuration = previousDuration + currentDuration
                let weightedConfidence = (
                    previous.confidence * Float(previousDuration) +
                    segment.confidence * Float(currentDuration)
                ) / Float(combinedDuration)

                let mergedSpeaker = Speaker(
                    id: previous.speaker.id,
                    label: previous.speaker.label,
                    embedding: previous.speaker.embedding ?? segment.speaker.embedding
                )

                let merged = SpeakerSegment(
                    speaker: mergedSpeaker,
                    startTime: previous.startTime,
                    endTime: max(previous.endTime, segment.endTime),
                    confidence: weightedConfidence
                )

                mergedSegments[mergedSegments.count - 1] = merged
            } else {
                mergedSegments.append(segment)
            }
        }

        return mergedSegments
    }

    private func extractAudioData(
        samples: [Float],
        sampleRate: Int,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> Data? {
        guard sampleRate > 0, !samples.isEmpty else { return nil }

        let startIndex = max(0, min(samples.count - 1, Int((startTime * Double(sampleRate)).rounded(.down))))
        let endIndex = max(startIndex, min(samples.count, Int((endTime * Double(sampleRate)).rounded(.up))))
        guard endIndex > startIndex else { return nil }

        let minimumSamples = Int(Double(sampleRate) * Self.minimumSegmentDurationSeconds)
        guard (endIndex - startIndex) >= minimumSamples else { return nil }

        let segmentSamples = Array(samples[startIndex..<endIndex])
        return segmentSamples.withUnsafeBufferPointer { pointer in
            Data(buffer: pointer)
        }
    }

    private func getOrCreateSpeakerDiarizer() -> any SpeakerDiarizer {
        if let speakerDiarizer {
            return speakerDiarizer
        }

        let created = speakerDiarizerFactory()
        speakerDiarizer = created
        return created
    }

    private static func defaultEngineFactory(
        provider: ModelManager.ModelProvider
    ) throws -> any TranscriptionEngine {
        switch provider {
        case .whisperKit:
            return WhisperKitEngine()
        case .parakeet:
            return ParakeetEngine()
        default:
            throw TranscriptionError.modelLoadFailed("Provider \(provider.rawValue) not supported locally")
        }
    }

    private func getDownloadBase() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Pindrop", isDirectory: true)
    }

    private func getStreamingModelBase() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    private func applyStreamingCallbacks() {
        guard let streamingEngine else { return }

        streamingEngine.setTranscriptionCallback { [weak self] result in
            guard !result.isFinal else { return }
            Task { @MainActor [weak self] in
                self?.streamingPartialCallback?(result.text)
            }
        }

        streamingEngine.setEndOfUtteranceCallback { [weak self] text in
            Task { @MainActor [weak self] in
                self?.streamingFinalUtteranceCallback?(text)
            }
        }
    }

    private func dataToFloatArray(_ data: Data) -> [Float] {
        let floatCount = data.count / MemoryLayout<Float>.size
        var floatArray = [Float](repeating: 0, count: floatCount)

        data.withUnsafeBytes { rawBuffer in
            let floatBuffer = rawBuffer.bindMemory(to: Float.self)
            for index in 0..<floatCount {
                floatArray[index] = floatBuffer[index]
            }
        }

        return floatArray
    }
}
