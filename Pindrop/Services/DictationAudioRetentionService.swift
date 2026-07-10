//
//  DictationAudioRetentionService.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import AVFoundation
import Foundation

/// Encodes float32 PCM dictation buffers to AAC `.m4a` under the managed DictationAudio area.
/// Input is the 16 kHz mono float32 buffer produced by `AudioRecorder`; AAC is written at 44.1 kHz
/// (Core Audio rejects MPEG-4 AAC at 16 kHz).
enum DictationAudioEncoder {
    /// Sample rate of recorded dictation PCM from `AudioRecorder`.
    static let inputSampleRate: Double = 16_000
    /// AAC-friendly output rate.
    static let outputSampleRate: Double = 44_100
    static let channelCount: AVAudioChannelCount = 1
    static let bitRate = 64_000

    static func encodePCMFloatData(
        _ audioData: Data,
        to destinationURL: URL,
        inputSampleRate: Double = inputSampleRate,
        channelCount: AVAudioChannelCount = channelCount
    ) throws {
        let sampleCount = audioData.count / MemoryLayout<Float>.size
        guard sampleCount > 0 else {
            throw DictationAudioError.emptyAudio
        }

        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputSampleRate,
            channels: channelCount,
            interleaved: false
        ),
        let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ),
        let inputChannelData = inputBuffer.floatChannelData else {
            throw DictationAudioError.encodingFailed("Unable to prepare PCM buffer for AAC encode.")
        }

        inputBuffer.frameLength = AVAudioFrameCount(sampleCount)
        audioData.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.bindMemory(to: Float.self).baseAddress else { return }
            inputChannelData[0].update(from: source, count: sampleCount)
        }

        // Resample to an AAC-supported rate when needed.
        let encodeBuffer: AVAudioPCMBuffer
        if abs(inputSampleRate - outputSampleRate) < 0.5 {
            encodeBuffer = inputBuffer
        } else {
            encodeBuffer = try resample(inputBuffer, toSampleRate: outputSampleRate)
        }

        let parent = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: encodeBuffer.format.sampleRate,
            AVNumberOfChannelsKey: Int(channelCount),
            AVEncoderBitRateKey: bitRate
        ]

        do {
            let outputFile = try AVAudioFile(
                forWriting: destinationURL,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try outputFile.write(from: encodeBuffer)
        } catch {
            throw DictationAudioError.encodingFailed(error.localizedDescription)
        }
    }

    private static func resample(
        _ inputBuffer: AVAudioPCMBuffer,
        toSampleRate outputSampleRate: Double
    ) throws -> AVAudioPCMBuffer {
        let inputFormat = inputBuffer.format
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputSampleRate,
            channels: inputFormat.channelCount,
            interleaved: false
        ) else {
            throw DictationAudioError.encodingFailed("Unable to create AAC resample format.")
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw DictationAudioError.encodingFailed("Unable to create audio converter for AAC encode.")
        }

        let ratio = outputSampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 32
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw DictationAudioError.encodingFailed("Unable to allocate resample buffer.")
        }

        var inputConsumed = false
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let error {
            throw DictationAudioError.encodingFailed(error.localizedDescription)
        }
        guard status != .error else {
            throw DictationAudioError.encodingFailed("Audio resampler failed.")
        }
        guard outputBuffer.frameLength > 0 else {
            throw DictationAudioError.encodingFailed("Audio resampler produced empty buffer.")
        }

        return outputBuffer
    }
}

enum DictationAudioError: Error, LocalizedError {
    case emptyAudio
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyAudio:
            return "No audio samples to encode."
        case .encodingFailed(let message):
            return "Failed to encode dictation audio: \(message)"
        }
    }
}

struct DictationAudioDiskUsage: Equatable, Sendable {
    let totalBytes: Int64
    let snippetCount: Int
}

struct DictationAudioSweepResult: Equatable, Sendable {
    let deletedCount: Int
    let freedBytes: Int64
}

/// Persists dictation audio off the insertion hot path, sweeps expired files, and
/// reports disk usage for the DictationAudio area. Applies only to `voiceRecording`.
@MainActor
final class DictationAudioRetentionService {
    static let sweepInterval: TimeInterval = 24 * 60 * 60

    private let historyStore: HistoryStore
    private let settingsStore: SettingsStore
    private let fileManager: FileManager
    private let now: () -> Date
    private let directoryURL: URL
    private var sweepTimer: Timer?
    private var pendingPersistTasks: [UUID: Task<Void, Never>] = [:]

    init(
        historyStore: HistoryStore,
        settingsStore: SettingsStore,
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.historyStore = historyStore
        self.settingsStore = settingsStore
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? ManagedMediaLibrary.dictationAudioDirectoryURL
        self.now = now
    }

    deinit {
        sweepTimer?.invalidate()
    }

    // MARK: - Persistence (async, off hot path)

    /// Save the history record first, then call this with the captured PCM data.
    /// Encode + peaks run off the main actor; the record is updated when ready.
    /// When retention is `.off`, does nothing.
    func schedulePersist(pcmFloatData: Data, recordID: UUID) {
        guard settingsStore.dictationAudioRetention != .off else {
            Log.audio.debug("Dictation audio persistence skipped (retention=off) record=\(recordID)")
            return
        }
        guard !pcmFloatData.isEmpty else {
            Log.audio.debug("Dictation audio persistence skipped (empty buffer) record=\(recordID)")
            return
        }

        pendingPersistTasks[recordID]?.cancel()
        let destinationDirectory = directoryURL
        let audioData = pcmFloatData

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let mediaURL = try await Task.detached(priority: .utility) {
                    try Self.encodeAndWritePeaks(
                        pcmFloatData: audioData,
                        recordID: recordID,
                        directoryURL: destinationDirectory
                    )
                }.value

                guard !Task.isCancelled else {
                    Self.removeUnlinkedMedia(at: mediaURL)
                    return
                }

                let didAttach = try self.historyStore.updateManagedMediaPath(
                    for: recordID,
                    path: mediaURL.path
                )
                if didAttach {
                    Log.audio.info(
                        "Persisted dictation audio for \(recordID.uuidString) → \(mediaURL.lastPathComponent)"
                    )
                } else {
                    // Record was deleted (or otherwise missing) while encode ran — drop orphans.
                    Self.removeUnlinkedMedia(at: mediaURL)
                    Log.audio.info(
                        "Discarded dictation audio for missing record \(recordID.uuidString)"
                    )
                }
            } catch {
                Log.audio.error(
                    "Failed to persist dictation audio for \(recordID.uuidString): \(error.localizedDescription)"
                )
            }

            self.pendingPersistTasks[recordID] = nil
        }

        pendingPersistTasks[recordID] = task
    }

    /// Synchronous encode used by tests and the detached persistence path.
    nonisolated static func encodeAndWritePeaks(
        pcmFloatData: Data,
        recordID: UUID,
        directoryURL: URL
    ) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let mediaURL = directoryURL
            .appendingPathComponent(recordID.uuidString)
            .appendingPathExtension("m4a")

        try DictationAudioEncoder.encodePCMFloatData(pcmFloatData, to: mediaURL)

        do {
            let peaks = try WaveformPeaks.extract(
                fromPCMFloatData: pcmFloatData,
                sampleRate: DictationAudioEncoder.inputSampleRate
            )
            try WaveformPeaks.writeSidecar(peaks, for: mediaURL)
        } catch {
            Log.audio.warning(
                "Waveform peaks extraction failed for \(recordID.uuidString): \(error.localizedDescription)"
            )
        }

        return mediaURL
    }

    /// Removes a just-written media file and its peaks sidecar when they will never be linked.
    nonisolated static func removeUnlinkedMedia(at mediaURL: URL) {
        try? FileManager.default.removeItem(at: mediaURL)
        WaveformPeaks.removeSidecar(for: mediaURL)
    }

    // MARK: - Retention sweep

    /// Deletes expired dictation audio + peaks sidecars and clears `managedMediaPath`.
    /// Transcript text is preserved. Imported / media-backed records are never touched.
    @discardableResult
    func sweepExpired() throws -> DictationAudioSweepResult {
        let retention = settingsStore.dictationAudioRetention
        guard let interval = retention.retentionInterval, interval > 0 else {
            // `.off` and `.forever` do not expire existing files via the windowed sweeper.
            // `.off` only prevents new persistence; existing files remain until manual delete
            // or a later retention change that re-enables a finite window.
            if retention == .forever || retention == .off {
                Log.audio.debug("Dictation audio sweep skipped (retention=\(retention.rawValue))")
            }
            return DictationAudioSweepResult(deletedCount: 0, freedBytes: 0)
        }

        let cutoff = now().addingTimeInterval(-interval)
        let voiceRaw = MediaSourceKind.voiceRecording.rawValue
        let records = try historyStore.fetchAll()

        var deletedCount = 0
        var freedBytes: Int64 = 0

        for record in records {
            let kind = record.sourceKindRawValue ?? voiceRaw
            guard kind == voiceRaw else { continue }
            guard let path = record.managedMediaPath,
                  !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            guard record.timestamp < cutoff else { continue }

            let mediaURL = URL(fileURLWithPath: path)
            freedBytes += removeAudioAndSidecar(at: mediaURL)
            record.managedMediaPath = nil
            deletedCount += 1
        }

        if deletedCount > 0 {
            try historyStore.saveContext()
        }

        Log.audio.info(
            "Dictation audio retention sweep: deleted \(deletedCount) file(s), freed \(freedBytes) bytes (retention=\(retention.rawValue))"
        )
        return DictationAudioSweepResult(deletedCount: deletedCount, freedBytes: freedBytes)
    }

    /// Launch-time sweep + 24h repeating timer.
    func startPeriodicSweep() {
        sweepTimer?.invalidate()

        do {
            _ = try sweepExpired()
        } catch {
            Log.audio.error("Dictation audio launch sweep failed: \(error.localizedDescription)")
        }

        let timer = Timer.scheduledTimer(withTimeInterval: Self.sweepInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                do {
                    _ = try self?.sweepExpired()
                } catch {
                    Log.audio.error("Dictation audio periodic sweep failed: \(error.localizedDescription)")
                }
            }
        }
        // Allow the timer to fire while tracking is in common modes (menus, etc.).
        RunLoop.main.add(timer, forMode: .common)
        sweepTimer = timer
    }

    func stopPeriodicSweep() {
        sweepTimer?.invalidate()
        sweepTimer = nil
    }

    // MARK: - Disk usage

    /// Aggregate size + count of audio files under the DictationAudio directory
    /// (`.m4a` only; peaks sidecars are not counted as snippets).
    func diskUsage() throws -> DictationAudioDiskUsage {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return DictationAudioDiskUsage(totalBytes: 0, snippetCount: 0)
        }

        let items = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var totalBytes: Int64 = 0
        var snippetCount = 0

        for url in items {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            totalBytes += size
            if url.pathExtension.lowercased() == "m4a" {
                snippetCount += 1
            }
        }

        return DictationAudioDiskUsage(totalBytes: totalBytes, snippetCount: snippetCount)
    }

    /// Deletes all dictation audio files + peaks and clears `managedMediaPath` on
    /// voiceRecording records. Transcripts are kept.
    func deleteAllDictationAudio() throws {
        let voiceRaw = MediaSourceKind.voiceRecording.rawValue
        let records = try historyStore.fetchAll()

        for record in records {
            let kind = record.sourceKindRawValue ?? voiceRaw
            guard kind == voiceRaw else { continue }
            if let path = record.managedMediaPath,
               !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                _ = removeAudioAndSidecar(at: URL(fileURLWithPath: path))
            }
            record.managedMediaPath = nil
        }

        try historyStore.saveContext()

        // Remove any orphaned files left in the DictationAudio directory.
        if fileManager.fileExists(atPath: directoryURL.path) {
            let items = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for url in items {
                try? fileManager.removeItem(at: url)
            }
        }

        Log.audio.info("Deleted all dictation audio under \(directoryURL.path)")
    }

    // MARK: - Helpers

    @discardableResult
    private func removeAudioAndSidecar(at mediaURL: URL) -> Int64 {
        var freed: Int64 = 0

        if fileManager.fileExists(atPath: mediaURL.path) {
            let size = (try? mediaURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            do {
                try fileManager.removeItem(at: mediaURL)
                freed += size
            } catch {
                Log.audio.warning("Failed to delete dictation audio at \(mediaURL.path): \(error.localizedDescription)")
            }
        }

        let sidecar = WaveformPeaks.sidecarURL(for: mediaURL)
        if fileManager.fileExists(atPath: sidecar.path) {
            let size = (try? sidecar.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            do {
                try fileManager.removeItem(at: sidecar)
                freed += size
            } catch {
                Log.audio.warning("Failed to delete peaks sidecar at \(sidecar.path): \(error.localizedDescription)")
            }
        }

        return freed
    }
}
