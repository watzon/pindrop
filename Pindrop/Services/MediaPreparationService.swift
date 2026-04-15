//
//  MediaPreparationService.swift
//  Pindrop
//
//  Created on 2026-03-07.
//

@preconcurrency import AVFoundation
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
    private let fileManager: FileManager
    private static let targetSampleRate: Double = 16_000
    // Target buffer size per read — small enough to tolerate malformed packet
    // tables on ~MB boundaries instead of blowing up on a single multi-GB read.
    private static let readChunkFrames: AVAudioFrameCount = 1 << 17  // 131 072 frames ≈ 2.7s @ 48 kHz

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func prepareAudio(from mediaURL: URL, ffmpegPath: String? = nil) async throws -> PreparedMediaAudio {
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
                Log.app.warning("MediaPreparation: ffmpeg transcode failed — \(error.localizedDescription). Falling back to AVAssetExportSession")
            }
        }

        // 3. Last resort: AVAssetExportSession → m4a. Kept for parity with
        //    the previous behavior when ffmpeg is not on PATH.
        let exportedURL = try await exportAudioTrack(from: mediaURL)
        defer { try? fileManager.removeItem(at: exportedURL) }
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
            try readAndConvert(
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
            if error is MediaPreparationError {
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
    ) throws {
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

            if status == .endOfStream || state.reachedEnd {
                break
            }
        }
    }

    // MARK: - ffmpeg path

    private func ffmpegTranscode(mediaURL: URL, ffmpegPath: String) async throws -> URL {
        let outputURL = fileManager.temporaryDirectory
            .appendingPathComponent("pindrop-prep-\(UUID().uuidString)")
            .appendingPathExtension("wav")
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

        let (status, stderr) = try await runProcess(executablePath: ffmpegPath, arguments: arguments)
        if status != 0 {
            throw MediaPreparationError.exportFailed("ffmpeg exited \(status): \(stderr.prefix(500))")
        }
        guard fileManager.fileExists(atPath: outputURL.path) else {
            throw MediaPreparationError.exportFailed("ffmpeg reported success but produced no output file.")
        }
        return outputURL
    }

    private func runProcess(executablePath: String, arguments: [String]) async throws -> (Int32, String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stderrPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = stderrPipe
            process.terminationHandler = { proc in
                let data = ((try? stderrPipe.fileHandleForReading.readToEnd()) ?? nil) ?? Data()
                let stderr = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (proc.terminationStatus, stderr))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
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

        let outputURL = fileManager.temporaryDirectory
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
