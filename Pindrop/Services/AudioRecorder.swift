//
//  AudioRecorder.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import os.log

enum AudioRecordingMode: String, CaseIterable, Equatable, Sendable {
    case microphone
    case systemAudio
    case microphoneAndSystemAudio

    var requiresMicrophonePermission: Bool {
        switch self {
        case .microphone, .microphoneAndSystemAudio:
            return true
        case .systemAudio:
            return false
        }
    }

    var requiresSystemAudioPermission: Bool {
        switch self {
        case .microphone:
            return false
        case .systemAudio, .microphoneAndSystemAudio:
            return true
        }
    }
}

struct AudioRecordingConfiguration: Equatable, Sendable {
    var mode: AudioRecordingMode

    static let microphone = AudioRecordingConfiguration(mode: .microphone)
}

enum AudioRecorderError: Error, LocalizedError {
    case permissionDenied
    case systemAudioPermissionDenied
    case notRecording
    case engineStartFailed(String)
    case systemAudioCaptureFailed(String)
    case unsupportedCaptureMode(String)
    case audioFormatCreationFailed
    case recordingTooLong(maximumDuration: TimeInterval)
    /// A controlled signal: the valid ASR spool is full and must be finalized.
    case recordingLimitReached(maximumDuration: TimeInterval)
    case audioWriterBacklogExceeded
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .systemAudioPermissionDenied:
            return "System audio capture permission denied or unavailable"
        case .notRecording:
            return "Not currently recording"
        case .engineStartFailed(let message):
            return "Audio engine failed to start: \(message)"
        case .systemAudioCaptureFailed(let message):
            return "System audio capture failed: \(message)"
        case .unsupportedCaptureMode(let message):
            return message
        case .audioFormatCreationFailed:
            return "Failed to create audio format"
        case .recordingTooLong(let maximumDuration):
            return "Recording exceeded the maximum duration of \(Int(maximumDuration / 60)) minutes"
        case .recordingLimitReached(let maximumDuration):
            return "Recording reached the maximum duration of \(Int(maximumDuration / 60)) minutes and is being finalized"
        case .audioWriterBacklogExceeded:
            return "Audio capture could not keep up with disk writing"
        }
    }
}

// MARK: - AudioCaptureBackend Protocol

/// Native-rate mono PCM collected alongside the 16 kHz ASR feed. Retention encodes
/// this so kept audio isn't telephone-bandwidth (the target format exists for the
/// recognizer, not for listening).
final class AudioCaptureNativeAudio {
    private var fileURL: URL?
    let sampleRate: Double

    init(fileURL: URL, sampleRate: Double) {
        self.fileURL = fileURL
        self.sampleRate = sampleRate
    }

    /// Transfers the temporary PCM file to the retention encoder. The caller owns
    /// deletion after this returns a URL.
    func takeFileURL() -> URL? {
        defer { fileURL = nil }
        return fileURL
    }

    func discard() {
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
    }

    deinit { discard() }
}

struct AudioPCMFile {
    let fileURL: URL
    let byteCount: Int
    let sampleRate: Double

    func consumeData(maximumByteCount: Int) throws -> Data {
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard byteCount <= maximumByteCount else {
            throw AudioRecorderError.recordingTooLong(
                maximumDuration: Double(maximumByteCount) / Double(16_000 * MemoryLayout<Float>.size)
            )
        }
        return try Data(contentsOf: fileURL)
    }

    func discard() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// Abstracts audio capture hardware, enabling mock-based testing.
protocol AudioCaptureBackend: AnyObject {
    var isCapturing: Bool { get }
    var targetFormat: AVAudioFormat { get }
    /// When true, capture also accumulates buffers at the device's native sample
    /// rate for retention-quality encoding. Set before `startCapture`.
    var retainsNativeAudio: Bool { get set }

    func startCapture(
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onAudioLevel: @escaping (Float) -> Void,
        onError: @escaping (Error) -> Void
    ) throws
    /// Stops capture and returns the file-backed 16 kHz mono Float32 PCM spool.
    func stopCapture() throws -> AudioPCMFile
    /// Drains the native-rate copy collected during the last capture, if enabled.
    func collectNativeAudio() -> AudioCaptureNativeAudio?
    func cancelCapture()
    func reset()
    func setPreferredInputDeviceUID(_ uid: String) throws
}

extension AudioCaptureBackend {
    // Backends that never feed retention (system-audio tap, test mocks) opt out.
    var retainsNativeAudio: Bool {
        get { false }
        set {}
    }

    func collectNativeAudio() -> AudioCaptureNativeAudio? { nil }
}

private enum AudioCaptureUtilities {
    static func makeTargetFormat() throws -> AVAudioFormat {
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: 16000.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw AudioRecorderError.audioFormatCreationFailed
        }
        guard format.sampleRate > 0, format.channelCount > 0, format.commonFormat == .pcmFormatFloat32 else {
            throw AudioRecorderError.audioFormatCreationFailed
        }
        return format
    }

    static func fallbackFormat() -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: 16000.0, channels: 1) ?? AVAudioFormat()
    }

    /// One-shot conversion helper for ad-hoc call sites. Hot capture paths keep a
    /// `ReusableAudioConverter` and reuse converter/output-buffer state across buffers.
    static func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        from inputFormat: AVAudioFormat,
        to outputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        ReusableAudioConverter().convert(buffer, from: inputFormat, to: outputFormat)
    }

    static func formatsEquivalent(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }
}

/// Serial conversion cache for a single capture callback context. Rebuilds the
/// `AVAudioConverter` only when source/target formats change, reuses a single
/// input-state flag, and keeps a small free-list of output buffers that have not
/// been published to streaming or spool consumers.
private final class ReusableAudioConverter {
    private final class InputState {
        var buffer: AVAudioPCMBuffer?
        var consumed = false
    }

    private var converter: AVAudioConverter?
    private var cachedInputFormat: AVAudioFormat?
    private var cachedOutputFormat: AVAudioFormat?
    private let inputState = InputState()
    /// Only holds buffers still owned by this converter (failed converts / unused).
    /// Once a buffer is returned to a caller it is never mutated or recycled here.
    private var freeOutputBuffers: [AVAudioPCMBuffer] = []
    private let maxPooledBuffers = 4

    func convert(
        _ buffer: AVAudioPCMBuffer,
        from inputFormat: AVAudioFormat,
        to outputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        if !matchesCachedFormats(input: inputFormat, output: outputFormat) {
            rebuild(from: inputFormat, to: outputFormat)
        }
        guard let converter else {
            Log.audio.error("Failed to create audio converter")
            return nil
        }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let convertedBuffer = makeOutputBuffer(capacity: capacity, format: outputFormat) else {
            Log.audio.error("Failed to create output buffer")
            return nil
        }

        inputState.buffer = buffer
        inputState.consumed = false
        defer {
            inputState.buffer = nil
            inputState.consumed = false
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { [inputState] _, outStatus in
            if inputState.consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputState.consumed = true
            outStatus.pointee = .haveData
            return inputState.buffer
        }

        let status = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if let error {
            Log.audio.error("Conversion error: \(error)")
            recycle(convertedBuffer)
            return nil
        }

        if status == .error {
            Log.audio.error("Conversion status error")
            recycle(convertedBuffer)
            return nil
        }

        // Ownership transfers to the caller; do not recycle while consumers may retain it.
        return convertedBuffer
    }

    func reset() {
        converter = nil
        cachedInputFormat = nil
        cachedOutputFormat = nil
        freeOutputBuffers.removeAll(keepingCapacity: false)
        inputState.buffer = nil
        inputState.consumed = false
    }

    private func rebuild(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) {
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        cachedInputFormat = inputFormat
        cachedOutputFormat = outputFormat
        // Drop pool entries that belong to the previous format pair.
        freeOutputBuffers.removeAll(keepingCapacity: false)
    }

    private func matchesCachedFormats(input: AVAudioFormat, output: AVAudioFormat) -> Bool {
        guard let cachedInputFormat, let cachedOutputFormat, converter != nil else { return false }
        return AudioCaptureUtilities.formatsEquivalent(cachedInputFormat, input)
            && AudioCaptureUtilities.formatsEquivalent(cachedOutputFormat, output)
    }

    private func makeOutputBuffer(capacity: AVAudioFrameCount, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if let index = freeOutputBuffers.firstIndex(where: {
            $0.frameCapacity >= capacity && AudioCaptureUtilities.formatsEquivalent($0.format, format)
        }) {
            let buffer = freeOutputBuffers.remove(at: index)
            buffer.frameLength = 0
            return buffer
        }
        return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
    }

    private func recycle(_ buffer: AVAudioPCMBuffer) {
        guard freeOutputBuffers.count < maxPooledBuffers else { return }
        buffer.frameLength = 0
        freeOutputBuffers.append(buffer)
    }
}

extension AudioCaptureUtilities {

    static func calculateAudioLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        let audioBufferList = buffer.audioBufferList.pointee
        let bufferCount = Int(audioBufferList.mNumberBuffers)
        guard bufferCount > 0 else { return 0 }

        var sum: Float = 0
        var sampleCount: Int = 0

        withUnsafePointer(to: audioBufferList.mBuffers) { buffersPointer in
            let buffers = UnsafeBufferPointer(start: buffersPointer, count: bufferCount)
            switch buffer.format.commonFormat {
            case .pcmFormatFloat32:
                for audioBuffer in buffers {
                    let dataByteSize = Int(audioBuffer.mDataByteSize)
                    guard dataByteSize > 0, let data = audioBuffer.mData else { continue }
                    let count = dataByteSize / MemoryLayout<Float>.size
                    let bufferPointer = data.bindMemory(to: Float.self, capacity: count)
                    for index in 0..<count {
                        let sample = bufferPointer[index]
                        sum += sample * sample
                    }
                    sampleCount += count
                }
            case .pcmFormatInt16:
                for audioBuffer in buffers {
                    let dataByteSize = Int(audioBuffer.mDataByteSize)
                    guard dataByteSize > 0, let data = audioBuffer.mData else { continue }
                    let count = dataByteSize / MemoryLayout<Int16>.size
                    let bufferPointer = data.bindMemory(to: Int16.self, capacity: count)
                    for index in 0..<count {
                        let floatSample = Float(bufferPointer[index]) / Float(Int16.max)
                        sum += floatSample * floatSample
                    }
                    sampleCount += count
                }
            default:
                break
            }
        }

        guard sampleCount > 0 else { return 0 }
        let rms = sqrt(sum / Float(sampleCount))
        return min(1.0 as Float, rms * 15)
    }

    static func data(from buffer: AVAudioPCMBuffer) -> Data? {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              buffer.format.channelCount == 1,
              let channelData = buffer.floatChannelData else {
            return nil
        }
        return Data(bytes: channelData[0], count: Int(buffer.frameLength) * MemoryLayout<Float>.size)
    }

    /// Mixes source spools in fixed 64 KiB chunks. Stop never holds both source
    /// recordings and the mixed output in memory at the same time.
    static func mixPCMFiles(_ microphone: AudioPCMFile, _ system: AudioPCMFile) throws -> AudioPCMFile {
        defer {
            microphone.discard()
            system.discard()
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pindrop-mixed-audio-\(UUID().uuidString).pcm")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            throw AudioRecorderError.engineStartFailed("Unable to create mixed audio spool")
        }
        do {
            let microphoneHandle = try FileHandle(forReadingFrom: microphone.fileURL)
            let systemHandle = try FileHandle(forReadingFrom: system.fileURL)
            let outputHandle = try FileHandle(forWritingTo: outputURL)
            defer {
                try? microphoneHandle.close()
                try? systemHandle.close()
                try? outputHandle.close()
            }

            let chunkByteCount = 64 * 1024
            var outputByteCount = 0
            while true {
                let microphoneChunk = microphoneHandle.readData(ofLength: chunkByteCount)
                let systemChunk = systemHandle.readData(ofLength: chunkByteCount)
                guard !microphoneChunk.isEmpty || !systemChunk.isEmpty else { break }

                let microphoneSampleCount = microphoneChunk.count / MemoryLayout<Float>.size
                let systemSampleCount = systemChunk.count / MemoryLayout<Float>.size
                let mixedSampleCount = max(microphoneSampleCount, systemSampleCount)
                var mixedChunk = Data(count: mixedSampleCount * MemoryLayout<Float>.size)
                mixedChunk.withUnsafeMutableBytes { destination in
                    let destinationSamples = destination.bindMemory(to: Float.self)
                    microphoneChunk.withUnsafeBytes { microphoneBytes in
                        let microphoneSamples = microphoneBytes.bindMemory(to: Float.self)
                        systemChunk.withUnsafeBytes { systemBytes in
                            let systemSamples = systemBytes.bindMemory(to: Float.self)
                            for index in 0..<mixedSampleCount {
                                let microphoneSample = index < microphoneSamples.count ? microphoneSamples[index] : 0
                                let systemSample = index < systemSamples.count ? systemSamples[index] : 0
                                destinationSamples[index] = max(-1, min(1, (microphoneSample + systemSample) * 0.5))
                            }
                        }
                    }
                }
                try outputHandle.write(contentsOf: mixedChunk)
                outputByteCount += mixedChunk.count
            }
            return AudioPCMFile(
                fileURL: outputURL,
                byteCount: outputByteCount,
                sampleRate: microphone.sampleRate
            )
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }
}

private enum CaptureLimits {
    /// Batch inference currently accepts one contiguous Data value. Keep that
    /// materialization below 40 MB (ten minutes of 16 kHz mono Float32 PCM).
    static let maximumASRDuration: TimeInterval = 10 * 60
    static let maximumASRByteCount = Int(maximumASRDuration * 16_000 * Double(MemoryLayout<Float>.size))
}

// MARK: - AVAudioEngineCaptureBackend

/// File-backed PCM spool with a bounded, non-blocking handoff from the capture
/// callback to one serial writer. Capture never waits for a lock or filesystem
/// operation: if all handoff permits are in use, the backend fails the recording
/// rather than silently dropping samples.
final class AudioPCMFileStorage: @unchecked Sendable {
    private static let writerQueueSpecificKey = DispatchSpecificKey<UUID>()
    private final class PCMStorageSlab: @unchecked Sendable {
        let capacity: Int
        let storage: UnsafeMutableRawPointer
        let availability = DispatchSemaphore(value: 1)
        var byteCount = 0
        var sampleRate: Double = 0

        init(capacity: Int) {
            self.capacity = capacity
            self.storage = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: MemoryLayout<Float>.alignment)
        }

        deinit { storage.deallocate() }

        /// Called by the capture callback after nonblocking acquisition. It only
        /// copies samples into memory allocated when the storage was created.
        func copy(from buffer: AVAudioPCMBuffer) -> Bool {
            guard buffer.format.commonFormat == .pcmFormatFloat32,
                  buffer.format.channelCount == 1,
                  let channelData = buffer.floatChannelData else {
                return false
            }
            let bytes = Int(buffer.frameLength) * MemoryLayout<Float>.size
            guard bytes > 0, bytes <= capacity else { return false }
            storage.copyMemory(from: channelData[0], byteCount: bytes)
            byteCount = bytes
            sampleRate = buffer.format.sampleRate
            return true
        }
    }

    private var fileURL: URL?
    private var fileHandle: FileHandle?
    private var sampleRate: Double?
    private var byteCount = 0
    private var writeFailure: Error?
    private var onWriteFailure: ((Error) -> Void)?
    private var onLimitReached: ((TimeInterval) -> Void)?
    private var limitReached = false
    private let writerQueue = DispatchQueue(label: "tech.watzon.pindrop.audio-pcm-writer")
    private let writerQueueIdentifier = UUID()
    private let slabs: [PCMStorageSlab]
    /// Preallocated SPSC FIFO. The capture callback is its only producer and the
    /// serial writer source is its only consumer; slab permits cap occupancy.
    private let readySlabIndices: UnsafeMutablePointer<Int>
    private var producedSequence: UInt64 = 0
    private var consumedSequence: UInt64 = 0
    private var readySource: DispatchSourceUserDataAdd!
    /// Accessed only by `writerQueue`; set before close/reset so queued tokens
    /// recycle their slabs without touching a retired spool.
    private var isDiscarded = false
    private let maximumByteCount: Int?
    private let writerDelayNanoseconds: UInt64

    init(
        pendingWriteLimit: Int = 32,
        maximumByteCount: Int? = nil,
        writerDelayNanoseconds: UInt64 = 0,
        slabByteCapacity: Int = 64 * 1024
    ) {
        let slabs = (0..<max(1, pendingWriteLimit)).map { _ in
            PCMStorageSlab(capacity: max(MemoryLayout<Float>.size, slabByteCapacity))
        }
        self.slabs = slabs
        self.readySlabIndices = UnsafeMutablePointer<Int>.allocate(capacity: slabs.count)
        self.maximumByteCount = maximumByteCount
        self.writerDelayNanoseconds = writerDelayNanoseconds
        writerQueue.setSpecific(key: Self.writerQueueSpecificKey, value: writerQueueIdentifier)
        let source = DispatchSource.makeUserDataAddSource(queue: writerQueue)
        source.setEventHandler { [weak self] in self?.drainReadySlabs() }
        source.resume()
        self.readySource = source
    }

    deinit {
        discard()
        readySource.cancel()
        readySlabIndices.deallocate()
    }

    func start(
        onWriteFailure: @escaping (Error) -> Void = { _ in },
        onLimitReached: @escaping (TimeInterval) -> Void = { _ in }
    ) throws {
        try writerQueue.sync {
            closeAndRemoveFile()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("pindrop-audio-\(UUID().uuidString).pcm")
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw AudioRecorderError.engineStartFailed("Unable to create temporary audio spool")
            }
            do {
                fileHandle = try FileHandle(forWritingTo: url)
            } catch {
                try? FileManager.default.removeItem(at: url)
                throw AudioRecorderError.engineStartFailed("Unable to create temporary audio spool")
            }
            fileURL = url
            sampleRate = nil
            byteCount = 0
            writeFailure = nil
            self.onWriteFailure = onWriteFailure
            self.onLimitReached = onLimitReached
            limitReached = false
            isDiscarded = false
        }
    }

    /// Acquires one of the preallocated slabs without blocking, copies samples,
    /// and hands its token to the serial writer. No callback-time heap allocation
    /// or filesystem operation occurs; full/oversized pools report overflow.
    func enqueue(_ buffer: AVAudioPCMBuffer) -> Bool {
        var acquiredIndex: Int?
        for index in slabs.indices where slabs[index].availability.wait(timeout: .now()) == .success {
            acquiredIndex = index
            break
        }
        guard let index = acquiredIndex else {
            return false
        }
        let slab = slabs[index]
        guard slab.copy(from: buffer) else {
            slab.availability.signal()
            return false
        }
        let slot = Int(producedSequence % UInt64(slabs.count))
        readySlabIndices[slot] = index
        producedSequence &+= 1
        // Dispatch source notification publishes this completed token to the
        // single writer; producer/consumer counters are never cross-thread read.
        readySource.add(data: 1)
        return true
    }

    /// Waits for the serial writer after the hardware callback has stopped, then
    /// transfers ownership of the completed temporary file to the caller.
    func finish() throws -> AudioPCMFile? {
        try withDrainedSlabs {
            try writerQueue.sync {
            if let writeFailure {
                closeAndRemoveFile()
                isDiscarded = true
                throw writeFailure
            }
            guard let fileURL, let sampleRate else {
                closeAndRemoveFile()
                byteCount = 0
                isDiscarded = true
                return nil
            }
            do {
                try fileHandle?.close()
            } catch {
                closeAndRemoveFile()
                throw error
            }
            fileHandle = nil
            self.fileURL = nil
            self.sampleRate = nil
            let result = AudioPCMFile(fileURL: fileURL, byteCount: byteCount, sampleRate: sampleRate)
            byteCount = 0
            isDiscarded = true
            return result
            }
        }
    }

    func discard() {
        if isOnWriterQueue {
            discardOnWriterQueue()
            return
        }
        withDrainedSlabs {
            writerQueue.sync {
                discardOnWriterQueue()
            }
        }
    }

    /// Runs only on `writerQueue`. One source drains the FIFO in capture order,
    /// then recycles each slab after its file write completes.
    private func drainReadySlabs() {
        let readyCount = Int(readySource.data)
        for _ in 0..<readyCount {
            let slot = Int(consumedSequence % UInt64(slabs.count))
            let slabIndex = readySlabIndices[slot]
            consumedSequence &+= 1
            write(slabs[slabIndex])
        }
    }

    private func write(_ slab: PCMStorageSlab) {
        defer { slab.availability.signal() }
        guard !isDiscarded, writeFailure == nil, !limitReached else { return }
        if let maximumByteCount, byteCount + slab.byteCount > maximumByteCount {
            limitReached = true
            onLimitReached?(Double(maximumByteCount) / Double(16_000 * MemoryLayout<Float>.size))
            return
        }
        do {
            if writerDelayNanoseconds > 0 {
                Thread.sleep(forTimeInterval: Double(writerDelayNanoseconds) / 1_000_000_000)
            }
            guard let fileHandle else {
                throw AudioRecorderError.engineStartFailed("Audio spool is not available")
            }
            let data = Data(bytesNoCopy: slab.storage, count: slab.byteCount, deallocator: .none)
            try fileHandle.write(contentsOf: data)
            byteCount += slab.byteCount
            if sampleRate == nil { sampleRate = slab.sampleRate }
        } catch {
            recordWriteFailure(error)
        }
    }

    private func withDrainedSlabs<T>(_ operation: () throws -> T) rethrows -> T {
        for slab in slabs { slab.availability.wait() }
        defer { for slab in slabs { slab.availability.signal() } }
        return try operation()
    }

    private var isOnWriterQueue: Bool {
        DispatchQueue.getSpecific(key: Self.writerQueueSpecificKey) == writerQueueIdentifier
    }

    /// Must run on `writerQueue`. The guard makes direct writer-queue cleanup and
    /// repeated teardown idempotent without synchronously re-entering that queue.
    private func discardOnWriterQueue() {
        guard !isDiscarded else { return }
        isDiscarded = true
        closeAndRemoveFile()
        sampleRate = nil
        byteCount = 0
        writeFailure = nil
        onWriteFailure = nil
        onLimitReached = nil
        limitReached = false
    }

    private func recordWriteFailure(_ error: Error) {
        guard writeFailure == nil else { return }
        writeFailure = error
        onWriteFailure?(error)
    }

    private func closeAndRemoveFile() {
        try? fileHandle?.close()
        fileHandle = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
    }
}

final class AVAudioEngineCaptureBackend: AudioCaptureBackend {
    
    private var audioEngine: AVAudioEngine?
    private let audioStorage = AudioPCMFileStorage(maximumByteCount: CaptureLimits.maximumASRByteCount)
    /// Native-rate mono copy for retention (tap format), kept only when enabled.
    private let nativeAudioStorage = AudioPCMFileStorage()
    /// Reused across tap callbacks; rebuilt when the engine reinstalls a tap with a new format.
    private let audioConverter = ReusableAudioConverter()
    var retainsNativeAudio = false
    private var preferredInputDeviceUID: String?
    private var configurationChangeObserver: NSObjectProtocol?
    private var onBufferCallback: ((AVAudioPCMBuffer) -> Void)?
    private var onAudioLevelCallback: ((Float) -> Void)?
    private var onErrorCallback: ((Error) -> Void)?
    private var isRestartingCapture = false
    private var pendingConfigurationRestartWorkItem: DispatchWorkItem?
    private var suppressConfigurationChangesUntil: Date?
    
    private(set) var isCapturing = false
    
    private let targetFormatStorage: AVAudioFormat
    var targetFormat: AVAudioFormat {
        if targetFormatStorage.sampleRate == 0 ||
            targetFormatStorage.channelCount == 0 ||
            targetFormatStorage.commonFormat != .pcmFormatFloat32 {
            return Self.makeFallbackFormat()
        }
        return targetFormatStorage
    }
    
    init() throws {
        self.targetFormatStorage = try AudioCaptureUtilities.makeTargetFormat()
    }

    deinit {
        removeConfigurationChangeObserver()
    }
    
    func startCapture(
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onAudioLevel: @escaping (Float) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        self.onBufferCallback = onBuffer
        self.onAudioLevelCallback = onAudioLevel
        self.onErrorCallback = onError
        do {
            try audioStorage.start(
                onWriteFailure: onError,
                onLimitReached: { onError(AudioRecorderError.recordingLimitReached(maximumDuration: $0)) }
            )
            if retainsNativeAudio {
                try nativeAudioStorage.start(onWriteFailure: onError)
            } else {
                nativeAudioStorage.discard()
            }
        } catch {
            audioStorage.discard()
            nativeAudioStorage.discard()
            throw error
        }
        removeConfigurationChangeObserver()
        
        do {
            var engine = try startFreshEngine()
            if !verifyPinnedDevice(on: engine) {
                Log.audio.error("Retrying audio capture with a fresh engine because the pinned input device was not honored")
                tearDownEngine(engine)
                self.audioEngine = nil

                engine = try startFreshEngine()
                if !verifyPinnedDevice(on: engine) {
                    Log.audio.error("Pinned input device was not honored after retry; continuing with the engine's current input device")
                }
            }

            isCapturing = true
            Log.audio.info("Audio engine started")
        } catch {
            if let engine = audioEngine {
                tearDownEngine(engine)
                self.audioEngine = nil
            }
            onBufferCallback = nil
            onAudioLevelCallback = nil
            onErrorCallback = nil
            audioStorage.discard()
            nativeAudioStorage.discard()
            throw AudioRecorderError.engineStartFailed(error.localizedDescription)
        }
    }
    
    func stopCapture() throws -> AudioPCMFile {
        guard isCapturing, let engine = audioEngine else {
            throw AudioRecorderError.notRecording
        }
        
        tearDownEngine(engine)
        isCapturing = false
        self.audioEngine = nil
        onBufferCallback = nil
        onAudioLevelCallback = nil
        onErrorCallback = nil
        isRestartingCapture = false
        cancelPendingConfigurationRestart()
        suppressConfigurationChangesUntil = nil
        audioConverter.reset()
        
        guard let capturedAudio = try audioStorage.finish() else {
            throw AudioRecorderError.notRecording
        }
        Log.audio.debug("Stopped capturing, collected \(capturedAudio.byteCount) bytes")
        return capturedAudio
    }
    
    func cancelCapture() {
        guard isCapturing, let engine = audioEngine else {
            return
        }
        
        tearDownEngine(engine)
        isCapturing = false
        self.audioEngine = nil
        onBufferCallback = nil
        onAudioLevelCallback = nil
        onErrorCallback = nil
        isRestartingCapture = false
        cancelPendingConfigurationRestart()
        suppressConfigurationChangesUntil = nil
        audioConverter.reset()
        audioStorage.discard()
        nativeAudioStorage.discard()

        Log.audio.info("Capture cancelled, audio discarded")
    }

    func collectNativeAudio() -> AudioCaptureNativeAudio? {
        guard let capturedAudio = try? nativeAudioStorage.finish(), capturedAudio.byteCount > 0 else { return nil }
        return AudioCaptureNativeAudio(fileURL: capturedAudio.fileURL, sampleRate: capturedAudio.sampleRate)
    }

    func reset() {
        if let engine = audioEngine {
            tearDownEngine(engine)
        }
        audioEngine = nil
        removeConfigurationChangeObserver()
        isCapturing = false
        onBufferCallback = nil
        onAudioLevelCallback = nil
        onErrorCallback = nil
        isRestartingCapture = false
        cancelPendingConfigurationRestart()
        suppressConfigurationChangesUntil = nil
        audioConverter.reset()
        audioStorage.discard()
        nativeAudioStorage.discard()
        Log.audio.info("Audio engine reset")
    }
    
    func setPreferredInputDeviceUID(_ uid: String) throws {
        let trimmedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUID = trimmedUID.isEmpty ? nil : trimmedUID
        guard preferredInputDeviceUID != normalizedUID else {
            Log.audio.debug("Preferred input device unchanged; no capture restart needed")
            return
        }

        preferredInputDeviceUID = normalizedUID

        guard let engine = audioEngine, isCapturing else { return }
        guard !isRestartingCapture else { return }

        isRestartingCapture = true
        suppressConfigurationChanges()
        Log.audio.info("Preferred input device changed during capture; restarting audio engine")
        engine.stop()
        restartCapture(engine, attempt: 1)
    }
    
    // MARK: - Private Helpers
    
    private static func makeFallbackFormat() -> AVAudioFormat {
        AudioCaptureUtilities.fallbackFormat()
    }

    private func registerConfigurationChangeObserver(for engine: AVAudioEngine) {
        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self, weak engine] _ in
            guard let self, let engine else { return }
            self.handleEngineConfigurationChange(for: engine)
        }
    }

    private func removeConfigurationChangeObserver() {
        guard let configurationChangeObserver else { return }
        NotificationCenter.default.removeObserver(configurationChangeObserver)
        self.configurationChangeObserver = nil
    }

    private func tearDownEngine(_ engine: AVAudioEngine) {
        removeConfigurationChangeObserver()
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }

        // Work around an AVFAudio teardown race observed on macOS 26.4:
        // AVAudioIOUnit can still be processing device changes after stop().
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            _ = engine
        }
    }

    private func handleEngineConfigurationChange(for engine: AVAudioEngine) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCapturing, self.audioEngine === engine else { return }
            guard !self.isRestartingCapture else { return }
            Log.audio.debug("Audio engine configuration changed; isRunning=\(engine.isRunning)")
            if self.isSuppressingConfigurationChanges {
                Log.audio.debug("Configuration change from recent input reconfiguration; no restart needed")
                if !engine.isRunning {
                    self.scheduleConfigurationRestart(for: engine, delay: self.configurationSuppressionRemaining + 0.2)
                }
                return
            }
            guard !engine.isRunning else {
                Log.audio.debug("Configuration change with engine still running; no restart needed")
                return
            }

            self.scheduleConfigurationRestart(for: engine, delay: 0.5)
        }
    }

    private func startFreshEngine() throws -> AVAudioEngine {
        let engine = AVAudioEngine()
        self.audioEngine = engine
        registerConfigurationChangeObserver(for: engine)

        installInputTap(on: engine)
        engine.prepare()
        try engine.start()
        suppressConfigurationChanges()
        logStartedEngineState(engine, context: "Audio engine started")
        return engine
    }

    private func installInputTap(on engine: AVAudioEngine) {
        let inputNode = engine.inputNode
        applyPreferredInputDevice(to: inputNode)
        let nodeFormat = inputNode.inputFormat(forBus: 0)
        let preferredDeviceID = preferredInputDeviceID()
        let nominalSampleRate = preferredDeviceID.flatMap(AudioDeviceManager.nominalSampleRate)
        let tapSampleRate: Double
        if let nominalSampleRate,
           abs(nodeFormat.sampleRate - nominalSampleRate) > 1.0 {
            tapSampleRate = nominalSampleRate
            Log.audio.warning(
                "Input node sample rate \(nodeFormat.sampleRate) differs from preferred device nominal sample rate \(nominalSampleRate); using nominal rate for tap"
            )
        } else {
            tapSampleRate = nodeFormat.sampleRate
        }
        let tapFormat = AVAudioFormat(
            standardFormatWithSampleRate: tapSampleRate,
            channels: 1
        ) ?? nodeFormat

        Log.audio.debug("Input format: \(nodeFormat)")
        Log.audio.debug("Tap format: \(tapFormat)")

        let audioStorage = self.audioStorage
        let targetFmt = self.targetFormat
        let audioConverter = self.audioConverter
        audioConverter.reset()

        let nativeAudioStorage = self.nativeAudioStorage
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }

            if self.retainsNativeAudio {
                // The tap format is already native-rate mono float32.
                if !nativeAudioStorage.enqueue(buffer) {
                    self.onErrorCallback?(AudioRecorderError.audioWriterBacklogExceeded)
                    return
                }
            }

            if let convertedBuffer = audioConverter.convert(buffer, from: buffer.format, to: targetFmt) {
                if !audioStorage.enqueue(convertedBuffer) {
                    self.onErrorCallback?(AudioRecorderError.audioWriterBacklogExceeded)
                    return
                }
                self.onBufferCallback?(convertedBuffer)
            }

            self.onAudioLevelCallback?(AudioCaptureUtilities.calculateAudioLevel(buffer))
        }
    }

    private func restartCapture(_ engine: AVAudioEngine, attempt: Int) {
        cancelPendingConfigurationRestart()
        engine.inputNode.removeTap(onBus: 0)
        installInputTap(on: engine)
        engine.prepare()

        do {
            try engine.start()
            logStartedEngineState(engine, context: "Audio engine restarted")
            _ = verifyPinnedDevice(on: engine)
            suppressConfigurationChanges()
            isRestartingCapture = false
            Log.audio.info("Audio engine restarted after configuration change")
        } catch {
            guard attempt < 3 else {
                isRestartingCapture = false
                Log.audio.error("Audio engine restart failed after \(attempt) attempts: \(error.localizedDescription)")
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.isCapturing, self.audioEngine === engine else {
                    self?.isRestartingCapture = false
                    return
                }

                self.restartCapture(engine, attempt: attempt + 1)
            }
        }
    }

    private func preferredInputDeviceID() -> AudioDeviceID? {
        guard let preferredUID = preferredInputDeviceUID else { return nil }
        return AudioDeviceManager.inputDeviceID(for: preferredUID)
    }

    private var isSuppressingConfigurationChanges: Bool {
        guard let suppressConfigurationChangesUntil else { return false }
        return Date() < suppressConfigurationChangesUntil
    }

    private var configurationSuppressionRemaining: TimeInterval {
        guard let suppressConfigurationChangesUntil else { return 0 }
        return max(0, suppressConfigurationChangesUntil.timeIntervalSinceNow)
    }

    private func suppressConfigurationChanges() {
        suppressConfigurationChangesUntil = Date().addingTimeInterval(2.0)
    }

    private func cancelPendingConfigurationRestart() {
        pendingConfigurationRestartWorkItem?.cancel()
        pendingConfigurationRestartWorkItem = nil
    }

    private func scheduleConfigurationRestart(for engine: AVAudioEngine, delay: TimeInterval) {
        cancelPendingConfigurationRestart()

        let workItem = DispatchWorkItem { [weak self, weak engine] in
            guard let self, let engine else { return }
            guard self.isCapturing, self.audioEngine === engine else { return }
            guard !self.isRestartingCapture else { return }

            if self.isSuppressingConfigurationChanges {
                self.scheduleConfigurationRestart(for: engine, delay: self.configurationSuppressionRemaining + 0.2)
                return
            }

            guard !engine.isRunning else {
                Log.audio.debug("Deferred configuration restart skipped because engine resumed")
                self.pendingConfigurationRestartWorkItem = nil
                return
            }

            self.pendingConfigurationRestartWorkItem = nil
            self.isRestartingCapture = true
            Log.audio.info("Audio engine remains stopped after configuration change; restarting capture")
            self.restartCapture(engine, attempt: 1)
        }

        pendingConfigurationRestartWorkItem = workItem
        Log.audio.debug("Audio engine stopped after configuration change; scheduling deferred restart")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func verifyPinnedDevice(on engine: AVAudioEngine) -> Bool {
        guard let preferredUID = preferredInputDeviceUID,
              let wantedID = AudioDeviceManager.inputDeviceID(for: preferredUID) else {
            return true
        }

        let actualID = engine.inputNode.auAudioUnit.deviceID
        if actualID != wantedID {
            Log.audio.error("Pinned input device not honored (wanted \(wantedID), engine is using \(actualID))")
            return false
        }

        return true
    }

    private func logStartedEngineState(_ engine: AVAudioEngine, context: String) {
        let inputNode = engine.inputNode
        let actualID = inputNode.auAudioUnit.deviceID
        let inputFormat = inputNode.inputFormat(forBus: 0)

        if let preferredDeviceID = preferredInputDeviceID() {
            let nominalSampleRate = AudioDeviceManager.nominalSampleRate(preferredDeviceID)
            let nominalSampleRateDescription = nominalSampleRate.map { String($0) } ?? "unknown"
            Log.audio.debug(
                "\(context): inputDeviceID=\(actualID), inputFormat=\(inputFormat), preferredNominalSampleRate=\(nominalSampleRateDescription)"
            )
        } else {
            Log.audio.debug("\(context): inputDeviceID=\(actualID), inputFormat=\(inputFormat), preferredNominalSampleRate=none")
        }
    }

    private func applyPreferredInputDevice(to inputNode: AVAudioInputNode) {
        guard let preferredUID = preferredInputDeviceUID else { return }
        guard let deviceID = AudioDeviceManager.inputDeviceID(for: preferredUID) else {
            Log.audio.warning("Preferred input device not found, using system default")
            return
        }
        
        do {
            try inputNode.auAudioUnit.setDeviceID(deviceID)
        } catch {
            Log.audio.error("Failed to set input device: \(error.localizedDescription)")
        }

        if let audioUnit = inputNode.audioUnit {
            var mutableDeviceID = deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &mutableDeviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                Log.audio.error("Failed to set input device via AUHAL property: \(status)")
            }
        }

        let actualID = inputNode.auAudioUnit.deviceID
        Log.audio.info("Preferred input device requested: \(deviceID), actual: \(actualID)")
    }
    
}

struct CoreAudioInputStreamFormat {
    let streamID: AudioStreamID
    let bufferIndex: Int
    let format: AVAudioFormat
}

enum CoreAudioInputFormatResolver {
    static func resolve(
        streamIDs: [AudioStreamID],
        descriptionForStream: (AudioStreamID) throws -> AudioStreamBasicDescription
    ) throws -> CoreAudioInputStreamFormat {
        guard !streamIDs.isEmpty else {
            throw AudioRecorderError.engineStartFailed("No microphone input stream is available")
        }

        var lastError: Error?
        for (bufferIndex, streamID) in streamIDs.enumerated() {
            do {
                var streamDescription = try descriptionForStream(streamID)
                guard let format = AVAudioFormat(streamDescription: &streamDescription),
                      format.sampleRate > 0,
                      format.channelCount > 0 else {
                    continue
                }
                return CoreAudioInputStreamFormat(
                    streamID: streamID,
                    bufferIndex: bufferIndex,
                    format: format
                )
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
        throw AudioRecorderError.engineStartFailed("Unable to construct microphone input format")
    }
}


final class CoreAudioInputCaptureBackend: AudioCaptureBackend {
    private struct CaptureDevice {
        let deviceID: AudioDeviceID
        let streamID: AudioStreamID
        let ioProcID: AudioDeviceIOProcID
        let generation: UInt64
    }

    private let audioStorage = AudioPCMFileStorage(maximumByteCount: CaptureLimits.maximumASRByteCount)
    /// Native-rate mono copy for retention, kept only when enabled.
    private let nativeAudioStorage = AudioPCMFileStorage()
    /// Serial capture-callback converters; rebuilt automatically when formats change.
    private let asrConverter = ReusableAudioConverter()
    private let nativeConverter = ReusableAudioConverter()
    var retainsNativeAudio = false
    private let targetFormatStorage: AVAudioFormat
    private let callbackQueue = DispatchQueue(label: "tech.watzon.pindrop.microphone-input")
    private let callbackQueueKey = DispatchSpecificKey<Bool>()
    private let stateLock = NSLock()

    private var preferredInputDeviceUID: String?
    private var activeCapture: CaptureDevice?
    private var activeCaptureGeneration: UInt64 = 0
    private var nextCaptureGeneration: UInt64 = 1
    private var activeOnBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var activeOnAudioLevel: ((Float) -> Void)?
    private var activeOnError: ((Error) -> Void)?
    private var isRestartingCapture = false
    private var pendingConfigurationRestartWorkItem: DispatchWorkItem?
    private var suppressConfigurationChangesUntil: Date?
    private var systemDeviceListener: AudioObjectPropertyListenerBlock?
    private var activeDeviceListeners: [
        (objectID: AudioObjectID, address: AudioObjectPropertyAddress, listener: AudioObjectPropertyListenerBlock)
    ] = []

    private(set) var isCapturing = false

    var targetFormat: AVAudioFormat {
        if targetFormatStorage.sampleRate == 0 ||
            targetFormatStorage.channelCount == 0 ||
            targetFormatStorage.commonFormat != .pcmFormatFloat32 {
            return AudioCaptureUtilities.fallbackFormat()
        }
        return targetFormatStorage
    }

    init() throws {
        self.targetFormatStorage = try AudioCaptureUtilities.makeTargetFormat()
        callbackQueue.setSpecific(key: callbackQueueKey, value: true)
    }

    deinit {
        tearDownActiveCapture(clearCallbacks: true)
    }

    func startCapture(
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onAudioLevel: @escaping (Float) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        guard !isCapturing else { return }
        do {
            try audioStorage.start(
                onWriteFailure: onError,
                onLimitReached: { onError(AudioRecorderError.recordingLimitReached(maximumDuration: $0)) }
            )
            if retainsNativeAudio {
                try nativeAudioStorage.start(onWriteFailure: onError)
            } else {
                nativeAudioStorage.discard()
            }
        } catch {
            audioStorage.discard()
            nativeAudioStorage.discard()
            throw error
        }
        cancelPendingConfigurationRestart()
        removeSystemDeviceListeners()
        removeActiveDeviceListeners()
        activeOnBuffer = onBuffer
        activeOnAudioLevel = onAudioLevel
        activeOnError = onError

        do {
            let capture = try makeStartedCaptureDevice(onBuffer: onBuffer, onAudioLevel: onAudioLevel)
            do {
                try verifyPinnedDevice(capture)
            } catch {
                stopAndDestroy(capture)
                throw error
            }

            activateCapture(capture)
            registerDeviceChangeObservers(for: capture)
            suppressConfigurationChanges()
        } catch {
            tearDownActiveCapture(clearCallbacks: true)
            audioStorage.discard()
            nativeAudioStorage.discard()
            throw error
        }
    }

    func stopCapture() throws -> AudioPCMFile {
        guard isCapturing else {
            throw AudioRecorderError.notRecording
        }

        tearDownActiveCapture(clearCallbacks: true)
        asrConverter.reset()
        nativeConverter.reset()
        guard let capturedAudio = try audioStorage.finish() else {
            throw AudioRecorderError.notRecording
        }
        Log.audio.debug("Stopped microphone capture, collected \(capturedAudio.byteCount) bytes")
        return capturedAudio
    }

    func cancelCapture() {
        guard isCapturing else { return }
        tearDownActiveCapture(clearCallbacks: true)
        asrConverter.reset()
        nativeConverter.reset()
        audioStorage.discard()
        nativeAudioStorage.discard()
        Log.audio.info("Microphone capture cancelled")
    }

    func collectNativeAudio() -> AudioCaptureNativeAudio? {
        guard let capturedAudio = try? nativeAudioStorage.finish(), capturedAudio.byteCount > 0 else { return nil }
        return AudioCaptureNativeAudio(fileURL: capturedAudio.fileURL, sampleRate: capturedAudio.sampleRate)
    }

    func reset() {
        tearDownActiveCapture(clearCallbacks: true)
        asrConverter.reset()
        nativeConverter.reset()
        audioStorage.discard()
        nativeAudioStorage.discard()
    }

    func setPreferredInputDeviceUID(_ uid: String) throws {
        let trimmedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUID = trimmedUID.isEmpty ? nil : trimmedUID
        guard preferredInputDeviceUID != normalizedUID else {
            Log.audio.debug("Preferred input device unchanged; no microphone restart needed")
            return
        }

        preferredInputDeviceUID = normalizedUID

        guard isCapturing,
              let activeOnBuffer,
              let activeOnAudioLevel else { return }

        try restartCaptureImmediately(
            reason: "preferred input device changed",
            onBuffer: activeOnBuffer,
            onAudioLevel: activeOnAudioLevel,
            preserveActiveOnFailure: true
        )
    }

    private func makeStartedCaptureDevice(
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onAudioLevel: @escaping (Float) -> Void
    ) throws -> CaptureDevice {
        let deviceID = try resolvedInputDeviceID()
        let sourceStream = try inputStream(for: deviceID)
        let generation = reserveCaptureGeneration()
        asrConverter.reset()
        nativeConverter.reset()

        var createdIOProcID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &createdIOProcID,
            deviceID,
            callbackQueue
        ) { [weak self] _, inputData, _, _, _ in
            self?.handleInput(
                inputData,
                generation: generation,
                sourceStream: sourceStream,
                onBuffer: onBuffer,
                onAudioLevel: onAudioLevel
            )
        }

        guard status == noErr, let createdIOProcID else {
            throw AudioRecorderError.engineStartFailed("Unable to create microphone IO proc (\(status))")
        }

        let startStatus = AudioDeviceStart(deviceID, createdIOProcID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(deviceID, createdIOProcID)
            throw AudioRecorderError.engineStartFailed("Unable to start microphone device (\(startStatus))")
        }

        Log.audio.info("Microphone capture started on input device: \(deviceID)")
        logStartedCaptureState(deviceID: deviceID, sourceFormat: sourceStream.format)
        return CaptureDevice(
            deviceID: deviceID,
            streamID: sourceStream.streamID,
            ioProcID: createdIOProcID,
            generation: generation
        )
    }

    private func resolvedInputDeviceID() throws -> AudioDeviceID {
        if let preferredInputDeviceUID {
            if let deviceID = AudioDeviceManager.inputDeviceID(for: preferredInputDeviceUID) {
                return deviceID
            }
            Log.audio.warning("Preferred input device not found, using system default")
        }

        guard let deviceID = AudioDeviceManager.defaultInputDeviceID() else {
            throw AudioRecorderError.engineStartFailed("No microphone input device is available")
        }
        return deviceID
    }

    private func inputStream(for deviceID: AudioDeviceID) throws -> CoreAudioInputStreamFormat {
        let streamIDs = try inputStreamIDs(for: deviceID)
        return try CoreAudioInputFormatResolver.resolve(streamIDs: streamIDs) { streamID in
            try virtualFormatDescription(for: streamID)
        }
    }

    private func inputStreamIDs(for deviceID: AudioDeviceID) throws -> [AudioStreamID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr else {
            throw AudioRecorderError.engineStartFailed(
                "Unable to read microphone input streams (\(status))"
            )
        }

        let streamCount = Int(size) / MemoryLayout<AudioStreamID>.stride
        guard streamCount > 0 else {
            throw AudioRecorderError.engineStartFailed("No microphone input stream is available")
        }

        var streamIDs = [AudioStreamID](repeating: 0, count: streamCount)
        status = streamIDs.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return kAudioHardwareUnspecifiedError }
            return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, baseAddress)
        }
        guard status == noErr else {
            throw AudioRecorderError.engineStartFailed(
                "Unable to read microphone input streams (\(status))"
            )
        }

        let returnedStreamCount = min(
            streamIDs.count,
            Int(size) / MemoryLayout<AudioStreamID>.stride
        )
        return Array(streamIDs.prefix(returnedStreamCount))
    }

    private func virtualFormatDescription(
        for streamID: AudioStreamID
    ) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyVirtualFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamDescription = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(
            streamID,
            &address,
            0,
            nil,
            &size,
            &streamDescription
        )
        guard status == noErr else {
            throw AudioRecorderError.engineStartFailed(
                "Unable to read microphone input stream format (\(status))"
            )
        }
        return streamDescription
    }


    private func handleInput(
        _ inputData: UnsafePointer<AudioBufferList>,
        generation: UInt64,
        sourceStream: CoreAudioInputStreamFormat,
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onAudioLevel: @escaping (Float) -> Void
    ) {
        guard isActiveCaptureGeneration(generation) else { return }

        let mutableBufferList = UnsafeMutablePointer(mutating: inputData)
        let audioBuffersPointer = UnsafeMutableAudioBufferListPointer(mutableBufferList)
        guard sourceStream.bufferIndex < audioBuffersPointer.count else {
            requestActiveCaptureFailureFromIOCallback(
                AudioRecorderError.engineStartFailed("Microphone input stream buffer is unavailable"),
                generation: generation
            )
            return
        }

        let sourceFormat = sourceStream.format
        let selectedBuffer = audioBuffersPointer[sourceStream.bufferIndex]
        guard selectedBuffer.mDataByteSize > 0, selectedBuffer.mData != nil else { return }
        guard selectedBuffer.mNumberChannels == sourceFormat.channelCount else {
            requestActiveCaptureFailureFromIOCallback(
                AudioRecorderError.engineStartFailed("Microphone input buffer does not match stream format"),
                generation: generation
            )
            return
        }

        var selectedBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: selectedBuffer
        )
        let sourceBuffer = withUnsafeMutablePointer(to: &selectedBufferList) { bufferList in
            AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                bufferListNoCopy: bufferList,
                deallocator: nil
            )
        }
        guard let sourceBuffer else {
            requestActiveCaptureFailureFromIOCallback(
                AudioRecorderError.engineStartFailed("Unable to wrap microphone input buffer"),
                generation: generation
            )
            return
        }

        let bytesPerFrame = max(Int(sourceFormat.streamDescription.pointee.mBytesPerFrame), 1)
        sourceBuffer.frameLength = AVAudioFrameCount(Int(selectedBuffer.mDataByteSize) / bytesPerFrame)

        if retainsNativeAudio,
           let nativeFormat = AVAudioFormat(
               standardFormatWithSampleRate: sourceFormat.sampleRate,
               channels: 1
           ),
           let nativeBuffer = nativeConverter.convert(
               sourceBuffer,
               from: sourceFormat,
               to: nativeFormat
           ) {
            // Downmix to mono at the device's native rate; the no-copy source
            // buffer cannot be stored directly.
            if !nativeAudioStorage.enqueue(nativeBuffer) {
                requestActiveCaptureFailureFromIOCallback(
                    AudioRecorderError.audioWriterBacklogExceeded,
                    generation: generation
                )
                return
            }
        }

        guard let convertedBuffer = asrConverter.convert(
            sourceBuffer,
            from: sourceFormat,
            to: targetFormat
        ) else {
            return
        }

        guard isActiveCaptureGeneration(generation) else { return }
        if !audioStorage.enqueue(convertedBuffer) {
            requestActiveCaptureFailureFromIOCallback(
                AudioRecorderError.audioWriterBacklogExceeded,
                generation: generation
            )
            return
        }
        onBuffer(convertedBuffer)
        if isActiveCaptureGeneration(generation) {
            onAudioLevel(AudioCaptureUtilities.calculateAudioLevel(convertedBuffer))
        }
    }

    private func activateCapture(_ capture: CaptureDevice) {
        stateLock.lock()
        activeCapture = capture
        activeCaptureGeneration = capture.generation
        isCapturing = true
        stateLock.unlock()
    }

    private func reserveCaptureGeneration() -> UInt64 {
        stateLock.lock()
        let generation = nextCaptureGeneration
        nextCaptureGeneration &+= 1
        stateLock.unlock()
        return generation
    }

    private func isActiveCaptureGeneration(_ generation: UInt64) -> Bool {
        stateLock.lock()
        let isActive = isCapturing && activeCaptureGeneration == generation
        stateLock.unlock()
        return isActive
    }

    private func deactivateActiveCapture() -> CaptureDevice? {
        stateLock.lock()
        let capture = activeCapture
        activeCapture = nil
        activeCaptureGeneration = 0
        isCapturing = false
        stateLock.unlock()
        return capture
    }

    private func activeCaptureSnapshot() -> CaptureDevice? {
        stateLock.lock()
        let capture = activeCapture
        stateLock.unlock()
        return capture
    }

    private func tearDownActiveCapture(clearCallbacks: Bool) {
        cancelPendingConfigurationRestart()
        isRestartingCapture = false
        suppressConfigurationChangesUntil = nil
        removeSystemDeviceListeners()
        removeActiveDeviceListeners()

        let capture = deactivateActiveCapture()
        if clearCallbacks {
            activeOnBuffer = nil
            activeOnAudioLevel = nil
            activeOnError = nil
        }

        if let capture {
            stopAndDestroy(capture)
        }
        drainCallbackQueue()
    }

    private func stopAndDestroy(_ capture: CaptureDevice) {
        AudioDeviceStop(capture.deviceID, capture.ioProcID)
        AudioDeviceDestroyIOProcID(capture.deviceID, capture.ioProcID)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            _ = capture.deviceID
            _ = capture.ioProcID
        }
    }

    private func drainCallbackQueue() {
        guard DispatchQueue.getSpecific(key: callbackQueueKey) != true else { return }
        callbackQueue.sync {}
    }

    private func restartCaptureImmediately(
        reason: String,
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onAudioLevel: @escaping (Float) -> Void,
        preserveActiveOnFailure: Bool
    ) throws {
        guard !isRestartingCapture else { return }
        isRestartingCapture = true
        cancelPendingConfigurationRestart()

        do {
            let replacement = try makeStartedCaptureDevice(onBuffer: onBuffer, onAudioLevel: onAudioLevel)
            do {
                try verifyPinnedDevice(replacement)
            } catch {
                stopAndDestroy(replacement)
                throw error
            }

            let previous = activeCaptureSnapshot()
            removeActiveDeviceListeners()
            activateCapture(replacement)
            registerDeviceChangeObservers(for: replacement)
            suppressConfigurationChanges()

            if let previous, previous.generation != replacement.generation {
                stopAndDestroy(previous)
            }
            drainCallbackQueue()
            Log.audio.info("Microphone capture restarted: \(reason)")
            isRestartingCapture = false
        } catch {
            isRestartingCapture = false
            if !preserveActiveOnFailure {
                failActiveCapture(error)
            }
            Log.audio.error("Failed to restart microphone capture after \(reason): \(error.localizedDescription)")
            throw error
        }
    }

    private func handleDeviceConfigurationChange(reason: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCapturing else { return }
            guard !self.isRestartingCapture else { return }
            Log.audio.debug("Microphone device configuration changed: \(reason)")

            if self.isSuppressingConfigurationChanges {
                self.scheduleConfigurationRestart(reason: reason, delay: self.configurationSuppressionRemaining + 0.2)
                return
            }

            self.scheduleConfigurationRestart(reason: reason, delay: 0.5)
        }
    }

    private func scheduleConfigurationRestart(reason: String, delay: TimeInterval) {
        cancelPendingConfigurationRestart()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isCapturing else { return }
            guard !self.isRestartingCapture else { return }

            if self.isSuppressingConfigurationChanges {
                self.scheduleConfigurationRestart(reason: reason, delay: self.configurationSuppressionRemaining + 0.2)
                return
            }

            self.pendingConfigurationRestartWorkItem = nil
            self.restartCaptureAfterDeviceChange(reason: reason, attempt: 1)
        }

        pendingConfigurationRestartWorkItem = workItem
        Log.audio.debug("Scheduling microphone restart after device change")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func restartCaptureAfterDeviceChange(reason: String, attempt: Int) {
        guard let activeOnBuffer, let activeOnAudioLevel else { return }

        do {
            try restartCaptureImmediately(
                reason: reason,
                onBuffer: activeOnBuffer,
                onAudioLevel: activeOnAudioLevel,
                preserveActiveOnFailure: true
            )
        } catch {
            guard attempt < 3, isCapturing else {
                failActiveCapture(error)
                return
            }

            let delay = 0.3 * Double(attempt)
            Log.audio.error("Microphone restart attempt \(attempt) failed: \(error.localizedDescription)")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isCapturing else { return }
                self.restartCaptureAfterDeviceChange(reason: reason, attempt: attempt + 1)
            }
        }
    }

    private func verifyPinnedDevice(_ capture: CaptureDevice) throws {
        guard let preferredInputDeviceUID else { return }
        guard let wantedID = AudioDeviceManager.inputDeviceID(for: preferredInputDeviceUID) else {
            Log.audio.warning("Preferred input device is not currently available")
            return
        }

        if capture.deviceID != wantedID {
            throw AudioRecorderError.engineStartFailed(
                "Pinned input device was not honored (wanted \(wantedID), using \(capture.deviceID))"
            )
        }
    }

    private var isSuppressingConfigurationChanges: Bool {
        guard let suppressConfigurationChangesUntil else { return false }
        return Date() < suppressConfigurationChangesUntil
    }

    private var configurationSuppressionRemaining: TimeInterval {
        guard let suppressConfigurationChangesUntil else { return 0 }
        return max(0, suppressConfigurationChangesUntil.timeIntervalSinceNow)
    }

    private func suppressConfigurationChanges() {
        suppressConfigurationChangesUntil = Date().addingTimeInterval(2.0)
    }

    private func cancelPendingConfigurationRestart() {
        pendingConfigurationRestartWorkItem?.cancel()
        pendingConfigurationRestartWorkItem = nil
    }

    private func failActiveCapture(_ error: Error) {
        let onError = activeOnError
        tearDownActiveCapture(clearCallbacks: true)
        onError?(error)
    }

    /// The IO proc may not synchronously stop or destroy Core Audio devices. Mark
    /// its generation inactive under the state lock, then perform teardown and
    /// user notification on the main control queue.
    private func requestActiveCaptureFailureFromIOCallback(_ error: Error, generation: UInt64) {
        stateLock.lock()
        let shouldSchedule = isCapturing && activeCaptureGeneration == generation
        if shouldSchedule {
            isCapturing = false
            activeCaptureGeneration = 0
        }
        stateLock.unlock()
        guard shouldSchedule else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let onError = self.activeOnError
            self.tearDownActiveCapture(clearCallbacks: true)
            onError?(error)
        }
    }

    private func registerDeviceChangeObservers(for capture: CaptureDevice) {
        registerSystemDeviceListeners()
        registerActiveDeviceListeners(for: capture)
    }

    private func registerSystemDeviceListeners() {
        removeSystemDeviceListeners()

        let listener: AudioObjectPropertyListenerBlock = { [weak self] addressCount, addresses in
            let reason: String
            if addressCount > 0 {
                reason = "system property \(addresses.pointee.mSelector)"
            } else {
                reason = "system devices changed"
            }
            self?.handleDeviceConfigurationChange(reason: reason)
        }
        systemDeviceListener = listener

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main,
            listener
        )

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultInputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            DispatchQueue.main,
            listener
        )
    }

    private func removeSystemDeviceListeners() {
        guard let systemDeviceListener else { return }

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main,
            systemDeviceListener
        )

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultInputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            DispatchQueue.main,
            systemDeviceListener
        )

        self.systemDeviceListener = nil
    }

    private func registerActiveDeviceListeners(for capture: CaptureDevice) {
        removeActiveDeviceListeners()

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleDeviceConfigurationChange(reason: "active input device changed")
        }

        let properties: [(objectID: AudioObjectID, address: AudioObjectPropertyAddress)] = [
            (
                capture.deviceID,
                AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyDeviceIsAlive,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
            ),
            (
                capture.deviceID,
                AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyStreams,
                    mScope: kAudioDevicePropertyScopeInput,
                    mElement: kAudioObjectPropertyElementMain
                )
            ),
            (
                capture.deviceID,
                AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyStreamConfiguration,
                    mScope: kAudioDevicePropertyScopeInput,
                    mElement: kAudioObjectPropertyElementMain
                )
            ),
            (
                capture.deviceID,
                AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyNominalSampleRate,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
            ),
            (
                capture.streamID,
                AudioObjectPropertyAddress(
                    mSelector: kAudioStreamPropertyVirtualFormat,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
            )
        ]

        for property in properties {
            var address = property.address
            AudioObjectAddPropertyListenerBlock(
                property.objectID,
                &address,
                DispatchQueue.main,
                listener
            )
            activeDeviceListeners.append(
                (objectID: property.objectID, address: address, listener: listener)
            )
        }
    }

    private func removeActiveDeviceListeners() {
        for entry in activeDeviceListeners {
            var address = entry.address
            AudioObjectRemovePropertyListenerBlock(
                entry.objectID,
                &address,
                DispatchQueue.main,
                entry.listener
            )
        }
        activeDeviceListeners.removeAll()
    }


    private func logStartedCaptureState(deviceID: AudioDeviceID, sourceFormat: AVAudioFormat) {
        let nominalSampleRate = AudioDeviceManager.nominalSampleRate(deviceID)
        let nominalDescription = nominalSampleRate.map { String($0) } ?? "unknown"
        Log.audio.debug(
            "Microphone capture state: inputDeviceID=\(deviceID), sourceFormat=\(sourceFormat), nominalSampleRate=\(nominalDescription)"
        )
    }
}

@available(macOS 14.2, *)
final class SystemAudioTapCaptureBackend: AudioCaptureBackend {
    private let audioStorage = AudioPCMFileStorage(maximumByteCount: CaptureLimits.maximumASRByteCount)
    /// Serial capture-callback converter; rebuilt automatically when formats change.
    private let audioConverter = ReusableAudioConverter()
    private let targetFormatStorage: AVAudioFormat
    private let callbackQueue = DispatchQueue(label: "tech.watzon.pindrop.system-audio-tap")

    private var tapID: AudioObjectID = 0
    private var aggregateDeviceID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?

    private(set) var isCapturing = false

    var targetFormat: AVAudioFormat {
        if targetFormatStorage.sampleRate == 0 ||
            targetFormatStorage.channelCount == 0 ||
            targetFormatStorage.commonFormat != .pcmFormatFloat32 {
            return AudioCaptureUtilities.fallbackFormat()
        }
        return targetFormatStorage
    }

    init() throws {
        self.targetFormatStorage = try AudioCaptureUtilities.makeTargetFormat()
    }

    deinit {
        destroyCaptureObjects()
    }

    func startCapture(
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onAudioLevel: @escaping (Float) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        guard !isCapturing else { return }
        try audioStorage.start(
            onWriteFailure: onError,
            onLimitReached: { onError(AudioRecorderError.recordingLimitReached(maximumDuration: $0)) }
        )
        var didStartCapture = false
        defer {
            if !didStartCapture {
                audioStorage.discard()
            }
        }
        destroyCaptureObjects()
        audioConverter.reset()

        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [])
        tapDescription.name = "Pindrop System Audio"
        tapDescription.uuid = UUID()
        tapDescription.isPrivate = true
        tapDescription.isExclusive = true
        tapDescription.muteBehavior = .unmuted

        var createdTapID = AudioObjectID(0)
        var status = AudioHardwareCreateProcessTap(tapDescription, &createdTapID)
        guard status == noErr else {
            throw AudioRecorderError.systemAudioCaptureFailed("Unable to create process tap (\(status))")
        }

        let createdAggregateDeviceID: AudioObjectID
        do {
            let tapUID = try tapUID(for: createdTapID)
            let outputUID = try defaultOutputDeviceUID()
            createdAggregateDeviceID = try createAggregateDevice(tapUID: tapUID, outputDeviceUID: outputUID)
        } catch {
            AudioHardwareDestroyProcessTap(createdTapID)
            throw error
        }

        let sourceFormat: AVAudioFormat
        do {
            sourceFormat = try tapFormat(for: createdTapID)
        } catch {
            AudioHardwareDestroyAggregateDevice(createdAggregateDeviceID)
            AudioHardwareDestroyProcessTap(createdTapID)
            throw error
        }

        var createdIOProcID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(
            &createdIOProcID,
            createdAggregateDeviceID,
            callbackQueue
        ) { [weak self] _, inputData, _, _, _ in
            self?.handleInput(
                inputData,
                sourceFormat: sourceFormat,
                onBuffer: onBuffer,
                onAudioLevel: onAudioLevel,
                onError: onError
            )
        }
        guard status == noErr, let createdIOProcID else {
            AudioHardwareDestroyAggregateDevice(createdAggregateDeviceID)
            AudioHardwareDestroyProcessTap(createdTapID)
            throw AudioRecorderError.systemAudioCaptureFailed("Unable to create IO proc (\(status))")
        }

        status = AudioDeviceStart(createdAggregateDeviceID, createdIOProcID)
        guard status == noErr else {
            AudioDeviceDestroyIOProcID(createdAggregateDeviceID, createdIOProcID)
            AudioHardwareDestroyAggregateDevice(createdAggregateDeviceID)
            AudioHardwareDestroyProcessTap(createdTapID)
            throw AudioRecorderError.systemAudioCaptureFailed("Unable to start system audio device (\(status))")
        }

        tapID = createdTapID
        aggregateDeviceID = createdAggregateDeviceID
        ioProcID = createdIOProcID
        isCapturing = true
        didStartCapture = true
        Log.audio.info("System audio tap capture started")
    }

    func stopCapture() throws -> AudioPCMFile {
        guard isCapturing else {
            throw AudioRecorderError.notRecording
        }

        destroyCaptureObjects()
        audioConverter.reset()
        guard let capturedAudio = try audioStorage.finish() else {
            throw AudioRecorderError.notRecording
        }
        Log.audio.debug("Stopped system audio capture, collected \(capturedAudio.byteCount) bytes")
        return capturedAudio
    }

    func cancelCapture() {
        guard isCapturing else { return }
        destroyCaptureObjects()
        audioConverter.reset()
        audioStorage.discard()
        Log.audio.info("System audio capture cancelled")
    }

    func reset() {
        destroyCaptureObjects()
        audioConverter.reset()
        audioStorage.discard()
    }

    func setPreferredInputDeviceUID(_ uid: String) throws {
        _ = uid
    }

    private func handleInput(
        _ inputData: UnsafePointer<AudioBufferList>,
        sourceFormat: AVAudioFormat,
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onAudioLevel: @escaping (Float) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        let mutableBufferList = UnsafeMutablePointer(mutating: inputData)
        let audioBuffersPointer = UnsafeMutableAudioBufferListPointer(mutableBufferList)
        guard let firstBuffer = audioBuffersPointer.first, firstBuffer.mDataByteSize > 0 else {
            return
        }

        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            bufferListNoCopy: mutableBufferList,
            deallocator: nil
        ) else {
            return
        }

        let bytesPerFrame = max(Int(sourceFormat.streamDescription.pointee.mBytesPerFrame), 1)
        sourceBuffer.frameLength = AVAudioFrameCount(Int(firstBuffer.mDataByteSize) / bytesPerFrame)

        guard let convertedBuffer = audioConverter.convert(
            sourceBuffer,
            from: sourceFormat,
            to: targetFormat
        ) else {
            return
        }

        if !audioStorage.enqueue(convertedBuffer) {
            onError(AudioRecorderError.audioWriterBacklogExceeded)
            return
        }
        onBuffer(convertedBuffer)
        onAudioLevel(AudioCaptureUtilities.calculateAudioLevel(convertedBuffer))
    }

    private func tapUID(for tapID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        let tapUIDPointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        tapUIDPointer.initialize(to: nil)
        defer {
            tapUIDPointer.deinitialize(count: 1)
            tapUIDPointer.deallocate()
        }
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, tapUIDPointer)
        guard status == noErr, let tapUID = tapUIDPointer.pointee else {
            throw AudioRecorderError.systemAudioCaptureFailed("Unable to read tap UID (\(status))")
        }
        return tapUID as String
    }

    private func defaultOutputDeviceUID() throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var outputDeviceID = AudioObjectID(0)
        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &outputDeviceID
        )
        guard status == noErr else {
            throw AudioRecorderError.systemAudioCaptureFailed("Unable to resolve default output device (\(status))")
        }

        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        size = UInt32(MemoryLayout<CFString?>.size)
        let outputUIDPointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        outputUIDPointer.initialize(to: nil)
        defer {
            outputUIDPointer.deinitialize(count: 1)
            outputUIDPointer.deallocate()
        }
        status = AudioObjectGetPropertyData(outputDeviceID, &address, 0, nil, &size, outputUIDPointer)
        guard status == noErr, let outputUID = outputUIDPointer.pointee else {
            throw AudioRecorderError.systemAudioCaptureFailed("Unable to read output device UID (\(status))")
        }

        return outputUID as String
    }

    private func createAggregateDevice(tapUID: String, outputDeviceUID: String) throws -> AudioObjectID {
        let aggregateUID = "tech.watzon.pindrop.aggregate.\(UUID().uuidString)"
        let aggregateDictionary: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Pindrop System Audio Capture",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID]
            ]
        ]

        var aggregateDeviceID = AudioObjectID(0)
        let status = AudioHardwareCreateAggregateDevice(aggregateDictionary as CFDictionary, &aggregateDeviceID)
        guard status == noErr else {
            throw AudioRecorderError.systemAudioCaptureFailed("Unable to create aggregate device (\(status))")
        }
        return aggregateDeviceID
    }

    private func tapFormat(for tapID: AudioObjectID) throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var streamDescription = AudioStreamBasicDescription()
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &streamDescription)
        guard status == noErr else {
            throw AudioRecorderError.systemAudioCaptureFailed("Unable to read tap format (\(status))")
        }

        var mutableDescription = streamDescription
        guard let format = AVAudioFormat(streamDescription: &mutableDescription) else {
            throw AudioRecorderError.systemAudioCaptureFailed("Unable to construct tap audio format")
        }

        return format
    }

    private func destroyCaptureObjects() {
        if aggregateDeviceID != 0, let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }

        if aggregateDeviceID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = 0
        }

        if tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }

        isCapturing = false
    }
}

final class MixedAudioCaptureBackend: AudioCaptureBackend {
    private let microphoneBackend: AudioCaptureBackend
    private let systemAudioBackend: AudioCaptureBackend

    private(set) var isCapturing = false

    var targetFormat: AVAudioFormat {
        microphoneBackend.targetFormat
    }

    var retainsNativeAudio: Bool {
        get { microphoneBackend.retainsNativeAudio }
        set { microphoneBackend.retainsNativeAudio = newValue }
    }

    init(microphoneBackend: AudioCaptureBackend, systemAudioBackend: AudioCaptureBackend) {
        self.microphoneBackend = microphoneBackend
        self.systemAudioBackend = systemAudioBackend
    }

    func startCapture(
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onAudioLevel: @escaping (Float) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        var microphoneLevel: Float = 0
        var systemLevel: Float = 0

        do {
            try microphoneBackend.startCapture(onBuffer: { _ in }, onAudioLevel: { level in
                microphoneLevel = level
                onAudioLevel(max(microphoneLevel, systemLevel))
            }, onError: onError)
        } catch {
            throw error
        }

        do {
            try systemAudioBackend.startCapture(onBuffer: { _ in }, onAudioLevel: { level in
                systemLevel = level
                onAudioLevel(max(microphoneLevel, systemLevel))
            }, onError: onError)
        } catch {
            microphoneBackend.cancelCapture()
            throw error
        }

        isCapturing = true
        _ = onBuffer
    }

    func stopCapture() throws -> AudioPCMFile {
        guard isCapturing else {
            throw AudioRecorderError.notRecording
        }

        let microphoneAudio: AudioPCMFile
        do {
            microphoneAudio = try microphoneBackend.stopCapture()
        } catch {
            systemAudioBackend.cancelCapture()
            isCapturing = false
            throw error
        }
        let systemAudio: AudioPCMFile
        do {
            systemAudio = try systemAudioBackend.stopCapture()
        } catch {
            microphoneAudio.discard()
            systemAudioBackend.cancelCapture()
            isCapturing = false
            throw error
        }
        isCapturing = false

        return try AudioCaptureUtilities.mixPCMFiles(microphoneAudio, systemAudio)
    }

    func cancelCapture() {
        microphoneBackend.cancelCapture()
        systemAudioBackend.cancelCapture()
        isCapturing = false
    }

    func reset() {
        microphoneBackend.reset()
        systemAudioBackend.reset()
        isCapturing = false
    }

    func setPreferredInputDeviceUID(_ uid: String) throws {
        try microphoneBackend.setPreferredInputDeviceUID(uid)
    }

    func collectNativeAudio() -> AudioCaptureNativeAudio? {
        microphoneBackend.collectNativeAudio()
    }
}

// MARK: - Band levels

/// Per-band RMS levels for the current audio buffer, normalized 0…1 with the same
/// gain curve as `AudioCaptureUtilities.calculateAudioLevel`. Drives the Orb
/// indicator's low, mid, and high waveform traces.
struct AudioBandLevels: Equatable {
    var low: Float
    var mid: Float
    var high: Float

    static let zero = AudioBandLevels(low: 0, mid: 0, high: 0)
}

/// Splits incoming buffers into three frequency bands (≲300 Hz, 300 Hz–2 kHz,
/// ≳2 kHz) using two cascaded one-pole low-pass filters, then reports per-band
/// RMS. Filter state persists across buffers; instances must only be used from
/// the capture callback's serial context.
final class ThreeBandLevelAnalyzer {
    private var lowState: Float = 0
    private var midState: Float = 0
    private var coefficientsSampleRate: Double = 0
    private var alphaLow: Float = 0
    private var alphaMid: Float = 0

    private static let lowCrossoverHz = 300.0
    private static let midCrossoverHz = 2000.0
    /// Speech carries far less energy in the upper bands; these gains rebalance
    /// the traces so all three read at comparable visual amplitude.
    private static let midGain: Float = 1.6
    private static let highGain: Float = 2.6

    func process(_ buffer: AVAudioPCMBuffer) -> AudioBandLevels {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0,
              buffer.format.commonFormat == .pcmFormatFloat32,
              let channelData = buffer.floatChannelData else {
            return .zero
        }

        updateCoefficientsIfNeeded(sampleRate: buffer.format.sampleRate)

        let samples = UnsafeBufferPointer(start: channelData[0], count: frameLength)
        var sumLow: Float = 0
        var sumMid: Float = 0
        var sumHigh: Float = 0

        for sample in samples {
            lowState += alphaLow * (sample - lowState)
            midState += alphaMid * (sample - midState)
            let low = lowState
            let mid = midState - lowState
            let high = sample - midState
            sumLow += low * low
            sumMid += mid * mid
            sumHigh += high * high
        }

        let count = Float(frameLength)
        return AudioBandLevels(
            low: normalize(sqrt(sumLow / count)),
            mid: normalize(sqrt(sumMid / count) * Self.midGain),
            high: normalize(sqrt(sumHigh / count) * Self.highGain)
        )
    }

    func reset() {
        lowState = 0
        midState = 0
    }

    private func normalize(_ rms: Float) -> Float {
        min(1.0, rms * 15)
    }

    private func updateCoefficientsIfNeeded(sampleRate: Double) {
        guard sampleRate > 0, sampleRate != coefficientsSampleRate else { return }
        coefficientsSampleRate = sampleRate
        alphaLow = Float(1 - exp(-2 * Double.pi * Self.lowCrossoverHz / sampleRate))
        alphaMid = Float(1 - exp(-2 * Double.pi * Self.midCrossoverHz / sampleRate))
    }
}

// MARK: - Level normalization

/// Visualization-only automatic gain control. Tracks a slow-decaying envelope of
/// the incoming overall level and rescales levels so quiet sources (soft voices,
/// low-gain mics, far-field devices) still fill the visual range while loud
/// sources don't change. Only indicator waveforms consume the normalized values;
/// recorded audio and transcription input are untouched.
/// Instances must only be used from the capture callback's serial context.
final class AudioLevelNormalizer {
    /// The envelope never adapts below this, so silence and room noise are not
    /// boosted to full scale during pauses.
    static let envelopeFloor: Float = 0.08
    /// Fraction of the envelope that maps to full visual scale — peaks at the
    /// tracked loudness land just below 1.0.
    static let targetPeak: Float = 0.9
    /// Per-update decay; at typical tap cadence the envelope relaxes over a few
    /// seconds, so the gain follows gradual loudness changes without pumping on
    /// every syllable.
    static let decay: Float = 0.994

    private var envelope: Float = 0

    func reset() {
        envelope = 0
    }

    /// Gain derived from the current envelope. Bands are scaled by this same
    /// factor so their relative structure (voice body vs sibilance) is preserved.
    var currentGain: Float {
        Self.targetPeak / max(envelope, Self.envelopeFloor)
    }

    /// Feed the latest overall level (instant attack, slow release) and return
    /// its normalized value.
    func normalize(_ level: Float) -> Float {
        envelope = max(level, envelope * Self.decay)
        return min(1.0, level * currentGain)
    }

    func scaled(_ bands: AudioBandLevels) -> AudioBandLevels {
        let gain = currentGain
        return AudioBandLevels(
            low: min(1.0, bands.low * gain),
            mid: min(1.0, bands.mid * gain),
            high: min(1.0, bands.high * gain)
        )
    }
}

// MARK: - Capture finalization handoff

/// Exclusive ownership wrapper so stop-time drain/mix/materialization can leave
/// the main actor without concurrent access to the same backend instance.
private final class CaptureFinalizationHandoff: @unchecked Sendable {
    let backend: any AudioCaptureBackend

    init(_ backend: any AudioCaptureBackend) {
        self.backend = backend
    }
}

/// Owns the ASR bytes and optional native spool after off-main finalization.
private final class CaptureFinalizationResult: @unchecked Sendable {
    let audioData: Data
    let nativeAudio: AudioCaptureNativeAudio?

    init(audioData: Data, nativeAudio: AudioCaptureNativeAudio?) {
        self.audioData = audioData
        self.nativeAudio = nativeAudio
    }
}

private enum CaptureFinalization {
    /// Runs only after capture ownership has been detached from `AudioRecorder`.
    /// Stops the backend (spool drain + optional mix) and materializes contiguous
    /// ASR PCM. Temporary files are removed on every success and error path.
    static func stopAndMaterialize(
        backend: any AudioCaptureBackend,
        maximumByteCount: Int
    ) throws -> CaptureFinalizationResult {
        let capturedAudio = try backend.stopCapture()
        let nativeAudio = backend.collectNativeAudio()
        do {
            let audioData = try capturedAudio.consumeData(maximumByteCount: maximumByteCount)
            return CaptureFinalizationResult(audioData: audioData, nativeAudio: nativeAudio)
        } catch {
            nativeAudio?.discard()
            // consumeData removes the ASR spool in both success and failure paths.
            throw error
        }
    }
}

/// Coalesces overall level and band-level UI updates into one main-actor delivery.
/// Capture callbacks only ever keep the latest values and at most one pending hop.
private final class AudioMeterDeliveryCoalescer: @unchecked Sendable {
    private let lock = NSLock()
    private var latestLevel: Float?
    private var latestBands: AudioBandLevels?
    private var isDeliveryPending = false

    /// Capture-thread entry. `deliver` runs on the main actor with the latest
    /// values present when the hop executes; at most one delivery is scheduled.
    func note(
        level: Float? = nil,
        bands: AudioBandLevels? = nil,
        deliver: @escaping @MainActor (_ level: Float?, _ bands: AudioBandLevels?) -> Void
    ) {
        lock.lock()
        if let level {
            latestLevel = level
        }
        if let bands {
            latestBands = bands
        }
        if isDeliveryPending {
            lock.unlock()
            return
        }
        isDeliveryPending = true
        lock.unlock()

        Task { @MainActor in
            let snapshot = self.takeSnapshot()
            deliver(snapshot.level, snapshot.bands)
        }
    }

    func reset() {
        lock.lock()
        latestLevel = nil
        latestBands = nil
        isDeliveryPending = false
        lock.unlock()
    }

    private func takeSnapshot() -> (level: Float?, bands: AudioBandLevels?) {
        lock.lock()
        let level = latestLevel
        let bands = latestBands
        latestLevel = nil
        latestBands = nil
        isDeliveryPending = false
        lock.unlock()
        return (level, bands)
    }
}

// MARK: - AudioRecorder

@MainActor
final class AudioRecorder {
    
    private(set) var isRecording = false
    private var isStartingRecording = false
    private var isLimitStopRequested = false
    private var currentConfiguration: AudioRecordingConfiguration = .microphone
    private var preferredInputDeviceUID: String?
    
    let permissionManager: any PermissionProviding
    private let microphoneCaptureBackend: AudioCaptureBackend
    private let systemAudioCaptureBackend: AudioCaptureBackend?
    private var activeCaptureBackend: AudioCaptureBackend?
    /// Non-nil while stop finalization owns a detached backend off the main actor.
    private var finalizingCapture: CaptureFinalizationHandoff?
    /// Start callers parked until `finalizingCapture` releases backend ownership.
    private var finalizationWaiters: [CheckedContinuation<Void, Never>] = []
    
    var targetFormat: AVAudioFormat {
        activeCaptureBackend?.targetFormat ?? microphoneCaptureBackend.targetFormat
    }
    
    var onAudioLevel: ((Float) -> Void)?
    /// Invoked directly on the audio capture thread — the streaming pump yields the
    /// buffer into an AsyncStream and must not wait for a main-thread slot (a busy
    /// render loop delays main-actor delivery until the session ends). The closure
    /// must be thread-safe; it is set/cleared on the main actor between sessions.
    nonisolated(unsafe) var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    /// When true, microphone sessions also keep a native-rate mono copy for
    /// retention-quality encoding. Set per session by the coordinator (retention on).
    var retainNativeAudioForSession = false
    /// Native-rate spool from the most recent stopped recording, if kept.
    private var lastNativeAudio: AudioCaptureNativeAudio?
    var onAudioBandLevels: ((AudioBandLevels) -> Void)?
    var onCaptureError: ((Error) -> Void)?

    /// Touched only from the capture backend's buffer callback (serial).
    private let bandLevelAnalyzer = ThreeBandLevelAnalyzer()
    /// Touched only from the capture backend's callbacks (serial).
    private let levelNormalizer = AudioLevelNormalizer()
    /// Capture-thread coalescer for main-actor meter delivery.
    private let meterDelivery = AudioMeterDeliveryCoalescer()

    init(
        permissionManager: some PermissionProviding,
        captureBackend: AudioCaptureBackend? = nil,
        systemAudioCaptureBackend: AudioCaptureBackend? = nil
    ) throws {
        self.permissionManager = permissionManager
        self.microphoneCaptureBackend = try captureBackend ?? CoreAudioInputCaptureBackend()
        if let systemAudioCaptureBackend {
            self.systemAudioCaptureBackend = systemAudioCaptureBackend
        } else if #available(macOS 14.2, *) {
            self.systemAudioCaptureBackend = try? SystemAudioTapCaptureBackend()
        } else {
            self.systemAudioCaptureBackend = nil
        }
    }
    
    @discardableResult
    func startRecording() async throws -> Bool {
        try await startRecording(configuration: .microphone)
    }

    @discardableResult
    func startRecording(configuration: AudioRecordingConfiguration) async throws -> Bool {
        if isRecording || isStartingRecording {
            return false
        }

        isStartingRecording = true
        defer { isStartingRecording = false }

        // Finalization exclusively owns the capture backend off the main actor.
        // Wait it out before reusing any backend; never start over a live handoff.
        await awaitCaptureFinalizationIfNeeded()
        guard finalizingCapture == nil else {
            return false
        }

        if configuration.mode.requiresMicrophonePermission {
            guard await permissionManager.requestPermission() else {
                throw AudioRecorderError.permissionDenied
            }
        }

        if configuration.mode.requiresSystemAudioPermission {
            guard await permissionManager.requestSystemAudioPermission() else {
                throw AudioRecorderError.systemAudioPermissionDenied
            }
        }

        let captureBackend = try makeCaptureBackend(for: configuration.mode)
        if let preferredInputDeviceUID {
            try captureBackend.setPreferredInputDeviceUID(preferredInputDeviceUID)
        }

        lastNativeAudio?.discard()
        lastNativeAudio = nil
        captureBackend.retainsNativeAudio = retainNativeAudioForSession
        isLimitStopRequested = false

        bandLevelAnalyzer.reset()
        levelNormalizer.reset()
        meterDelivery.reset()
        do {
            let bandLevelAnalyzer = self.bandLevelAnalyzer
            let levelNormalizer = self.levelNormalizer
            let meterDelivery = self.meterDelivery
            try captureBackend.startCapture(
                onBuffer: { [weak self] buffer in
                    // Bands use the gain from the previous level update — a
                    // one-buffer lag that is invisible at tap cadence.
                    let bands = levelNormalizer.scaled(bandLevelAnalyzer.process(buffer))
                    // Raw buffers go straight to the streaming pump from the capture
                    // thread; only UI-facing meters hop to the main actor.
                    self?.onAudioBuffer?(buffer)
                    meterDelivery.note(bands: bands) { [weak self] level, deliveredBands in
                        if let level {
                            self?.onAudioLevel?(level)
                        }
                        if let deliveredBands {
                            self?.onAudioBandLevels?(deliveredBands)
                        }
                    }
                },
                onAudioLevel: { [weak self] level in
                    let normalized = levelNormalizer.normalize(level)
                    meterDelivery.note(level: normalized) { [weak self] deliveredLevel, bands in
                        if let deliveredLevel {
                            self?.onAudioLevel?(deliveredLevel)
                        }
                        if let bands {
                            self?.onAudioBandLevels?(bands)
                        }
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.handleCaptureFailure(error)
                    }
                }
            )
        } catch {
            activeCaptureBackend = nil
            currentConfiguration = .microphone
            throw error
        }

        activeCaptureBackend = captureBackend
        currentConfiguration = configuration
        isRecording = true
        return true
    }
    
    func stopRecording() async throws -> Data {
        guard isRecording, let activeCaptureBackend else {
            throw AudioRecorderError.notRecording
        }

        // Detach capture ownership before leaving the main actor so concurrent
        // cancel/reset paths cannot race the same backend instance.
        let handoff = CaptureFinalizationHandoff(activeCaptureBackend)
        finalizingCapture = handoff
        isRecording = false
        isLimitStopRequested = false
        self.activeCaptureBackend = nil
        currentConfiguration = .microphone
        meterDelivery.reset()

        let finalization = Task.detached(priority: .userInitiated) {
            try CaptureFinalization.stopAndMaterialize(
                backend: handoff.backend,
                maximumByteCount: CaptureLimits.maximumASRByteCount
            )
        }

        do {
            let result = try await finalization.value
            endCaptureFinalization(handoff)
            lastNativeAudio?.discard()
            lastNativeAudio = result.nativeAudio
            Log.audio.info("Recording stopped, \(result.audioData.count) bytes captured")
            return result.audioData
        } catch {
            // Drain any late success so temporary files and native spools are not
            // orphaned when the waiting main-actor task is cancelled.
            finalization.cancel()
            switch await finalization.result {
            case .success(let lateResult):
                lateResult.nativeAudio?.discard()
            case .failure:
                handoff.backend.cancelCapture()
            }
            endCaptureFinalization(handoff)
            lastNativeAudio?.discard()
            lastNativeAudio = nil
            throw error
        }
    }
    
    func cancelRecording() {
        guard isRecording else {
            return
        }

        activeCaptureBackend?.cancelCapture()
        activeCaptureBackend = nil
        currentConfiguration = .microphone
        isRecording = false
        isLimitStopRequested = false
        meterDelivery.reset()
        lastNativeAudio?.discard()
        lastNativeAudio = nil

        Log.audio.info("Recording cancelled, audio discarded")
    }
    
    func resetAudioEngine() {
        // Never reset/reuse a backend still owned by detached finalization.
        if finalizingCapture == nil {
            activeCaptureBackend?.reset()
            microphoneCaptureBackend.reset()
            systemAudioCaptureBackend?.reset()
            activeCaptureBackend = nil
            lastNativeAudio?.discard()
            lastNativeAudio = nil
        }
        currentConfiguration = .microphone
        isRecording = false
        isLimitStopRequested = false
        meterDelivery.reset()
        Log.audio.info("Audio engine reset")
    }

    /// Transfers the native spool to the retention service. It must be consumed or
    /// discarded by that service; this recorder will not materialize it as Data.
    func takeLastNativeAudio() -> AudioCaptureNativeAudio? {
        defer { lastNativeAudio = nil }
        return lastNativeAudio
    }

    func setPreferredInputDeviceUID(_ uid: String) throws {
        guard preferredInputDeviceUID != uid else { return }

        preferredInputDeviceUID = uid
        if let activeCaptureBackend {
            try activeCaptureBackend.setPreferredInputDeviceUID(uid)
            if currentConfiguration.mode == .systemAudio {
                try microphoneCaptureBackend.setPreferredInputDeviceUID(uid)
            }
        } else {
            try microphoneCaptureBackend.setPreferredInputDeviceUID(uid)
        }
    }

    private func handleCaptureFailure(_ error: Error) {
        guard isRecording else { return }
        if case .recordingLimitReached = error as? AudioRecorderError {
            guard !isLimitStopRequested else { return }
            isLimitStopRequested = true
            // Keep the backend and spool alive. The coordinator routes this
            // controlled signal through normal stop/transcription finalization.
            onCaptureError?(error)
            return
        }
        // A full writer handoff is terminal: leaving the backend active would
        // continue invoking its real-time callback after the recorder has
        // rejected the session. Stop it before releasing our active reference.
        activeCaptureBackend?.cancelCapture()
        isRecording = false
        isLimitStopRequested = false
        activeCaptureBackend = nil
        currentConfiguration = .microphone
        meterDelivery.reset()
        Log.audio.error("Active capture failed: \(error.localizedDescription)")
        onCaptureError?(error)
    }

    /// Suspends until any in-flight stop finalization releases backend ownership.
    private func awaitCaptureFinalizationIfNeeded() async {
        guard finalizingCapture != nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if finalizingCapture == nil {
                continuation.resume()
            } else {
                finalizationWaiters.append(continuation)
            }
        }
    }

    private func endCaptureFinalization(_ handoff: CaptureFinalizationHandoff) {
        guard finalizingCapture === handoff else { return }
        finalizingCapture = nil
        let waiters = finalizationWaiters
        finalizationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }


    private func makeCaptureBackend(for mode: AudioRecordingMode) throws -> AudioCaptureBackend {
        switch mode {
        case .microphone:
            return microphoneCaptureBackend
        case .systemAudio:
            guard let systemAudioCaptureBackend else {
                throw AudioRecorderError.unsupportedCaptureMode("System audio capture requires macOS 14.2 or later.")
            }
            return systemAudioCaptureBackend
        case .microphoneAndSystemAudio:
            guard let systemAudioCaptureBackend else {
                throw AudioRecorderError.unsupportedCaptureMode("System audio capture requires macOS 14.2 or later.")
            }
            return MixedAudioCaptureBackend(
                microphoneBackend: microphoneCaptureBackend,
                systemAudioBackend: systemAudioCaptureBackend
            )
        }
    }
}
