//
//  DictationAudioRetentionService.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import AVFoundation
import Foundation

/// Encodes float32 PCM dictation buffers to AAC `.m4a` under the managed DictationAudio area.
/// Preferred input is the native-rate copy kept by `AudioRecorder` (44.1/48 kHz) so retained
/// audio isn't telephone-bandwidth; the 16 kHz ASR feed remains the fallback. Sub-32 kHz
/// input is resampled to 44.1 kHz (Core Audio rejects MPEG-4 AAC at 16 kHz).
enum DictationAudioEncoder {
    /// Sample rate of the ASR-feed PCM from `AudioRecorder` (fallback input).
    static let inputSampleRate: Double = 16_000
    /// AAC-friendly output rate for low-rate input.
    static let outputSampleRate: Double = 44_100
    static let channelCount: AVAudioChannelCount = 1
    static let bitRate = 96_000

    /// AAC output rate for a given input: keep native rates the encoder accepts,
    /// resample only genuinely low-rate input.
    static func encodeSampleRate(forInputRate inputRate: Double) -> Double {
        inputRate >= 32_000 ? inputRate : outputSampleRate
    }

    static func encodePCMFloatData(
        _ audioData: Data,
        to destinationURL: URL,
        inputSampleRate: Double = inputSampleRate,
        channelCount: AVAudioChannelCount = channelCount
    ) throws {
        try Task.checkCancellation()

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

        // Resample only when the input rate isn't AAC-friendly (sub-32 kHz).
        let encodeRate = encodeSampleRate(forInputRate: inputSampleRate)
        let encodeBuffer: AVAudioPCMBuffer
        if abs(inputSampleRate - encodeRate) < 0.5 {
            encodeBuffer = inputBuffer
        } else {
            try Task.checkCancellation()
            encodeBuffer = try resample(inputBuffer, toSampleRate: encodeRate)
        }

        try Task.checkCancellation()
        try writeEncodeBuffer(
            encodeBuffer,
            to: destinationURL,
            channelCount: channelCount
        )
    }

    /// Streams a raw Float32 PCM spool into the AAC writer in small buffers so
    /// native capture never has to coexist with a second full-size Data value.
    static func encodePCMFloatFile(
        _ sourceURL: URL,
        to destinationURL: URL,
        inputSampleRate: Double,
        channelCount: AVAudioChannelCount = channelCount
    ) throws {
        try Task.checkCancellation()

        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputSampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            throw DictationAudioError.encodingFailed("Unable to prepare PCM format for AAC encode.")
        }
        let encodeRate = encodeSampleRate(forInputRate: inputSampleRate)
        let parent = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        // Stage into a unique temp file so cancellation / superseding work cannot
        // leave a half-written destination visible under the final media path.
        let stagingURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.deletingPathExtension().lastPathComponent).\(UUID().uuidString).tmp")
            .appendingPathExtension(destinationURL.pathExtension)
        defer {
            if FileManager.default.fileExists(atPath: stagingURL.path) {
                try? FileManager.default.removeItem(at: stagingURL)
            }
        }

        if FileManager.default.fileExists(atPath: stagingURL.path) {
            try FileManager.default.removeItem(at: stagingURL)
        }

        let outputFile = try AVAudioFile(
            forWriting: stagingURL,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: encodeRate,
                AVNumberOfChannelsKey: Int(channelCount),
                AVEncoderBitRateKey: bitRate
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let converter: AVAudioConverter?
        if abs(inputSampleRate - encodeRate) < 0.5 {
            converter = nil
        } else {
            guard let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: encodeRate,
                channels: channelCount,
                interleaved: false
            ) else {
                throw DictationAudioError.encodingFailed("Unable to create AAC resample format.")
            }
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        }

        let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? sourceHandle.close() }
        let framesPerChunk = 16_384
        var wroteFrames = false
        while true {
            try Task.checkCancellation()
            let data = sourceHandle.readData(ofLength: framesPerChunk * MemoryLayout<Float>.size)
            guard !data.isEmpty else { break }
            let frameCount = data.count / MemoryLayout<Float>.size
            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                frameCapacity: AVAudioFrameCount(frameCount)
            ), let channelData = inputBuffer.floatChannelData else {
                throw DictationAudioError.encodingFailed("Unable to prepare PCM chunk for AAC encode.")
            }
            inputBuffer.frameLength = AVAudioFrameCount(frameCount)
            data.withUnsafeBytes { rawBuffer in
                channelData[0].update(
                    from: rawBuffer.bindMemory(to: Float.self).baseAddress!,
                    count: frameCount
                )
            }
            if let converter {
                let outputCapacity = AVAudioFrameCount(Double(frameCount) * encodeRate / inputSampleRate) + 32
                guard let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: converter.outputFormat,
                    frameCapacity: outputCapacity
                ) else {
                    throw DictationAudioError.encodingFailed("Unable to prepare resample chunk for AAC encode.")
                }
                var consumed = false
                var conversionError: NSError?
                let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                    if consumed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    consumed = true
                    outStatus.pointee = .haveData
                    return inputBuffer
                }
                if let conversionError { throw DictationAudioError.encodingFailed(conversionError.localizedDescription) }
                guard status != .error else {
                    throw DictationAudioError.encodingFailed("Audio resampler failed.")
                }
                if outputBuffer.frameLength > 0 { try outputFile.write(from: outputBuffer) }
            } else {
                try outputFile.write(from: inputBuffer)
            }
            wroteFrames = true
        }
        guard wroteFrames else { throw DictationAudioError.emptyAudio }

        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: stagingURL, to: destinationURL)
    }

    private static func writeEncodeBuffer(
        _ encodeBuffer: AVAudioPCMBuffer,
        to destinationURL: URL,
        channelCount: AVAudioChannelCount
    ) throws {
        let parent = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let stagingURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.deletingPathExtension().lastPathComponent).\(UUID().uuidString).tmp")
            .appendingPathExtension(destinationURL.pathExtension)
        defer {
            if FileManager.default.fileExists(atPath: stagingURL.path) {
                try? FileManager.default.removeItem(at: stagingURL)
            }
        }

        if FileManager.default.fileExists(atPath: stagingURL.path) {
            try FileManager.default.removeItem(at: stagingURL)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: encodeBuffer.format.sampleRate,
            AVNumberOfChannelsKey: Int(channelCount),
            AVEncoderBitRateKey: bitRate
        ]

        do {
            let outputFile = try AVAudioFile(
                forWriting: stagingURL,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try outputFile.write(from: encodeBuffer)
        } catch {
            throw DictationAudioError.encodingFailed(error.localizedDescription)
        }

        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: stagingURL, to: destinationURL)
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

/// Owns the daily sweep `Timer` and in-flight maintenance `Task` so `deinit` can
/// tear them down without reading MainActor-isolated stored properties.
private final class DictationAudioRetentionResources: @unchecked Sendable {
    private let lock = NSLock()
    private var sweepTimer: Timer?
    private var maintenanceTask: Task<Void, Never>?

    /// Installs a new timer, invalidating any previous one. Idempotent if called
    /// repeatedly with successive timers.
    func installTimer(_ timer: Timer) {
        lock.lock()
        let previous = sweepTimer
        sweepTimer = timer
        lock.unlock()
        previous?.invalidate()
    }

    /// Invalidates and clears the sweep timer only.
    func clearTimer() {
        lock.lock()
        let previous = sweepTimer
        sweepTimer = nil
        lock.unlock()
        previous?.invalidate()
    }

    /// Replaces the in-flight maintenance task, cancelling any previous one.
    func replaceMaintenanceTask(_ task: Task<Void, Never>) {
        lock.lock()
        let previous = maintenanceTask
        maintenanceTask = task
        lock.unlock()
        previous?.cancel()
    }

    /// Idempotent: invalidate timer and cancel maintenance task.
    func tearDown() {
        lock.lock()
        let timer = sweepTimer
        let task = maintenanceTask
        sweepTimer = nil
        maintenanceTask = nil
        lock.unlock()
        timer?.invalidate()
        task?.cancel()
    }
}

/// Persists dictation audio off the insertion hot path, sweeps expired files, and
/// reports disk usage for the DictationAudio area. Applies only to `voiceRecording`.
@MainActor
final class DictationAudioRetentionService {
    static let sweepInterval: TimeInterval = 24 * 60 * 60
    /// Allow the daily timer to slip substantially so macOS can coalesce wake-ups.
    static let sweepTimerTolerance: TimeInterval = 60 * 60
    /// Main-context mutation batch size for async maintenance.
    static let maintenanceBatchSize = 32

    private struct PendingMediaDeletion: Sendable {
        let recordID: UUID
        let mediaPath: String
        let freedBytes: Int64
    }

    private let historyStore: HistoryStore
    private let settingsStore: SettingsStore
    private let fileManager: FileManager
    private let now: () -> Date
    private let directoryURL: URL
    /// Nonisolated resource ownership so `deinit` can release timer/task without
    /// touching MainActor-isolated stored properties.
    private let resources = DictationAudioRetentionResources()
    /// Generation counters let superseded persist tasks avoid clearing a newer slot.
    private var pendingPersistTasks: [UUID: (generation: UInt64, task: Task<Void, Never>)] = [:]
    private var persistGenerations: [UUID: UInt64] = [:]

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
        resources.tearDown()
    }

    // MARK: - Persistence (async, off hot path)

    /// Save the history record first, then call this with the captured PCM data.
    /// Encode + peaks run off the main actor; the record is updated when ready.
    /// When retention is `.off`, does nothing.
    func schedulePersist(
        pcmFloatData: Data,
        sampleRate: Double = DictationAudioEncoder.inputSampleRate,
        recordID: UUID
    ) {
        guard settingsStore.dictationAudioRetention != .off else {
            Log.audio.debug("Dictation audio persistence skipped (retention=off) record=\(recordID)")
            return
        }
        guard !pcmFloatData.isEmpty else {
            Log.audio.debug("Dictation audio persistence skipped (empty buffer) record=\(recordID)")
            return
        }

        let previous = pendingPersistTasks[recordID]
        previous?.task.cancel()

        let generation = (persistGenerations[recordID] ?? 0) &+ 1
        persistGenerations[recordID] = generation

        let destinationDirectory = directoryURL
        let audioData = pcmFloatData

        let ownedTask = Task { [weak self] in
            // Serialize superseding work: cancel then await the prior job so two
            // encodes cannot race on the same destination path.
            if let previous {
                await previous.task.value
            }
            guard !Task.isCancelled else {
                self?.clearPendingPersistTask(for: recordID, generation: generation)
                return
            }
            guard let self else { return }
            defer { self.clearPendingPersistTask(for: recordID, generation: generation) }

            do {
                let encodeTask = Task.detached(priority: .utility) {
                    try Task.checkCancellation()
                    return try Self.encodeAndWritePeaks(
                        pcmFloatData: audioData,
                        sampleRate: sampleRate,
                        recordID: recordID,
                        directoryURL: destinationDirectory
                    )
                }
                let mediaURL = try await withTaskCancellationHandler {
                    try await encodeTask.value
                } onCancel: {
                    encodeTask.cancel()
                }

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
            } catch is CancellationError {
                // Superseded or cancelled — nothing to report.
            } catch {
                Log.audio.error(
                    "Failed to persist dictation audio for \(recordID.uuidString): \(error.localizedDescription)"
                )
            }
        }

        pendingPersistTasks[recordID] = (generation: generation, task: ownedTask)
    }

    /// Ownership of `pcmFloatFileURL` transfers to this service. It is always
    /// removed after the background encoder finishes (or immediately when
    /// retention is disabled).
    func schedulePersist(
        pcmFloatFileURL: URL,
        sampleRate: Double,
        recordID: UUID
    ) {
        guard settingsStore.dictationAudioRetention != .off else {
            try? FileManager.default.removeItem(at: pcmFloatFileURL)
            return
        }

        let previous = pendingPersistTasks[recordID]
        previous?.task.cancel()

        let generation = (persistGenerations[recordID] ?? 0) &+ 1
        persistGenerations[recordID] = generation

        let destinationDirectory = directoryURL

        let ownedTask = Task { [weak self] in
            if let previous {
                await previous.task.value
            }
            defer { try? FileManager.default.removeItem(at: pcmFloatFileURL) }
            guard !Task.isCancelled else {
                self?.clearPendingPersistTask(for: recordID, generation: generation)
                return
            }
            guard let self else { return }
            defer { self.clearPendingPersistTask(for: recordID, generation: generation) }

            do {
                let encodeTask = Task.detached(priority: .utility) {
                    try Task.checkCancellation()
                    return try Self.encodeFileAndWritePeaks(
                        pcmFloatFileURL: pcmFloatFileURL,
                        sampleRate: sampleRate,
                        recordID: recordID,
                        directoryURL: destinationDirectory
                    )
                }
                let mediaURL = try await withTaskCancellationHandler {
                    try await encodeTask.value
                } onCancel: {
                    encodeTask.cancel()
                }
                guard !Task.isCancelled else {
                    Self.removeUnlinkedMedia(at: mediaURL)
                    return
                }
                if try self.historyStore.updateManagedMediaPath(for: recordID, path: mediaURL.path) {
                    Log.audio.info("Persisted dictation audio for \(recordID.uuidString) → \(mediaURL.lastPathComponent)")
                } else {
                    Self.removeUnlinkedMedia(at: mediaURL)
                }
            } catch is CancellationError {
                // Superseded or cancelled.
            } catch {
                Log.audio.error("Failed to persist dictation audio for \(recordID.uuidString): \(error.localizedDescription)")
            }
        }
        pendingPersistTasks[recordID] = (generation: generation, task: ownedTask)
    }

    /// Synchronous encode used by tests and the detached persistence path.
    nonisolated static func encodeAndWritePeaks(
        pcmFloatData: Data,
        sampleRate: Double = DictationAudioEncoder.inputSampleRate,
        recordID: UUID,
        directoryURL: URL
    ) throws -> URL {
        try Task.checkCancellation()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let mediaURL = directoryURL
            .appendingPathComponent(recordID.uuidString)
            .appendingPathExtension("m4a")

        do {
            try DictationAudioEncoder.encodePCMFloatData(
                pcmFloatData,
                to: mediaURL,
                inputSampleRate: sampleRate
            )

            try Task.checkCancellation()
            do {
                let peaks = try WaveformPeaks.extract(
                    fromPCMFloatData: pcmFloatData,
                    sampleRate: sampleRate
                )
                try Task.checkCancellation()
                try WaveformPeaks.writeSidecar(peaks, for: mediaURL)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Log.audio.warning(
                    "Waveform peaks extraction failed for \(recordID.uuidString): \(error.localizedDescription)"
                )
            }

            try Task.checkCancellation()
            return mediaURL
        } catch is CancellationError {
            removeUnlinkedMedia(at: mediaURL)
            throw CancellationError()
        }
    }

    nonisolated static func encodeFileAndWritePeaks(
        pcmFloatFileURL: URL,
        sampleRate: Double,
        recordID: UUID,
        directoryURL: URL
    ) throws -> URL {
        try Task.checkCancellation()
        let mediaURL = directoryURL
            .appendingPathComponent(recordID.uuidString)
            .appendingPathExtension("m4a")
        do {
            try DictationAudioEncoder.encodePCMFloatFile(
                pcmFloatFileURL,
                to: mediaURL,
                inputSampleRate: sampleRate
            )
            try Task.checkCancellation()
            do {
                let peaks = try WaveformPeaks.extract(
                    fromPCMFloatFile: pcmFloatFileURL,
                    sampleRate: sampleRate
                )
                try Task.checkCancellation()
                try WaveformPeaks.writeSidecar(peaks, for: mediaURL)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Log.audio.warning(
                    "Waveform peaks extraction failed for \(recordID.uuidString): \(error.localizedDescription)"
                )
            }
            try Task.checkCancellation()
            return mediaURL
        } catch is CancellationError {
            removeUnlinkedMedia(at: mediaURL)
            throw CancellationError()
        }
    }

    /// Removes a just-written media file and its peaks sidecar when they will never be linked.
    nonisolated static func removeUnlinkedMedia(at mediaURL: URL) {
        try? FileManager.default.removeItem(at: mediaURL)
        WaveformPeaks.removeSidecar(for: mediaURL)
    }

    // MARK: - Retention sweep

    /// Deletes expired dictation audio + peaks sidecars and clears `managedMediaPath`.
    /// Transcript text is preserved. Imported / media-backed records are never touched.
    ///
    /// Synchronous API retained for tests and explicit callers. Launch / timer paths use
    /// `performMaintenanceAsync()` so startup never blocks on filesystem deletion.
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
        var deletedCount = 0
        var freedBytes: Int64 = 0
        var clearedRecordIDs: [UUID] = []
        clearedRecordIDs.reserveCapacity(Self.maintenanceBatchSize)

        while true {
            let candidates = try historyStore.fetchExpiredDictationMediaCandidates(
                olderThan: cutoff,
                limit: Self.maintenanceBatchSize
            )
            if candidates.isEmpty { break }

            var batchIDs: [UUID] = []
            batchIDs.reserveCapacity(candidates.count)

            for candidate in candidates {
                batchIDs.append(candidate.recordID)
                guard !candidate.mediaPath.isEmpty else { continue }
                let mediaURL = URL(fileURLWithPath: candidate.mediaPath)
                freedBytes += removeAudioAndSidecar(at: mediaURL)
                deletedCount += 1
            }

            _ = try historyStore.clearManagedMediaPaths(for: batchIDs)
            clearedRecordIDs.append(contentsOf: batchIDs)

            // Defensive: if the store returned a full page of rows that could not be
            // cleared, stop rather than loop forever.
            if candidates.count < Self.maintenanceBatchSize { break }
            if batchIDs.isEmpty { break }
        }

        Log.audio.info(
            "Dictation audio retention sweep: deleted \(deletedCount) file(s), freed \(freedBytes) bytes (retention=\(retention.rawValue))"
        )
        return DictationAudioSweepResult(deletedCount: deletedCount, freedBytes: freedBytes)
    }

    /// Non-blocking maintenance used at launch and by the daily timer.
    /// Queries only expired eligible records, deletes files off-main, then applies
    /// model path clears in bounded main-context batches.
    @discardableResult
    func performMaintenanceAsync() async -> DictationAudioSweepResult {
        let retention = settingsStore.dictationAudioRetention
        guard let interval = retention.retentionInterval, interval > 0 else {
            if retention == .forever || retention == .off {
                Log.audio.debug("Dictation audio maintenance skipped (retention=\(retention.rawValue))")
            }
            return DictationAudioSweepResult(deletedCount: 0, freedBytes: 0)
        }

        let cutoff = now().addingTimeInterval(-interval)
        var deletedCount = 0
        var freedBytes: Int64 = 0

        do {
            while !Task.isCancelled {
                let candidates = try historyStore.fetchExpiredDictationMediaCandidates(
                    olderThan: cutoff,
                    limit: Self.maintenanceBatchSize
                )
                if candidates.isEmpty { break }

                // Detached deletes do not inherit cancellation. Await them fully,
                // clear model paths for every completed deletion, then decide
                // whether to continue the maintenance loop.
                let deleteTask = Task.detached(priority: .utility) { () -> [PendingMediaDeletion] in
                    var results: [PendingMediaDeletion] = []
                    results.reserveCapacity(candidates.count)
                    for candidate in candidates {
                        // Always clear the model path, even when the filesystem path is empty.
                        var freed: Int64 = 0
                        if !candidate.mediaPath.isEmpty {
                            let mediaURL = URL(fileURLWithPath: candidate.mediaPath)
                            freed = Self.removeAudioAndSidecarStatic(at: mediaURL)
                        }
                        results.append(
                            PendingMediaDeletion(
                                recordID: candidate.recordID,
                                mediaPath: candidate.mediaPath,
                                freedBytes: freed
                            )
                        )
                    }
                    return results
                }
                let deletions = await deleteTask.value

                if !deletions.isEmpty {
                    let recordIDs = deletions.map(\.recordID)
                    _ = try historyStore.clearManagedMediaPaths(for: recordIDs)
                    deletedCount += deletions.reduce(into: 0) { count, deletion in
                        if !deletion.mediaPath.isEmpty { count += 1 }
                    }
                    freedBytes += deletions.reduce(into: Int64(0)) { $0 += $1.freedBytes }
                }

                if Task.isCancelled { break }
                if candidates.count < Self.maintenanceBatchSize { break }
            }
        } catch is CancellationError {
            // Expected when a newer maintenance pass supersedes this one.
        } catch {
            Log.audio.error("Dictation audio maintenance failed: \(error.localizedDescription)")
        }

        if deletedCount > 0 {
            Log.audio.info(
                "Dictation audio retention maintenance: deleted \(deletedCount) file(s), freed \(freedBytes) bytes (retention=\(retention.rawValue))"
            )
        }
        return DictationAudioSweepResult(deletedCount: deletedCount, freedBytes: freedBytes)
    }

    /// Launch-time non-blocking sweep + optional 24h repeating timer for finite policies.
    /// Startup never waits for the sweep. Disabled/forever policies install no timer.
    func startPeriodicSweep() {
        scheduleMaintenance(runImmediately: true)
    }

    /// Install or tear down the daily timer and optionally kick an immediate async sweep
    /// when the retention policy changes.
    func applyRetentionPolicyChange() {
        scheduleMaintenance(runImmediately: true)
    }

    func stopPeriodicSweep() {
        resources.tearDown()
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

    private func scheduleMaintenance(runImmediately: Bool) {
        let retention = settingsStore.dictationAudioRetention
        let hasFiniteWindow = (retention.retentionInterval ?? 0) > 0

        resources.clearTimer()

        if hasFiniteWindow {
            let timer = Timer(
                timeInterval: Self.sweepInterval,
                repeats: true
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.kickMaintenancePass()
                }
            }
            timer.tolerance = Self.sweepTimerTolerance
            RunLoop.main.add(timer, forMode: .common)
            resources.installTimer(timer)
        }

        if runImmediately {
            if hasFiniteWindow {
                kickMaintenancePass()
            } else if retention == .forever || retention == .off {
                Log.audio.debug("Dictation audio periodic timer not installed (retention=\(retention.rawValue))")
            }
        }
    }

    private func kickMaintenancePass() {
        let task = Task { [weak self] in
            guard let self else { return }
            _ = await self.performMaintenanceAsync()
        }
        resources.replaceMaintenanceTask(task)
    }

    private func clearPendingPersistTask(for recordID: UUID, generation: UInt64) {
        guard pendingPersistTasks[recordID]?.generation == generation else { return }
        pendingPersistTasks[recordID] = nil
        if persistGenerations[recordID] == generation {
            persistGenerations[recordID] = nil
        }
    }

    @discardableResult
    private func removeAudioAndSidecar(at mediaURL: URL) -> Int64 {
        Self.removeAudioAndSidecarStatic(at: mediaURL, fileManager: fileManager)
    }

    nonisolated private static func removeAudioAndSidecarStatic(
        at mediaURL: URL,
        fileManager: FileManager = .default
    ) -> Int64 {
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
