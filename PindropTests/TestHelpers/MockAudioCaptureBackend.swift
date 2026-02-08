//
//  MockAudioCaptureBackend.swift
//  PindropTests
//
//  Created on 2026-02-08.
//

import AVFoundation
import Foundation
@testable import Pindrop

final class MockAudioCaptureBackend: AudioCaptureBackend {
    private(set) var isCapturing: Bool = false

    let targetFormat: AVAudioFormat

    var shouldThrowOnStart: Error?
    var shouldThrowOnStop: Error?
    var simulatedBuffers: [AVAudioPCMBuffer] = []

    var startCaptureCallCount: Int = 0
    var stopCaptureCallCount: Int = 0
    var cancelCaptureCallCount: Int = 0
    var resetCallCount: Int = 0
    var lastPreferredInputDeviceUID: String?

    var capturedOnBuffer: ((AVAudioPCMBuffer) -> Void)?
    var capturedOnAudioLevel: ((Float) -> Void)?

    init() {
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
        // Force unwrap is safe here — known-good parameters for 16kHz mono Float32
        self.targetFormat = AVAudioFormat(streamDescription: &streamDescription)!
    }

    func startCapture(
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onAudioLevel: @escaping (Float) -> Void
    ) throws {
        startCaptureCallCount += 1
        if let error = shouldThrowOnStart { throw error }
        capturedOnBuffer = onBuffer
        capturedOnAudioLevel = onAudioLevel
        isCapturing = true
    }

    func stopCapture() throws -> [AVAudioPCMBuffer] {
        stopCaptureCallCount += 1
        if let error = shouldThrowOnStop { throw error }
        isCapturing = false
        return simulatedBuffers
    }

    func cancelCapture() {
        cancelCaptureCallCount += 1
        isCapturing = false
    }

    func reset() {
        resetCallCount += 1
        isCapturing = false
    }

    func setPreferredInputDeviceUID(_ uid: String) {
        lastPreferredInputDeviceUID = uid
    }

    // MARK: - Test Helpers

    static func makeSynthesizedBuffer(
        format: AVAudioFormat,
        frameCount: AVAudioFrameCount = 1600,
        frequency: Float = 440.0
    ) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData else { return nil }
        let sampleRate = Float(format.sampleRate)

        for frame in 0..<Int(frameCount) {
            let sample = sin(2.0 * Float.pi * frequency * Float(frame) / sampleRate)
            channelData[0][frame] = sample * 0.5
        }

        return buffer
    }
}
