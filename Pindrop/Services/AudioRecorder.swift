//
//  AudioRecorder.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import AVFoundation
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

@MainActor
final class AudioRecorder {
    
    private var audioEngine: AVAudioEngine?
    private var audioBuffers: [AVAudioPCMBuffer] = []
    private(set) var isRecording = false
    
    let targetFormat: AVAudioFormat
    let permissionManager: PermissionManager
    
    var onAudioLevel: ((Float) -> Void)?
    
    nonisolated init(permissionManager: PermissionManager) {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000.0,
            channels: 1,
            interleaved: false
        ) else {
            fatalError("Failed to create audio format")
        }
        self.targetFormat = format
        self.permissionManager = permissionManager
    }
    
    func startRecording() async throws {
        guard await permissionManager.requestPermission() else {
            throw AudioRecorderError.permissionDenied
        }
        
        if isRecording {
            return
        }
        
        audioBuffers.removeAll()
        
        let engine = AVAudioEngine()
        self.audioEngine = engine
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        Log.audio.debug("Input format: \(inputFormat)")
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            let level = self.calculateAudioLevel(buffer)
            
            Task { @MainActor in
                self.onAudioLevel?(level)
                
                if let convertedBuffer = self.convertBuffer(buffer, from: inputFormat, to: self.targetFormat) {
                    self.audioBuffers.append(convertedBuffer)
                }
            }
        }
        
        engine.prepare()
        
        do {
            try engine.start()
            isRecording = true
            Log.audio.info("Audio engine started")
        } catch {
            inputNode.removeTap(onBus: 0)
            self.audioEngine = nil
            throw AudioRecorderError.engineStartFailed(error.localizedDescription)
        }
    }
    
    func stopRecording() async throws -> Data {
        guard isRecording, let engine = audioEngine else {
            throw AudioRecorderError.notRecording
        }
        
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        self.audioEngine = nil
        
        Log.audio.debug("Stopped recording, collected \(self.audioBuffers.count) buffers")
        
        let audioData = combineBuffersToData(audioBuffers)
        audioBuffers.removeAll()
        
        Log.audio.info("Recording stopped, \(audioData.count) bytes captured")
        
        return audioData
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
        guard let channelData = buffer.floatChannelData else { return 0 }
        
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[0][i]
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameLength))
        let normalizedLevel = min(1.0, rms * 5)
        return normalizedLevel
    }
}
