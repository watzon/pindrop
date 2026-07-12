//
//  MediaPreparationService.swift
//  Pindrop
//
//  Created on 2026-03-07.
//

@preconcurrency import AVFoundation
import Darwin
import Foundation

struct PreparedMediaAudio: Equatable, Sendable {
    let audioData: Data
    let duration: TimeInterval
}

protocol MediaAudioPreparing: Sendable {
    func prepareAudio(from mediaURL: URL, ffmpegPath: String?) async throws -> PreparedMediaAudio
}

extension MediaAudioPreparing {
    func prepareAudio(from mediaURL: URL) async throws -> PreparedMediaAudio {
        try await prepareAudio(from: mediaURL, ffmpegPath: nil)
    }
}

enum MediaPreparationError: Error, LocalizedError {
    case unsupportedMedia(String)
    case exportFailed(String)
    case readFailed(String)
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedMedia(let message):
            return "Unsupported media: \(message)"
        case .exportFailed(let message):
            return "Failed to export audio from media: \(message)"
        case .readFailed(let message):
            return "Failed to read audio: \(message)"
        case .conversionFailed(let message):
            return "Failed to prepare audio for transcription: \(message)"
        }
    }
}

@MainActor
final class MediaPreparationService: MediaAudioPreparing {
    private let worker: MediaAudioPreparationWorker

    init(fileManager: FileManager = .default, temporaryDirectory: URL? = nil) {
        worker = MediaAudioPreparationWorker(
            fileManager: fileManager,
            temporaryDirectory: temporaryDirectory ?? fileManager.temporaryDirectory
        )
    }

    func prepareAudio(from mediaURL: URL, ffmpegPath: String? = nil) async throws -> PreparedMediaAudio {
        try await worker.prepare(
            MediaPreparationInput(mediaURL: mediaURL, ffmpegPath: ffmpegPath)
        )
    }
}

private struct MediaPreparationInput: Sendable {
    let mediaURL: URL
    let ffmpegPath: String?
}

private final class ProcessStandardErrorCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.withLock {
            data.append(newData)
        }
    }

    var string: String {
        lock.withLock {
            String(data: data, encoding: .utf8) ?? ""
        }
    }
}

private final class DeferredProcessOutputCleanup: @unchecked Sendable {
    private let lock = NSLock()
    private let fileManager: FileManager
    private let outputURL: URL
    private var processExited = false
    private var cleanupScheduled = false
    private var ownsOutput = true

    init(fileManager: FileManager, outputURL: URL) {
        self.fileManager = fileManager
        self.outputURL = outputURL
    }

    func scheduleCleanup() {
        let shouldRemove = lock.withLock { () -> Bool in
            cleanupScheduled = true
            return processExited && ownsOutput
        }
        if shouldRemove {
            try? fileManager.removeItem(at: outputURL)
        }
    }

    func processDidExit() {
        let shouldRemove = lock.withLock { () -> Bool in
            processExited = true
            return cleanupScheduled && ownsOutput
        }
        if shouldRemove {
            try? fileManager.removeItem(at: outputURL)
        }
    }

    func relinquishOwnership() {
        lock.withLock {
            ownsOutput = false
        }
    }
}

private final class ProcessCompletionState: @unchecked Sendable {
    typealias Result = Swift.Result<(Int32, String), Error>
    private static let terminationGraceNanoseconds: UInt64 = 1_000_000_000

    private let lock = NSLock()
    private let didExit: @Sendable () -> Void
    private var continuation: CheckedContinuation<(Int32, String), Error>?
    private var result: Result?
    private var process: Process?
    private var cancellationRequested = false

    init(didExit: @escaping @Sendable () -> Void) {
        self.didExit = didExit
    }

    func launch(_ process: Process, continuation: CheckedContinuation<(Int32, String), Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            didExit()
            continuation.resume(with: result)
            return
        }
        self.process = process
        self.continuation = continuation

        guard !cancellationRequested else {
            lock.unlock()
            complete(.failure(CancellationError()))
            didExit()
            clearProcess()
            return
        }

        do {
            try process.run()
            lock.unlock()
        } catch {
            lock.unlock()
            complete(.failure(error))
            didExit()
            clearProcess()
        }
    }

    func cancel() {
        let process = lock.withLock { () -> Process? in
            cancellationRequested = true
            return self.process
        }
        if process?.isRunning == true {
            process?.terminate()
            scheduleForcedTermination()
        }
        complete(.failure(CancellationError()))
    }

    func processDidExit(with result: Result) {
        complete(result)
        didExit()
        clearProcess()
    }

    func complete(_ result: Result) {
        let continuation = lock.withLock { () -> CheckedContinuation<(Int32, String), Error>? in
            guard self.result == nil else { return nil }
            self.result = result
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(with: result)
    }

    func clearProcess() {
        lock.withLock {
            process = nil
        }
    }

    private func scheduleForcedTermination() {
        Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: Self.terminationGraceNanoseconds)
            self?.forceTerminateIfNecessary()
        }
    }

    private func forceTerminateIfNecessary() {
        let processIdentifier = lock.withLock { () -> pid_t? in
            guard let process, process.isRunning else { return nil }
            return process.processIdentifier
        }
        guard let processIdentifier, processIdentifier > 0 else { return }
        Darwin.kill(processIdentifier, SIGKILL)
    }
}

/// Keeps synchronous AVFoundation decode and conversion work off the main actor.
private actor MediaAudioPreparationWorker {
    private let fileManager: FileManager
    private let temporaryDirectory: URL
    private static let targetSampleRate: Double = 16_000
    // Target buffer size per read — small enough to tolerate malformed packet
    // tables on ~MB boundaries instead of blowing up on a single multi-GB read.
    private static let readChunkFrames: AVAudioFrameCount = 1 << 17  // 131 072 frames ≈ 2.7s @ 48 kHz

    init(fileManager: FileManager = .default, temporaryDirectory: URL) {
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory
    }

    func prepare(_ input: MediaPreparationInput) async throws -> PreparedMediaAudio {
        try Task.checkCancellation()
        let mediaURL = input.mediaURL
        let ffmpegPath = input.ffmpegPath
        let fileSize = (try? fileManager.attributesOfItem(atPath: mediaURL.path)[.size] as? NSNumber)?.int64Value ?? -1
        let uti = (try? mediaURL.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier) ?? "unknown"
        Log.app.info(
            "MediaPreparation: begin source=\(mediaURL.lastPathComponent) " +
            "ext=\(mediaURL.pathExtension) size=\(fileSize) uti=\(uti) " +
            "ffmpegAvailable=\(ffmpegPath != nil)"
        )

        // 1. Try the fast path: AVAudioFile directly on the source.
        if let prepared = try await tryPrepareWithAVAudioFile(url: mediaURL, label: "direct") {
            return prepared
        }
        try Task.checkCancellation()

        // 2. Try ffmpeg transcode to a clean WAV if available. This is the most
        //    robust path for files with malformed packet tables, HLS-fetched
        //    segments, or exotic containers that AVAssetExportSession inherits
        //    bugs from.
        if let ffmpegPath {
            do {
                let wavURL = try await ffmpegTranscode(mediaURL: mediaURL, ffmpegPath: ffmpegPath)
                defer { try? fileManager.removeItem(at: wavURL) }
                if let prepared = try await tryPrepareWithAVAudioFile(url: wavURL, label: "ffmpeg") {
                    return prepared
                }
                Log.app.warning("MediaPreparation: ffmpeg WAV still not readable by AVAudioFile, falling back to AVAssetExportSession")
            } catch {
                if error is CancellationError {
                    throw error
                }
                Log.app.warning("MediaPreparation: ffmpeg transcode failed — \(error.localizedDescription). Falling back to AVAssetExportSession")
            }
        }
        try Task.checkCancellation()

        // 3. Last resort: AVAssetExportSession → m4a. Kept for parity with
        //    the previous behavior when ffmpeg is not on PATH.
        let exportedURL = try await exportAudioTrack(from: mediaURL)
        defer { try? fileManager.removeItem(at: exportedURL) }
        try Task.checkCancellation()
        if let prepared = try await tryPrepareWithAVAudioFile(url: exportedURL, label: "export") {
            return prepared
        }

        throw MediaPreparationError.readFailed(
            "None of the decode paths could read this media. Enable ffmpeg on PATH for better format support."
        )
    }

    // MARK: - AVAudioFile path

    /// Open `url` with AVAudioFile and convert to 16 kHz mono Float32 via
    /// chunked reads. Returns `nil` if the open itself fails — the caller
    /// should fall through to a more aggressive decode. Any failure *after*
    /// a successful open (mid-read, converter allocation) is thrown so the
    /// caller can surface or log it.
    private func tryPrepareWithAVAudioFile(url: URL, label: String) async throws -> PreparedMediaAudio? {
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            Log.app.info("MediaPreparation[\(label)]: AVAudioFile open failed — \(error.localizedDescription)")
            return nil
        }

        let inputFormat = audioFile.processingFormat
        let totalFrames = audioFile.length
        Log.app.info(
            "MediaPreparation[\(label)]: opened frames=\(totalFrames) " +
            "sampleRate=\(inputFormat.sampleRate) channels=\(inputFormat.channelCount) " +
            "common=\(inputFormat.commonFormat.rawValue) interleaved=\(inputFormat.isInterleaved)"
        )

        guard totalFrames > 0 else {
            // AVAudioFile can open some containers (notably MP4 with AAC) and
            // report 0 frames because it doesn't decode the inner track.
            // Signal the caller to try another decode path instead of
            // producing a silent transcript.
            Log.app.warning("MediaPreparation[\(label)]: file reports zero frames, falling through to next decode path")
            return nil
        }

        let outputFormat = Self.targetFormat
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw MediaPreparationError.conversionFailed("Unable to initialize audio converter.")
        }

        var accumulated = Data()
        // Reserve a generous capacity to reduce reallocations.
        let expectedOutputFrames = Int(Double(totalFrames) * outputFormat.sampleRate / max(inputFormat.sampleRate, 1))
        accumulated.reserveCapacity(max(0, expectedOutputFrames) * MemoryLayout<Float>.size)

        do {
            try await readAndConvert(
                audioFile: audioFile,
                inputFormat: inputFormat,
                outputFormat: outputFormat,
                converter: converter,
                into: &accumulated
            )
        } catch {
            Log.app.error("MediaPreparation[\(label)]: chunked read failed — \(error.localizedDescription)")
            // Signal the caller to try another decode path rather than surfacing here —
            // except for .conversionFailed which is definitive.
            if error is CancellationError || error is MediaPreparationError {
                throw error
            }
            return nil
        }

        let duration = Double(totalFrames) / max(inputFormat.sampleRate, 1)
        Log.app.info("MediaPreparation[\(label)]: success bytes=\(accumulated.count) duration=\(String(format: "%.2f", duration))s")
        return PreparedMediaAudio(audioData: accumulated, duration: duration)
    }

    private func readAndConvert(
        audioFile: AVAudioFile,
        inputFormat: AVAudioFormat,
        outputFormat: AVAudioFormat,
        converter: AVAudioConverter,
        into accumulated: inout Data
    ) async throws {
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: Self.readChunkFrames) else {
            throw MediaPreparationError.readFailed("Unable to allocate input buffer.")
        }

        let sampleRatio = outputFormat.sampleRate / max(inputFormat.sampleRate, 1)
        let outputCapacity = AVAudioFrameCount(Double(Self.readChunkFrames) * sampleRatio) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            throw MediaPreparationError.conversionFailed("Unable to allocate output buffer.")
        }

        final class ChunkState: @unchecked Sendable {
            var supplied = false
            var reachedEnd = false
        }
        let state = ChunkState()

        while true {
            try Task.checkCancellation()
            inputBuffer.frameLength = 0
            do {
                try audioFile.read(into: inputBuffer)
            } catch {
                // Per AVAudioFile docs, read throws once EOF/packet issues are
                // hit. If we already produced some samples treat it as the
                // natural end of stream; otherwise rethrow so the caller can
                // try another decode path.
                if accumulated.isEmpty {
                    throw MediaPreparationError.readFailed(error.localizedDescription)
                } else {
                    Log.app.warning("MediaPreparation: truncating read at tail — \(error.localizedDescription)")
                    break
                }
            }

            if inputBuffer.frameLength == 0 {
                break
            }

            state.supplied = false
            state.reachedEnd = (audioFile.framePosition >= audioFile.length)

            outputBuffer.frameLength = 0
            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                if state.supplied {
                    outStatus.pointee = state.reachedEnd ? .endOfStream : .noDataNow
                    return nil
                }
                state.supplied = true
                outStatus.pointee = .haveData
                return inputBuffer
            }

            if let conversionError {
                throw MediaPreparationError.conversionFailed(conversionError.localizedDescription)
            }

            if outputBuffer.frameLength > 0, let channelData = outputBuffer.floatChannelData {
                let frames = Int(outputBuffer.frameLength)
                let byteCount = frames * MemoryLayout<Float>.size
                channelData[0].withMemoryRebound(to: UInt8.self, capacity: byteCount) { ptr in
                    accumulated.append(ptr, count: byteCount)
                }
            }

            try Task.checkCancellation()

            if status == .endOfStream || state.reachedEnd {
                break
            }
        }
    }

    // MARK: - ffmpeg path

    private func ffmpegTranscode(mediaURL: URL, ffmpegPath: String) async throws -> URL {
        let outputURL = temporaryDirectory
            .appendingPathComponent("pindrop-prep-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let outputCleanup = DeferredProcessOutputCleanup(fileManager: fileManager, outputURL: outputURL)
        if fileManager.fileExists(atPath: outputURL.path) {
            try? fileManager.removeItem(at: outputURL)
        }

        // 16 kHz mono signed 16-bit PCM WAV — matches what AVAudioFile handles
        // most reliably. We'll upconvert floats via AVAudioConverter afterwards.
        let arguments = [
            "-nostdin",
            "-y",
            "-hide_banner",
            "-loglevel", "error",
            "-i", mediaURL.path,
            "-vn",
            "-ac", "1",
            "-ar", String(Int(Self.targetSampleRate)),
            "-acodec", "pcm_s16le",
            "-f", "wav",
            outputURL.path
        ]

        Log.app.info("MediaPreparation: launching ffmpeg for \(mediaURL.lastPathComponent) → \(outputURL.lastPathComponent)")

        do {
            let (status, stderr) = try await runProcess(
                executablePath: ffmpegPath,
                arguments: arguments,
                onExit: { @Sendable in outputCleanup.processDidExit() }
            )
            if status != 0 {
                throw MediaPreparationError.exportFailed("ffmpeg exited \(status): \(stderr.prefix(500))")
            }
            guard fileManager.fileExists(atPath: outputURL.path) else {
                throw MediaPreparationError.exportFailed("ffmpeg reported success but produced no output file.")
            }
            outputCleanup.relinquishOwnership()
            return outputURL
        } catch {
            outputCleanup.scheduleCleanup()
            throw error
        }
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        onExit: @escaping @Sendable () -> Void
    ) async throws -> (Int32, String) {
        let state = ProcessCompletionState(didExit: onExit)
        return try await withTaskCancellationHandler(operation: {
            let result = try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                let stderrPipe = Pipe()
                let stderrCollector = ProcessStandardErrorCollector()

                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = stderrPipe
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    stderrCollector.append(handle.availableData)
                }
                process.terminationHandler = { proc in
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    stderrCollector.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                    state.processDidExit(with: .success((proc.terminationStatus, stderrCollector.string)))
                }

                state.launch(process, continuation: continuation)
            }
            try Task.checkCancellation()
            return result
        }, onCancel: {
            state.cancel()
        })
    }

    // MARK: - AVAssetExportSession path (fallback)

    private func exportAudioTrack(from mediaURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: mediaURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw MediaPreparationError.unsupportedMedia("No audio track was found.")
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MediaPreparationError.exportFailed("Unable to create export session.")
        }

        let outputURL = temporaryDirectory
            .appendingPathComponent("pindrop-export-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        if fileManager.fileExists(atPath: outputURL.path) {
            try? fileManager.removeItem(at: outputURL)
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.shouldOptimizeForNetworkUse = false

        await exportSession.export()

        if exportSession.status == .completed {
            Log.app.info("MediaPreparation: AVAssetExportSession produced \(outputURL.lastPathComponent)")
            return outputURL
        }

        throw MediaPreparationError.exportFailed(exportSession.error?.localizedDescription ?? "Export session did not complete.")
    }

    private static var targetFormat: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: targetSampleRate, channels: 1)!
    }
}
