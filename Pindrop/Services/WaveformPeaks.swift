//
//  WaveformPeaks.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import Accelerate
import AVFoundation
import Foundation

/// Waveform peak extraction and sidecar persistence for dictation audio.
/// Sidecar format: `<basename>.peaks` next to the audio file — JSON array of Float 0…1.
enum WaveformPeaks {
    static let defaultBucketCount = 200
    static let sidecarExtension = "peaks"

    /// Frames per chunked AVAudioFile read. Keeps peak extraction off the full-file
    /// PCM allocation path for long recordings.
    static let extractionChunkFrames: AVAudioFrameCount = 16_384

    static func sidecarURL(for audioURL: URL) -> URL {
        audioURL.deletingPathExtension().appendingPathExtension(sidecarExtension)
    }

    /// Extract normalized peak buckets from a readable audio file (WAV, m4a, CAF, …).
    ///
    /// Reads the file in fixed-size chunks rather than allocating one full-length
    /// PCM buffer. Checks task cancellation between chunks so UI/loaders can abort.
    static func extract(from audioURL: URL, bucketCount: Int = defaultBucketCount) throws -> [Float] {
        let file = try AVAudioFile(forReading: audioURL)
        let format = file.processingFormat
        let totalFrames = file.length
        let buckets = max(bucketCount, 1)
        guard totalFrames > 0 else {
            return Array(repeating: 0, count: buckets)
        }

        let framesPerBucket = max(1, (Int(totalFrames) + buckets - 1) / buckets)
        // Always stream fixed-size chunks so long files never allocate a full-file buffer,
        // even when buckets are few and frames-per-bucket is huge.
        let chunkCapacity = extractionChunkFrames
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkCapacity) else {
            throw WaveformPeaksError.bufferAllocationFailed
        }

        var rawPeaks = [Float](repeating: 0, count: buckets)
        var frameOffset = 0

        while frameOffset < Int(totalFrames) {
            try Task.checkCancellation()

            let remaining = Int(totalFrames) - frameOffset
            let toRead = AVAudioFrameCount(min(remaining, Int(chunkCapacity)))
            buffer.frameLength = 0
            try file.read(into: buffer, frameCount: toRead)

            let readCount = Int(buffer.frameLength)
            guard readCount > 0 else { break }

            if let channelData = buffer.floatChannelData {
                let samples = UnsafeBufferPointer(start: channelData[0], count: readCount)
                accumulatePeaks(
                    samples: samples,
                    frameOffset: frameOffset,
                    framesPerBucket: framesPerBucket,
                    buckets: buckets,
                    rawPeaks: &rawPeaks
                )
            }

            frameOffset += readCount
            if readCount < Int(toRead) { break }
        }

        return normalizePeaks(rawPeaks)
    }

    /// Extract normalized peak buckets from mono interleaved/non-interleaved Float32 PCM data
    /// (the PCM format returned by `AudioRecorder`).
    static func extract(
        fromPCMFloatData data: Data,
        sampleRate: Double = 16_000,
        channelCount: AVAudioChannelCount = 1,
        bucketCount: Int = defaultBucketCount
    ) throws -> [Float] {
        guard sampleRate > 0, channelCount > 0 else {
            throw WaveformPeaksError.invalidFormat
        }
        let sampleCount = data.count / MemoryLayout<Float>.size
        guard sampleCount > 0 else {
            return Array(repeating: 0, count: max(bucketCount, 1))
        }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)),
        let channelData = buffer.floatChannelData else {
            throw WaveformPeaksError.bufferAllocationFailed
        }

        buffer.frameLength = AVAudioFrameCount(sampleCount)
        data.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.bindMemory(to: Float.self).baseAddress else { return }
            channelData[0].update(from: source, count: sampleCount)
        }

        return peaks(from: buffer, bucketCount: bucketCount)
    }

    /// Streams a raw mono Float32 PCM spool into peak buckets. Unlike
    /// `extract(from:)`, this never loads the complete recording into an audio
    /// buffer and is used for native-rate retention spools.
    static func extract(
        fromPCMFloatFile fileURL: URL,
        sampleRate: Double,
        bucketCount: Int = defaultBucketCount
    ) throws -> [Float] {
        guard sampleRate > 0 else { throw WaveformPeaksError.invalidFormat }
        let buckets = max(bucketCount, 1)
        let byteCount = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let sampleCount = byteCount / MemoryLayout<Float>.size
        guard sampleCount > 0 else { return Array(repeating: 0, count: buckets) }

        let samplesPerBucket = max(1, (sampleCount + buckets - 1) / buckets)
        var rawPeaks = [Float](repeating: 0, count: buckets)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var sampleOffset = 0
        while true {
            try Task.checkCancellation()
            let chunk = handle.readData(ofLength: 64 * 1024)
            guard !chunk.isEmpty else { break }
            chunk.withUnsafeBytes { bytes in
                let samples = bytes.bindMemory(to: Float.self)
                for (index, sample) in samples.enumerated() {
                    let bucket = min((sampleOffset + index) / samplesPerBucket, buckets - 1)
                    rawPeaks[bucket] = max(rawPeaks[bucket], abs(sample))
                }
                sampleOffset += samples.count
            }
        }

        return normalizePeaks(rawPeaks)
    }

    static func writeSidecar(_ peaks: [Float], for audioURL: URL) throws {
        let sidecar = sidecarURL(for: audioURL)
        let data = try JSONEncoder().encode(peaks)
        try data.write(to: sidecar, options: .atomic)
    }

    static func readSidecar(for audioURL: URL) throws -> [Float]? {
        let sidecar = sidecarURL(for: audioURL)
        guard FileManager.default.fileExists(atPath: sidecar.path) else { return nil }
        let data = try Data(contentsOf: sidecar)
        return try JSONDecoder().decode([Float].self, from: data)
    }

    static func removeSidecar(for audioURL: URL, fileManager: FileManager = .default) {
        let sidecar = sidecarURL(for: audioURL)
        guard fileManager.fileExists(atPath: sidecar.path) else { return }
        try? fileManager.removeItem(at: sidecar)
    }

    /// Downsample absolute-peak buckets, then normalize to 0…1 by the max peak.
    static func peaks(from buffer: AVAudioPCMBuffer, bucketCount: Int) -> [Float] {
        let buckets = max(bucketCount, 1)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0,
              let channelData = buffer.floatChannelData else {
            return Array(repeating: 0, count: buckets)
        }

        let samples = UnsafeBufferPointer(start: channelData[0], count: frameLength)
        var rawPeaks = [Float](repeating: 0, count: buckets)

        // Absolute peak per bucket via strided scan (vDSP for abs + max where useful).
        let framesPerBucket = max(1, (frameLength + buckets - 1) / buckets)
        for bucket in 0..<buckets {
            let start = bucket * framesPerBucket
            guard start < frameLength else { break }
            let end = min(start + framesPerBucket, frameLength)
            let count = end - start
            var maxAbs: Float = 0
            samples.baseAddress!.advanced(by: start).withMemoryRebound(to: Float.self, capacity: count) { ptr in
                vDSP_maxmgv(ptr, 1, &maxAbs, vDSP_Length(count))
            }
            rawPeaks[bucket] = maxAbs
        }

        return normalizePeaks(rawPeaks)
    }

    /// Fold a chunk of samples into absolute-peak buckets using global frame offsets.
    private static func accumulatePeaks(
        samples: UnsafeBufferPointer<Float>,
        frameOffset: Int,
        framesPerBucket: Int,
        buckets: Int,
        rawPeaks: inout [Float]
    ) {
        let count = samples.count
        guard count > 0, let base = samples.baseAddress else { return }

        var index = 0
        while index < count {
            let globalFrame = frameOffset + index
            let bucket = min(globalFrame / framesPerBucket, buckets - 1)
            let bucketStartFrame = bucket * framesPerBucket
            let bucketEndFrame = min(bucketStartFrame + framesPerBucket, frameOffset + count)
            let localStart = index
            let localEnd = min(localStart + (bucketEndFrame - globalFrame), count)
            let span = localEnd - localStart
            guard span > 0 else { break }

            var maxAbs: Float = 0
            base.advanced(by: localStart).withMemoryRebound(to: Float.self, capacity: span) { ptr in
                vDSP_maxmgv(ptr, 1, &maxAbs, vDSP_Length(span))
            }
            if maxAbs > rawPeaks[bucket] {
                rawPeaks[bucket] = maxAbs
            }
            index = localEnd
        }
    }

    private static func normalizePeaks(_ rawPeaks: [Float]) -> [Float] {
        let buckets = rawPeaks.count
        guard buckets > 0 else { return rawPeaks }

        var globalMax: Float = 0
        vDSP_maxv(rawPeaks, 1, &globalMax, vDSP_Length(buckets))
        guard globalMax > 0 else { return rawPeaks }

        var normalized = [Float](repeating: 0, count: buckets)
        var divisor = globalMax
        vDSP_vsdiv(rawPeaks, 1, &divisor, &normalized, 1, vDSP_Length(buckets))
        return normalized
    }
}

/// Loads waveform peaks from a sidecar if present; otherwise extracts on demand and caches.
/// Concurrent callers for the same URL + bucket count share one in-flight extraction.
enum WaveformPeaksLoader {
    private static let coalescer = WaveformPeaksLoadCoalescer()

    static func load(
        for audioURL: URL,
        bucketCount: Int = WaveformPeaks.defaultBucketCount
    ) throws -> [Float] {
        try coalescer.load(for: audioURL, bucketCount: bucketCount)
    }
}

/// Process-wide in-flight extraction table. Keyed by standardized path + bucket count
/// so concurrent UI opens of the same media share one decode.
private final class WaveformPeaksLoadCoalescer: @unchecked Sendable {
    private struct Key: Hashable {
        let path: String
        let bucketCount: Int
    }

    private final class Entry {
        let condition = NSCondition()
        var result: Result<[Float], Error>?
    }

    private let lock = NSLock()
    private var inFlight: [Key: Entry] = [:]

    func load(for audioURL: URL, bucketCount: Int) throws -> [Float] {
        if let cached = try readCached(audioURL) {
            return cached
        }

        let key = Key(path: audioURL.standardizedFileURL.path, bucketCount: bucketCount)

        lock.lock()
        if let existing = inFlight[key] {
            lock.unlock()
            existing.condition.lock()
            while existing.result == nil {
                existing.condition.wait()
            }
            let result = existing.result!
            existing.condition.unlock()
            return try result.get()
        }

        let entry = Entry()
        inFlight[key] = entry
        lock.unlock()

        let result: Result<[Float], Error>
        do {
            result = .success(try extractAndCache(audioURL: audioURL, bucketCount: bucketCount))
        } catch {
            result = .failure(error)
        }

        entry.condition.lock()
        entry.result = result
        entry.condition.broadcast()
        entry.condition.unlock()

        lock.lock()
        if inFlight[key] === entry {
            inFlight[key] = nil
        }
        lock.unlock()

        return try result.get()
    }

    private func readCached(_ audioURL: URL) throws -> [Float]? {
        if let cached = try WaveformPeaks.readSidecar(for: audioURL), !cached.isEmpty {
            return cached
        }
        return nil
    }

    private func extractAndCache(audioURL: URL, bucketCount: Int) throws -> [Float] {
        if let cached = try readCached(audioURL) {
            return cached
        }
        let peaks = try WaveformPeaks.extract(from: audioURL, bucketCount: bucketCount)
        do {
            try WaveformPeaks.writeSidecar(peaks, for: audioURL)
        } catch {
            Log.audio.warning(
                "Failed to cache waveform peaks for \(audioURL.lastPathComponent): \(error.localizedDescription)"
            )
        }
        return peaks
    }
}

enum WaveformPeaksError: Error, LocalizedError {
    case bufferAllocationFailed
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .bufferAllocationFailed:
            return "Unable to allocate audio buffer for waveform peak extraction."
        case .invalidFormat:
            return "Invalid audio format for waveform peak extraction."
        }
    }
}
