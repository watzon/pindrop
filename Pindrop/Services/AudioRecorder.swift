//
//  AudioRecorder.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import AVFoundation
import CoreAudio
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
        }
    }
}

// MARK: - AudioCaptureBackend Protocol

/// Abstracts audio capture hardware, enabling mock-based testing.
protocol AudioCaptureBackend: AnyObject {
    var isCapturing: Bool { get }
    var targetFormat: AVAudioFormat { get }
    
    func startCapture(onBuffer: @escaping (AVAudioPCMBuffer) -> Void, onAudioLevel: @escaping (Float) -> Void) throws
    func stopCapture() throws -> [AVAudioPCMBuffer]
    func cancelCapture()
    func reset()
    func setPreferredInputDeviceUID(_ uid: String)
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

    static func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        from inputFormat: AVAudioFormat,
        to outputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            Log.audio.error("Failed to create audio converter")
            return nil
        }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: capacity
        ) else {
            Log.audio.error("Failed to create output buffer")
            return nil
        }

        var error: NSError?

        final class InputState: @unchecked Sendable {
            var consumed = false
        }
        let inputState = InputState()

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputState.consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputState.consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        let status = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if let error {
            Log.audio.error("Conversion error: \(error)")
            return nil
        }

        if status == .error {
            Log.audio.error("Conversion status error")
            return nil
        }

        return convertedBuffer
    }

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

    static func flattenSamples(from buffers: [AVAudioPCMBuffer]) -> [Float] {
        var samples: [Float] = []
        for buffer in buffers {
            guard let channelData = buffer.floatChannelData else { continue }
            let frameLength = Int(buffer.frameLength)
            samples.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: frameLength))
        }
        return samples
    }

    static func makeBuffer(from samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty else { return nil }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channelData = buffer.floatChannelData else { return nil }
        channelData[0].initialize(from: samples, count: samples.count)
        return buffer
    }

    static func combineBuffersToData(_ buffers: [AVAudioPCMBuffer]) -> Data {
        let allSamples = flattenSamples(from: buffers)
        return allSamples.withUnsafeBufferPointer { bufferPointer in
            Data(buffer: bufferPointer)
        }
    }
}

// MARK: - AVAudioEngineCaptureBackend

/// Thread-safe buffer storage for audio recording.
/// Uses a lock to allow immediate buffer appending from the audio render thread.
private final class AudioBufferStorage: @unchecked Sendable {
    private var buffers: [AVAudioPCMBuffer] = []
    private let lock = NSLock()
    
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        buffers.append(buffer)
    }
    
    func removeAll() -> [AVAudioPCMBuffer] {
        lock.lock()
        defer { lock.unlock() }
        let result = buffers
        buffers.removeAll()
        return result
    }
    
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffers.count
    }
}

final class AVAudioEngineCaptureBackend: AudioCaptureBackend {
    
    private var audioEngine: AVAudioEngine?
    private let audioBuffers = AudioBufferStorage()
    private var preferredInputDeviceUID: String?
    private var configurationChangeObserver: NSObjectProtocol?
    
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
    
    func startCapture(onBuffer: @escaping (AVAudioPCMBuffer) -> Void, onAudioLevel: @escaping (Float) -> Void) throws {
        _ = audioBuffers.removeAll()
        removeConfigurationChangeObserver()
        
        let engine = AVAudioEngine()
        self.audioEngine = engine
        registerConfigurationChangeObserver(for: engine)
        
        let inputNode = engine.inputNode
        applyPreferredInputDevice(to: inputNode)
        let nodeFormat = inputNode.inputFormat(forBus: 0)
        let tapFormat = AVAudioFormat(
            standardFormatWithSampleRate: nodeFormat.sampleRate,
            channels: 1
        ) ?? nodeFormat
        
        Log.audio.debug("Input format: \(nodeFormat)")
        Log.audio.debug("Tap format: \(tapFormat)")
        
        let bufferStorage = self.audioBuffers
        let targetFmt = self.targetFormat
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            guard self != nil else { return }

            let bufferFormat = buffer.format
            if let convertedBuffer = AudioCaptureUtilities.convertBuffer(buffer, from: bufferFormat, to: targetFmt) {
                bufferStorage.append(convertedBuffer)
                onBuffer(convertedBuffer)
            }
            
            let level = AudioCaptureUtilities.calculateAudioLevel(buffer)
            onAudioLevel(level)
        }
        
        engine.prepare()
        
        do {
            try engine.start()
            isCapturing = true
            Log.audio.info("Audio engine started")
        } catch {
            inputNode.removeTap(onBus: 0)
            engine.reset()
            self.audioEngine = nil
            throw AudioRecorderError.engineStartFailed(error.localizedDescription)
        }
    }
    
    func stopCapture() throws -> [AVAudioPCMBuffer] {
        guard isCapturing, let engine = audioEngine else {
            throw AudioRecorderError.notRecording
        }
        
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
        self.audioEngine = nil
        removeConfigurationChangeObserver()
        
        let collectedBuffers = audioBuffers.removeAll()
        Log.audio.debug("Stopped capturing, collected \(collectedBuffers.count) buffers")
        
        return collectedBuffers
    }
    
    func cancelCapture() {
        guard isCapturing, let engine = audioEngine else {
            return
        }
        
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
        self.audioEngine = nil
        removeConfigurationChangeObserver()
        _ = audioBuffers.removeAll()
        
        Log.audio.info("Capture cancelled, audio discarded")
    }
    
    func reset() {
        if let engine = audioEngine {
            if isCapturing {
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
            }
        }
        audioEngine = nil
        removeConfigurationChangeObserver()
        isCapturing = false
        _ = audioBuffers.removeAll()
        Log.audio.info("Audio engine reset")
    }
    
    func setPreferredInputDeviceUID(_ uid: String) {
        let trimmedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        preferredInputDeviceUID = trimmedUID.isEmpty ? nil : trimmedUID

        guard let engine = audioEngine else { return }
        applyPreferredInputDevice(to: engine.inputNode)
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

    private func handleEngineConfigurationChange(for engine: AVAudioEngine) {
        guard isCapturing, audioEngine === engine else { return }

        // AVAudioEngine can reconfigure its I/O unit mid-session and fall back to a
        // different input. Re-apply the user's selected device when that happens.
        applyPreferredInputDevice(to: engine.inputNode)
    }

    private func applyPreferredInputDevice(to inputNode: AVAudioInputNode) {
        guard let preferredUID = preferredInputDeviceUID else { return }
        guard let deviceID = AudioDeviceManager.inputDeviceID(for: preferredUID) else {
            Log.audio.warning("Preferred input device not found, using system default")
            return
        }
        
        do {
            try inputNode.auAudioUnit.setDeviceID(deviceID)
            Log.audio.info("Using preferred input device: \(deviceID)")
        } catch {
            Log.audio.error("Failed to set input device: \(error.localizedDescription)")
        }
    }
    
}

@available(macOS 14.2, *)
final class SystemAudioTapCaptureBackend: AudioCaptureBackend {
    private let audioBuffers = AudioBufferStorage()
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
        onAudioLevel: @escaping (Float) -> Void
    ) throws {
        guard !isCapturing else { return }
        _ = audioBuffers.removeAll()
        destroyCaptureObjects()

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
                onAudioLevel: onAudioLevel
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
        Log.audio.info("System audio tap capture started")
    }

    func stopCapture() throws -> [AVAudioPCMBuffer] {
        guard isCapturing else {
            throw AudioRecorderError.notRecording
        }

        destroyCaptureObjects()
        let collectedBuffers = audioBuffers.removeAll()
        Log.audio.debug("Stopped system audio capture, collected \(collectedBuffers.count) buffers")
        return collectedBuffers
    }

    func cancelCapture() {
        guard isCapturing else { return }
        destroyCaptureObjects()
        _ = audioBuffers.removeAll()
        Log.audio.info("System audio capture cancelled")
    }

    func reset() {
        destroyCaptureObjects()
        _ = audioBuffers.removeAll()
    }

    func setPreferredInputDeviceUID(_ uid: String) {
        _ = uid
    }

    private func handleInput(
        _ inputData: UnsafePointer<AudioBufferList>,
        sourceFormat: AVAudioFormat,
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onAudioLevel: @escaping (Float) -> Void
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

        guard let convertedBuffer = AudioCaptureUtilities.convertBuffer(
            sourceBuffer,
            from: sourceFormat,
            to: targetFormat
        ) else {
            return
        }

        audioBuffers.append(convertedBuffer)
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
        var tapUID: CFString = "" as CFString
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &tapUID)
        guard status == noErr else {
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
        var outputUID: CFString = "" as CFString
        status = AudioObjectGetPropertyData(outputDeviceID, &address, 0, nil, &size, &outputUID)
        guard status == noErr else {
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

    init(microphoneBackend: AudioCaptureBackend, systemAudioBackend: AudioCaptureBackend) {
        self.microphoneBackend = microphoneBackend
        self.systemAudioBackend = systemAudioBackend
    }

    func startCapture(
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onAudioLevel: @escaping (Float) -> Void
    ) throws {
        var microphoneLevel: Float = 0
        var systemLevel: Float = 0

        do {
            try microphoneBackend.startCapture(onBuffer: { _ in }, onAudioLevel: { level in
                microphoneLevel = level
                onAudioLevel(max(microphoneLevel, systemLevel))
            })
        } catch {
            throw error
        }

        do {
            try systemAudioBackend.startCapture(onBuffer: { _ in }, onAudioLevel: { level in
                systemLevel = level
                onAudioLevel(max(microphoneLevel, systemLevel))
            })
        } catch {
            microphoneBackend.cancelCapture()
            throw error
        }

        isCapturing = true
        _ = onBuffer
    }

    func stopCapture() throws -> [AVAudioPCMBuffer] {
        guard isCapturing else {
            throw AudioRecorderError.notRecording
        }

        let microphoneBuffers = try microphoneBackend.stopCapture()
        let systemBuffers = try systemAudioBackend.stopCapture()
        isCapturing = false

        let mixedBuffer = Self.mix(
            microphoneSamples: AudioCaptureUtilities.flattenSamples(from: microphoneBuffers),
            systemSamples: AudioCaptureUtilities.flattenSamples(from: systemBuffers),
            format: targetFormat
        )

        return mixedBuffer.map { [$0] } ?? []
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

    func setPreferredInputDeviceUID(_ uid: String) {
        microphoneBackend.setPreferredInputDeviceUID(uid)
    }

    private static func mix(
        microphoneSamples: [Float],
        systemSamples: [Float],
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let mixedCount = max(microphoneSamples.count, systemSamples.count)
        guard mixedCount > 0 else { return nil }

        var mixedSamples = Array(repeating: Float.zero, count: mixedCount)
        for index in 0..<mixedCount {
            let microphoneSample = index < microphoneSamples.count ? microphoneSamples[index] : 0
            let systemSample = index < systemSamples.count ? systemSamples[index] : 0
            mixedSamples[index] = max(-1, min(1, (microphoneSample + systemSample) * 0.5))
        }

        return AudioCaptureUtilities.makeBuffer(from: mixedSamples, format: format)
    }
}

// MARK: - AudioRecorder

@MainActor
final class AudioRecorder {
    
    private(set) var isRecording = false
    private var isStartingRecording = false
    private var currentConfiguration: AudioRecordingConfiguration = .microphone
    private var preferredInputDeviceUID: String?
    
    let permissionManager: any PermissionProviding
    private let microphoneCaptureBackend: AudioCaptureBackend
    private let systemAudioCaptureBackend: AudioCaptureBackend?
    private var activeCaptureBackend: AudioCaptureBackend?
    
    var targetFormat: AVAudioFormat {
        activeCaptureBackend?.targetFormat ?? microphoneCaptureBackend.targetFormat
    }
    
    var onAudioLevel: ((Float) -> Void)?
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    
    init(
        permissionManager: some PermissionProviding,
        captureBackend: AudioCaptureBackend? = nil,
        systemAudioCaptureBackend: AudioCaptureBackend? = nil
    ) throws {
        self.permissionManager = permissionManager
        self.microphoneCaptureBackend = try captureBackend ?? AVAudioEngineCaptureBackend()
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
            captureBackend.setPreferredInputDeviceUID(preferredInputDeviceUID)
        }

        do {
            try captureBackend.startCapture(
                onBuffer: { [weak self] buffer in
                    Task { @MainActor [weak self] in
                        self?.onAudioBuffer?(buffer)
                    }
                },
                onAudioLevel: { [weak self] level in
                    Task { @MainActor [weak self] in
                        self?.onAudioLevel?(level)
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
        
        let collectedBuffers = try activeCaptureBackend.stopCapture()
        isRecording = false
        self.activeCaptureBackend = nil
        currentConfiguration = .microphone
        
        let audioData = AudioCaptureUtilities.combineBuffersToData(collectedBuffers)
        
        Log.audio.info("Recording stopped, \(audioData.count) bytes captured")
        
        return audioData
    }
    
    func cancelRecording() {
        guard isRecording else {
            return
        }
        
        activeCaptureBackend?.cancelCapture()
        activeCaptureBackend = nil
        currentConfiguration = .microphone
        isRecording = false
        
        Log.audio.info("Recording cancelled, audio discarded")
    }
    
    func resetAudioEngine() {
        activeCaptureBackend?.reset()
        activeCaptureBackend = nil
        microphoneCaptureBackend.reset()
        systemAudioCaptureBackend?.reset()
        currentConfiguration = .microphone
        isRecording = false
        Log.audio.info("Audio engine reset")
    }

    func setPreferredInputDeviceUID(_ uid: String) {
        preferredInputDeviceUID = uid
        microphoneCaptureBackend.setPreferredInputDeviceUID(uid)
        activeCaptureBackend?.setPreferredInputDeviceUID(uid)
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
