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

enum AudioRecorderError: Error, LocalizedError {
    case permissionDenied
    case notRecording
    case engineStartFailed(String)
    case audioFormatCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .notRecording:
            return "Not currently recording"
        case .engineStartFailed(let message):
            return "Audio engine failed to start: \(message)"
        case .audioFormatCreationFailed:
            return "Failed to create audio format"
        }
    }
}

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

@MainActor
final class AudioRecorder {
    
    private var audioEngine: AVAudioEngine?
    private let audioBuffers = AudioBufferStorage()
    private(set) var isRecording = false
    private var preferredInputDeviceUID: String?
    
    private let targetFormatStorage: AVAudioFormat
    var targetFormat: AVAudioFormat {
        if targetFormatStorage.sampleRate == 0 ||
            targetFormatStorage.channelCount == 0 ||
            targetFormatStorage.commonFormat != .pcmFormatFloat32 {
            return AudioRecorder.makeFallbackFormat()
        }
        return targetFormatStorage
    }
    let permissionManager: PermissionManager
    
    var onAudioLevel: ((Float) -> Void)?
    
    nonisolated init(permissionManager: PermissionManager) throws {
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
        self.targetFormatStorage = format
        self.permissionManager = permissionManager
    }
    
    func startRecording() async throws {
        guard await permissionManager.requestPermission() else {
            throw AudioRecorderError.permissionDenied
        }
        
        if isRecording {
            return
        }
        
        _ = audioBuffers.removeAll()
        
        let engine = AVAudioEngine()
        self.audioEngine = engine
        
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
            guard let self = self else { return }

            let bufferFormat = buffer.format
            if let convertedBuffer = self.convertBuffer(buffer, from: bufferFormat, to: targetFmt) {
                bufferStorage.append(convertedBuffer)
            }
            
            let level = self.calculateAudioLevel(buffer)
            Task { @MainActor in
                self.onAudioLevel?(level)
            }
        }
        
        engine.prepare()
        
        do {
            try engine.start()
            isRecording = true
            Log.audio.info("Audio engine started")
        } catch {
            inputNode.removeTap(onBus: 0)
            engine.reset()
            self.audioEngine = nil
            throw AudioRecorderError.engineStartFailed(error.localizedDescription)
        }
    }
    
    func resetAudioEngine() {
        if let engine = audioEngine {
            if isRecording {
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
            }
        }
        audioEngine = nil
        isRecording = false
        _ = audioBuffers.removeAll()
        Log.audio.info("Audio engine reset")
    }
    
    func stopRecording() async throws -> Data {
        guard isRecording, let engine = audioEngine else {
            throw AudioRecorderError.notRecording
        }
        
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        self.audioEngine = nil
        
        let collectedBuffers = audioBuffers.removeAll()
        Log.audio.debug("Stopped recording, collected \(collectedBuffers.count) buffers")
        
        let audioData = combineBuffersToData(collectedBuffers)
        
        Log.audio.info("Recording stopped, \(audioData.count) bytes captured")
        
        return audioData
    }
    
    func cancelRecording() {
        guard isRecording, let engine = audioEngine else {
            return
        }
        
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        self.audioEngine = nil
        _ = audioBuffers.removeAll()
        
        Log.audio.info("Recording cancelled, audio discarded")
    }

    func setPreferredInputDeviceUID(_ uid: String) {
        let trimmedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        preferredInputDeviceUID = trimmedUID.isEmpty ? nil : trimmedUID
    }
    
    private func convertBuffer(
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
        
        if let error = error {
            Log.audio.error("Conversion error: \(error)")
            return nil
        }
        
        if status == .error {
            Log.audio.error("Conversion status error")
            return nil
        }
        
        return convertedBuffer
    }

    private static func makeFallbackFormat() -> AVAudioFormat {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16000.0, channels: 1) else {
            return AVAudioFormat()
        }
        return format
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
    
    private func combineBuffersToData(_ buffers: [AVAudioPCMBuffer]) -> Data {
        var allSamples: [Float] = []
        
        for buffer in buffers {
            guard let channelData = buffer.floatChannelData else { continue }
            let frameLength = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            allSamples.append(contentsOf: samples)
        }
        
        return allSamples.withUnsafeBufferPointer { bufferPointer in
            Data(buffer: bufferPointer)
        }
    }
    
    nonisolated private func calculateAudioLevel(_ buffer: AVAudioPCMBuffer) -> Float {
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
        return min(1.0 as Float, rms * 5)
    }
}
