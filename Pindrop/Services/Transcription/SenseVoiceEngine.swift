//
//  SenseVoiceEngine.swift
//  Pindrop
//
//  Created on 2026-07-13.
//

import Foundation
import FluidAudio

/// Batch transcription engine for FunASR SenseVoice-Small via FluidAudio's
/// CoreML / Apple Neural Engine pipeline. Non-autoregressive multilingual ASR
/// (strongest on zh / yue / en / ja / ko) with built-in punctuation tags stripped
/// from the returned text.
///
/// Catalog integration is **int8-only**: discovery, download, and load all share
/// ``catalogPrecision``. FluidAudio 0.15.4+ downloads only the preprocessor +
/// int8 encoder (vocab is fetched as a root `.json` auxiliary).
///
/// Long audio is split into overlapping windows (default 100 s body + 3 s
/// overlap). Adjacent window transcripts are stitched with longest
/// suffix/prefix word-token deduplication so boundary words appear once.
@MainActor
public final class SenseVoiceEngine: TranscriptionEngine, CapabilityReporting {

    public static var capabilities: AudioEngineCapabilities {
        [.transcription]
    }

    /// Sole precision used by the Pindrop catalog entry `sensevoice-small`.
    public static let catalogPrecision: SenseVoiceEncoderPrecision = .int8

    /// Conservative window under FluidAudio's documented ~108 s / 1800-frame cap
    /// so the CoreML path never silently truncates a window.
    public static let maxWindowDurationSeconds = 100

    /// Overlap between consecutive windows so speech near a boundary is fully
    /// covered in at least one window. 3 s is within the 2–5 s guidance band.
    public static let overlapDurationSeconds = 3

    public nonisolated static var maxWindowSamples: Int {
        SenseVoiceConfig.sampleRate * maxWindowDurationSeconds
    }

    public nonisolated static var overlapSamples: Int {
        SenseVoiceConfig.sampleRate * overlapDurationSeconds
    }

    /// Artifact basenames FluidAudio 0.15.4+ will fetch for a precision-aware
    /// SenseVoice download (excludes unused encoder precisions).
    public static func requiredDownloadArtifacts(
        precision: SenseVoiceEncoderPrecision = catalogPrecision
    ) -> Set<String> {
        ModelNames.SenseVoice.requiredModels(precision: precision.rawValue)
    }

    public enum EngineError: Error, LocalizedError {
        case modelNotLoaded
        case invalidAudioData
        case transcriptionFailed(String)
        case downloadFailed(String)
        case initializationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "SenseVoice model is not loaded."
            case .invalidAudioData:
                return "Invalid audio data. Expected 16kHz mono PCM Float32 samples."
            case .transcriptionFailed(let message):
                return "SenseVoice transcription failed: \(message)"
            case .downloadFailed(let message):
                return "SenseVoice model download failed: \(message)"
            case .initializationFailed(let message):
                return "SenseVoice initialization failed: \(message)"
            }
        }
    }

    public private(set) var state: TranscriptionEngineState = .unloaded
    public private(set) var error: Error?

    /// Always matches ``catalogPrecision``.
    public var preferredPrecision: SenseVoiceEncoderPrecision {
        get { Self.catalogPrecision }
        set { /* catalog is int8-only */ }
    }

    private var models: SenseVoiceModels?

    /// Test seam: when set, each window is transcribed through this closure
    /// instead of CoreML. Production leaves it nil.
    var windowTranscribeOverride: (@Sendable (_ samples: [Float], _ language: Int32) async throws -> String)?

    /// Test-only window geometry overrides (keep production constants otherwise).
    var testMaxWindowSamples: Int?
    var testOverlapSamples: Int?

    public init() {}

    public func loadModel(path: String) async throws {
        guard state != .loading else { return }

        state = .loading
        error = nil

        do {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw EngineError.initializationFailed("SenseVoice model directory not found: \(path)")
            }

            let precision = Self.catalogPrecision
            guard SenseVoiceModels.modelsExist(at: directory, precision: precision) else {
                throw EngineError.initializationFailed(
                    "SenseVoice int8 model files incomplete at \(path)"
                )
            }

            models = try SenseVoiceModels.load(from: directory, precision: precision)
            state = .ready
            Log.transcription.info(
                "SenseVoice loaded from path=\(path) precision=\(precision.rawValue)"
            )
        } catch let engineError as EngineError {
            self.error = engineError
            state = .error
            throw engineError
        } catch {
            let mapped = EngineError.initializationFailed(error.localizedDescription)
            self.error = mapped
            state = .error
            throw mapped
        }
    }

    public func loadModel(name: String, downloadBase: URL? = nil) async throws {
        guard state != .loading else { return }

        state = .loading
        error = nil

        do {
            let precision = Self.catalogPrecision
            let loaded: SenseVoiceModels
            if let downloadBase,
               SenseVoiceModels.modelsExist(at: downloadBase, precision: precision) {
                loaded = try SenseVoiceModels.load(from: downloadBase, precision: precision)
            } else {
                loaded = try await SenseVoiceModels.downloadAndLoad(precision: precision)
            }

            models = loaded
            state = .ready
            Log.transcription.info(
                "SenseVoice ready name=\(name) precision=\(precision.rawValue)"
            )
        } catch let engineError as EngineError {
            self.error = engineError
            state = .error
            throw engineError
        } catch {
            let mapped = EngineError.downloadFailed(error.localizedDescription)
            self.error = mapped
            state = .error
            throw mapped
        }
    }

    public func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String {
        if !audioData.isEmpty,
           audioData.count % MemoryLayout<Float>.stride != 0 {
            throw EngineError.invalidAudioData
        }

        let override = windowTranscribeOverride
        if override == nil {
            guard state == .ready, models != nil else {
                throw EngineError.modelNotLoaded
            }
        } else {
            guard state == .ready else {
                throw EngineError.modelNotLoaded
            }
        }

        guard !audioData.isEmpty else {
            throw EngineError.invalidAudioData
        }

        let samples = audioData.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
        guard !samples.isEmpty else {
            throw EngineError.invalidAudioData
        }

        state = .transcribing
        defer {
            if state == .transcribing {
                state = .ready
            }
        }

        let languageIndex = Self.senseVoiceLanguageIndex(for: options.language)
        let maxWindow = testMaxWindowSamples ?? Self.maxWindowSamples
        let overlap = testOverlapSamples ?? Self.overlapSamples
        let windows = Self.partitionSamples(
            samples,
            maxWindowSamples: maxWindow,
            overlapSamples: overlap
        )
        var pieces: [String] = []
        pieces.reserveCapacity(windows.count)

        do {
            for window in windows {
                let text: String
                if let override {
                    text = try await override(window, languageIndex)
                } else if let models {
                    let manager = SenseVoiceManager(
                        models: models,
                        language: languageIndex,
                        textNorm: SenseVoiceConfig.defaultTextNorm
                    )
                    text = try await manager.transcribe(audio: window)
                } else {
                    throw EngineError.modelNotLoaded
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    pieces.append(trimmed)
                }
            }
            return Self.stitchTranscripts(pieces)
        } catch let engineError as EngineError {
            self.error = engineError
            throw engineError
        } catch {
            self.error = error
            throw EngineError.transcriptionFailed(error.localizedDescription)
        }
    }

    public func unloadModel() async {
        models = nil
        error = nil
        state = .unloaded
    }

    public func loadModel(modelName: String) async throws {
        try await loadModel(name: modelName, downloadBase: nil)
    }

    public func loadModel(modelPath: String) async throws {
        try await loadModel(path: modelPath)
    }

    /// Test-only: mark the engine ready so `windowTranscribeOverride` can run
    /// without a real CoreML model load.
    func prepareForWindowTests() {
        state = .ready
        error = nil
    }

    // MARK: - Language / precision / window helpers

    public static func precision(forModelName name: String) -> SenseVoiceEncoderPrecision? {
        let lowered = name.lowercased()
        guard lowered.contains("sensevoice") else { return nil }
        if lowered.contains("fp16") || lowered.contains("fp32") {
            return nil
        }
        return .int8
    }

    public static func senseVoiceLanguageIndex(for language: AppLanguage) -> Int32 {
        switch language {
        case .automatic:
            return SenseVoiceConfig.defaultLanguage
        case .simplifiedChinese:
            return 3
        case .english:
            return 4
        case .japanese:
            return 11
        case .korean:
            return 12
        case .russian, .ukrainian, .spanish, .french, .german, .turkish,
             .portugueseBrazil, .italian, .dutch:
            return SenseVoiceConfig.defaultLanguage
        }
    }

    /// Split samples into windows of at most `maxWindowSamples` with
    /// `overlapSamples` shared between consecutive windows.
    ///
    /// Hop size is `maxWindowSamples - overlapSamples`. The final window is the
    /// normal hop-started partial tail (exactly the configured overlap with the
    /// previous window) — it is **not** right-aligned to a full cap, which would
    /// inflate overlap to nearly the whole window for cap+ε inputs.
    public nonisolated static func partitionSamples(
        _ samples: [Float],
        maxWindowSamples: Int,
        overlapSamples: Int = 0
    ) -> [[Float]] {
        precondition(maxWindowSamples > 0)
        let overlap = min(max(0, overlapSamples), maxWindowSamples - 1)
        guard !samples.isEmpty else { return [] }
        if samples.count <= maxWindowSamples {
            return [samples]
        }

        let hop = max(1, maxWindowSamples - overlap)
        var windows: [[Float]] = []
        var start = 0
        while start < samples.count {
            let end = min(start + maxWindowSamples, samples.count)
            windows.append(Array(samples[start..<end]))
            if end == samples.count { break }
            start += hop
        }
        return windows
    }

    /// Deterministically stitch adjacent window transcripts by dropping the
    /// longest shared word-token suffix/prefix. Falls back to a single space
    /// join when there is no overlapping token run. Punctuation attached to
    /// tokens is preserved (tokens are whitespace-split only).
    public nonisolated static func stitchTranscripts(_ pieces: [String]) -> String {
        let cleaned = pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = cleaned.first else { return "" }
        return cleaned.dropFirst().reduce(first) { partial, next in
            mergeTranscripts(partial, next)
        }
    }

    /// Merge two adjacent window transcripts with longest suffix/prefix dedupe.
    public nonisolated static func mergeTranscripts(_ left: String, _ right: String) -> String {
        let lhs = left.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhs = right.trimmingCharacters(in: .whitespacesAndNewlines)
        if lhs.isEmpty { return rhs }
        if rhs.isEmpty { return lhs }

        let leftTokens = tokenize(lhs)
        let rightTokens = tokenize(rhs)

        if let overlap = longestTokenOverlap(suffixOf: leftTokens, prefixOf: rightTokens),
           overlap > 0 {
            let skipRight = originalTokenCount(spanningComparableCount: overlap, in: rightTokens)
            let keptRight = Array(rightTokens.dropFirst(skipRight))
            if keptRight.isEmpty {
                return joinTokens(leftTokens)
            }
            return joinTokens(leftTokens + keptRight)
        }

        // Character-level fallback only for whitespace-free CJK runs, and only
        // when the shared suffix/prefix is long enough to be intentional
        // (never a coincidental single Latin/CJK character).
        if isWhitespaceFreeCJK(lhs), isWhitespaceFreeCJK(rhs),
           let charOverlap = longestCharacterOverlap(suffixOf: lhs, prefixOf: rhs),
           charOverlap >= Self.minimumCJKCharacterOverlap {
            let index = rhs.index(rhs.startIndex, offsetBy: charOverlap)
            let remainder = String(rhs[index...])
            if remainder.isEmpty {
                return lhs
            }
            return lhs + remainder
        }

        // No overlap — join with a single space.
        return lhs + " " + rhs
    }

    // MARK: - Private stitch helpers

    nonisolated private static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    nonisolated private static func joinTokens(_ tokens: [String]) -> String {
        tokens.joined(separator: " ")
    }

    /// Comparison-only normalization: Unicode case-fold via `lowercased()`, strip
    /// leading/trailing punctuation and symbols. Empty results are ignored for
    /// overlap. Display tokens always keep their original spelling/punctuation.
    nonisolated static func normalizeTokenForComparison(_ token: String) -> String {
        token
            .lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .symbols)
    }

    /// Comparable (non-empty normalized) projections of raw whitespace tokens.
    nonisolated private static func comparableTokens(from tokens: [String]) -> [String] {
        tokens.compactMap { token in
            let normalized = normalizeTokenForComparison(token)
            return normalized.isEmpty ? nil : normalized
        }
    }

    /// How many original tokens must be skipped to drop `comparableCount`
    /// non-empty-normalized tokens from the front of `tokens`.
    nonisolated private static func originalTokenCount(
        spanningComparableCount comparableCount: Int,
        in tokens: [String]
    ) -> Int {
        guard comparableCount > 0 else { return 0 }
        var seen = 0
        var index = 0
        while index < tokens.count, seen < comparableCount {
            if !normalizeTokenForComparison(tokens[index]).isEmpty {
                seen += 1
            }
            index += 1
        }
        return index
    }

    nonisolated private static func longestTokenOverlap(
        suffixOf left: [String],
        prefixOf right: [String]
    ) -> Int? {
        let leftComparable = comparableTokens(from: left)
        let rightComparable = comparableTokens(from: right)
        let maxK = min(leftComparable.count, rightComparable.count)
        guard maxK > 0 else { return nil }
        // Prefer longer overlaps. Comparison uses normalized forms only; the
        // caller keeps left-side original tokens for display.
        for k in stride(from: maxK, through: 1, by: -1) {
            if leftComparable.suffix(k).elementsEqual(rightComparable.prefix(k)) {
                return k
            }
        }
        return nil
    }

    /// Minimum shared characters required before CJK char-fallback dedupe runs.
    /// 1-char overlaps are common coincidences ("s"/"s", "的"/"的") and must not
    /// rewrite either side.
    nonisolated private static let minimumCJKCharacterOverlap = 2

    nonisolated private static func longestCharacterOverlap(
        suffixOf left: String,
        prefixOf right: String
    ) -> Int? {
        let maxK = min(min(left.count, right.count), 40)
        guard maxK >= minimumCJKCharacterOverlap else { return nil }
        for k in stride(from: maxK, through: minimumCJKCharacterOverlap, by: -1) {
            let leftSuffix = left.suffix(k)
            let rightPrefix = right.prefix(k)
            if leftSuffix == rightPrefix {
                return k
            }
        }
        return nil
    }

    /// True when `text` has no whitespace and is composed primarily of CJK
    /// Unified Ideographs / Hangul / Hiragana / Katakana (not Latin).
    nonisolated private static func isWhitespaceFreeCJK(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard text.allSatisfy({ !$0.isWhitespace }) else { return false }
        var cjkCount = 0
        var total = 0
        for scalar in text.unicodeScalars {
            total += 1
            if isCJKScalar(scalar) {
                cjkCount += 1
            }
        }
        // Require a clear CJK majority so mixed Latin punctuation runs stay on
        // the word-token / space-join path.
        return total > 0 && cjkCount * 2 >= total
    }

    nonisolated private static func isCJKScalar(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        switch v {
        case 0x3040...0x30FF: return true // Hiragana + Katakana
        case 0x3400...0x4DBF: return true // CJK Extension A
        case 0x4E00...0x9FFF: return true // CJK Unified
        case 0xAC00...0xD7AF: return true // Hangul Syllables
        case 0xF900...0xFAFF: return true // CJK Compatibility Ideographs
        case 0xFF66...0xFF9D: return true // Halfwidth Katakana
        default: return false
        }
    }

    nonisolated private static func needsSpaceJoin(lhs: String, rhs: String) -> Bool {
        guard let last = lhs.last, let first = rhs.first else { return true }
        // Space when either side ends/starts with a Latin letter or digit.
        let leftNeeds = last.isLetter && last.isASCII || last.isNumber
        let rightNeeds = first.isLetter && first.isASCII || first.isNumber
        return leftNeeds || rightNeeds
    }
}
