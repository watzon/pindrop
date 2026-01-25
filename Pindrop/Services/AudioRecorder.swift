//
//  AudioRecorder.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import AVFoundation

enum AudioRecorderError: Error {
    case permissionDenied
    case notRecording
    case engineStartFailed
    case audioFormatCreationFailed
}

@MainActor
final class AudioRecorder {
    
    private let audioEngine = AVAudioEngine()
    private var audioBuffers: [AVAudioPCMBuffer] = []
    private(set) var isRecording = false
    
    let audioFormat: AVAudioFormat
    
    init() {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000.0,
            channels: 1,
            interleaved: false
        ) else {
            fatalError("Failed to create audio format")
        }
        self.audioFormat = format
    }
    
    func startRecording() async throws {
        guard await requestMicrophonePermission() else {
            throw AudioRecorderError.permissionDenied
        }
        
        audioBuffers.removeAll()
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        let mixer = AVAudioMixerNode()
        audioEngine.attach(mixer)
        
        audioEngine.connect(inputNode, to: mixer, format: inputFormat)
        
        mixer.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                if let convertedBuffer = self.convertBuffer(buffer, from: inputFormat, to: self.audioFormat) {
                    self.audioBuffers.append(convertedBuffer)
                }
            }
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            mixer.removeTap(onBus: 0)
            throw AudioRecorderError.engineStartFailed
        }
    }
    
    func stopRecording() async throws -> Data {
        guard isRecording else {
            throw AudioRecorderError.notRecording
        }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
        
        let audioData = combineBuffersToData(audioBuffers)
        audioBuffers.removeAll()
        
        return audioData
    }
    
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    private func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        from inputFormat: AVAudioFormat,
        to outputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return nil
        }
        
        let capacity = AVAudioFrameCount(
            Double(buffer.frameLength) * outputFormat.sampleRate / inputFormat.sampleRate
        )
        
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: capacity
        ) else {
            return nil
        }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        
        if error != nil {
            return nil
        }
        
        return convertedBuffer
    }
    
    private func combineBuffersToData(_ buffers: [AVAudioPCMBuffer]) -> Data {
        var data = Data()
        
        for buffer in buffers {
            guard let channelData = buffer.int16ChannelData else { continue }
            
            let frameLength = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            
            for frame in 0..<frameLength {
                for channel in 0..<channelCount {
                    let sample = channelData[channel][frame]
                    var sampleValue = sample
                    data.append(Data(bytes: &sampleValue, count: MemoryLayout<Int16>.size))
                }
            }
        }
        
        return data
    }
}
